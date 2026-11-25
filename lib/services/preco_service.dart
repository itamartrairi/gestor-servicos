import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';

class PrecoSugerido {
  PrecoSugerido({
    required this.custoUnitario,
    required this.somaPct,
    this.preco,
    required this.componentes,
    this.erro,
  });
  final double custoUnitario;
  final double somaPct;
  final double? preco;
  final Map<String, double> componentes;
  final String? erro;
}

/// Tabelas de preço (varejo, atacado, promoção…) e preço sugerido pela margem.
///
/// O preço de varejo fica na variação do produto. Cada tabela aplica um ajuste
/// percentual sobre ele (ex.: −15% no atacado) ou usa um preço manual definido
/// para a variação.
class PrecoService {
  PrecoService(this.db);
  final Database db;

  /// Preço sugerido = custo unitário ÷ (1 − soma dos percentuais).
  static PrecoSugerido precoSugerido({
    required double custoUnitario,
    required double pctTaxas,
    required double pctImpostos,
    required double pctFixas,
    required double pctMargem,
  }) {
    final soma = pctTaxas + pctImpostos + pctFixas + pctMargem;
    if (soma >= 100) {
      return PrecoSugerido(
        custoUnitario: custoUnitario,
        somaPct: soma,
        componentes: const {},
        erro: 'A soma dos percentuais (${pct(soma)}) deve ser menor que 100%.',
      );
    }
    final preco = custoUnitario / (1 - soma / 100);
    return PrecoSugerido(
      custoUnitario: custoUnitario,
      somaPct: soma,
      preco: r2(preco),
      componentes: {
        'Custo unitário': r2(custoUnitario),
        'Taxas (cartão, entrega)': r2(preco * pctTaxas / 100),
        'Impostos': r2(preco * pctImpostos / 100),
        'Despesas fixas': r2(preco * pctFixas / 100),
        'Margem desejada': r2(preco * pctMargem / 100),
      },
    );
  }

  /// Custo estimado de compra: preço de venda menos o desconto do fornecedor.
  static double custoComDesconto(double precoCatalogo, double descontoPct) => r2(precoCatalogo * (1 - descontoPct / 100));

  Future<List<Map<String, Object?>>> tabelas({bool apenasAtivas = true}) =>
      db.query('tabelas_preco', where: apenasAtivas ? 'ativo = 1' : null, orderBy: 'padrao DESC, nome');

  Future<int?> tabelaPadrao({DatabaseExecutor? ex}) async {
    final r = await (ex ?? db).query('tabelas_preco', where: 'padrao = 1 AND ativo = 1', limit: 1);
    return r.isEmpty ? null : r.first['id'] as int;
  }

  Future<int> salvarTabela({int? id, required String nome, double ajustePct = 0, bool padrao = false, bool ativo = true}) async {
    if (nome.trim().isEmpty) throw RegraException('Informe o nome da tabela');
    if (ajustePct <= -100) throw RegraException('O ajuste deve ser maior que −100%');
    return db.transaction((txn) async {
      if (padrao) await txn.update('tabelas_preco', {'padrao': 0});
      final dados = {'nome': nome.trim(), 'ajuste_pct': ajustePct, 'padrao': padrao ? 1 : 0, 'ativo': ativo ? 1 : 0};
      if (id == null) return txn.insert('tabelas_preco', dados);
      await txn.update('tabelas_preco', dados, where: 'id = ?', whereArgs: [id]);
      return id;
    });
  }

  /// Exclui uma tabela de preço que não seja a padrão nem usada em pedidos.
  /// Os clientes que usavam a tabela passam a usar a padrão.
  Future<void> excluirTabela(int tabelaId) async {
    await db.transaction((txn) async {
      final t = await txn.query('tabelas_preco', where: 'id = ?', whereArgs: [tabelaId]);
      if (t.isEmpty) throw RegraException('Tabela não encontrada');
      if (Base.i(t.first['padrao']) == 1) throw RegraException('A tabela padrão não pode ser excluída. Defina outra como padrão antes.');
      final p = await txn.rawQuery('SELECT COUNT(*) c FROM pedidos WHERE tabela_id = ?', [tabelaId]);
      if (Base.i(p.first['c']) > 0) {
        throw RegraException('A tabela foi usada em pedidos. Desative-a em vez de excluir.');
      }
      await txn.update('clientes', {'tabela_id': null}, where: 'tabela_id = ?', whereArgs: [tabelaId]);
      await txn.delete('precos_tabela', where: 'tabela_id = ?', whereArgs: [tabelaId]);
      await txn.delete('tabelas_preco', where: 'id = ?', whereArgs: [tabelaId]);
    });
  }

  /// Preço manual de uma variação numa tabela. [preco] nulo remove o preço manual.
  Future<void> definirPreco(int tabelaId, int variacaoId, double? preco) async {
    if (preco == null) {
      await db.delete('precos_tabela', where: 'tabela_id = ? AND variacao_id = ?', whereArgs: [tabelaId, variacaoId]);
      return;
    }
    if (preco < 0) throw RegraException('Preço não pode ser negativo');
    await db.insert('precos_tabela', {'tabela_id': tabelaId, 'variacao_id': variacaoId, 'preco': r2(preco)},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Preço da variação na tabela: preço manual, ou varejo × (1 + ajuste%).
  Future<double> precoPara(int variacaoId, int? tabelaId, {DatabaseExecutor? ex}) async {
    final e = ex ?? db;
    final v = await e.query('variacoes', columns: ['preco_venda'], where: 'id = ?', whereArgs: [variacaoId]);
    final catalogo = v.isEmpty ? 0.0 : Base.d(v.first['preco_venda']);
    if (tabelaId == null) return catalogo;
    final manual = await e.query('precos_tabela',
        columns: ['preco'], where: 'tabela_id = ? AND variacao_id = ?', whereArgs: [tabelaId, variacaoId]);
    if (manual.isNotEmpty) return Base.d(manual.first['preco']);
    final t = await e.query('tabelas_preco', columns: ['ajuste_pct'], where: 'id = ?', whereArgs: [tabelaId]);
    final ajuste = t.isEmpty ? 0.0 : Base.d(t.first['ajuste_pct']);
    return r2(catalogo * (1 + ajuste / 100));
  }

  /// Produtos com custo médio, preço de varejo, preço na tabela e margem.
  Future<List<Map<String, Object?>>> listaDePrecos(int tabelaId) async {
    final t = (await db.query('tabelas_preco', where: 'id = ?', whereArgs: [tabelaId])).first;
    final ajuste = Base.d(t['ajuste_pct']);
    final linhas = await db.rawQuery('''
      SELECT i.id item_id, v.id variacao_id, i.nome, v.nome variacao, COALESCE(v.codigo, i.codigo) codigo,
             v.preco_venda catalogo, i.custo_medio, pt.preco manual, f.nome marca
      FROM itens i JOIN variacoes v ON v.item_id = i.id
      LEFT JOIN precos_tabela pt ON pt.variacao_id = v.id AND pt.tabela_id = ?
      LEFT JOIN fornecedores f ON f.id = i.fornecedor_id
      WHERE i.ativo = 1 AND v.ativo = 1 AND i.tipo = 'acabado'
      ORDER BY i.nome, v.nome''', [tabelaId]);
    return [
      for (final l in linhas)
        {
          ...l,
          'preco': l['manual'] != null ? Base.d(l['manual']) : r2(Base.d(l['catalogo']) * (1 + ajuste / 100)),
        }
    ];
  }

  Future<double> margemPadrao() async =>
      double.tryParse(await Base(db).config('margem_padrao_pct') ?? '30') ?? 30;
}

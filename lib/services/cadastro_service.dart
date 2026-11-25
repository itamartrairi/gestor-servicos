import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';

class CadastroService {
  CadastroService(this.db);
  final Database db;

  static const tiposItem = {
    'servico': 'Serviço',
    'acabado': 'Produto para venda (com estoque)',
  };

  static const unidadesVenda = ['un', 'atendimento', 'sessão', 'hora', 'peça', 'kit', 'kg', 'dz', 'cento', 'm'];
  static const unidadesConsumo = ['kg', 'g', 'l', 'ml', 'un', 'saco', 'muda'];

  /// Salva um item. Produtos recebem uma variação "Padrão" quando não
  /// possuem nenhuma.
  Future<int> salvarItem(Map<String, Object?> dados, {int? id}) async {
    final nome = (dados['nome'] as String?)?.trim() ?? '';
    if (nome.isEmpty) throw RegraException('Informe o nome');
    return db.transaction((txn) async {
      int itemId;
      if (id == null) {
        itemId = await txn.insert('itens', {...dados, 'criado_em': agoraIso()});
      } else {
        await txn.update('itens', dados, where: 'id = ?', whereArgs: [id]);
        itemId = id;
      }
      final tipo = dados['tipo'] as String;
      if (tipo != 'insumo' && tipo != 'embalagem') {
        final v = await txn.query('variacoes', where: 'item_id = ?', whereArgs: [itemId]);
        if (v.isEmpty) {
          await txn.insert('variacoes', {
            'item_id': itemId,
            'nome': 'Padrão',
            'unidade_venda': dados['unidade_venda'] ?? 'un',
            'preco_venda': 0,
          });
        }
      }
      return itemId;
    });
  }

  /// Consultas que, se encontrarem registros, impedem excluir um cadastro.
  /// Cada item: (SQL com um parâmetro "?", descrição do uso).
  static const dependencias = <String, List<(String, String)>>{
    'clientes': [
      ('SELECT COUNT(*) c FROM pedidos WHERE cliente_id = ?', 'pedidos'),
      ('SELECT COUNT(*) c FROM agendamentos WHERE cliente_id = ?', 'agendamentos'),
      ('SELECT COUNT(*) c FROM titulos WHERE cliente_id = ?', 'contas a receber'),
    ],
    'fornecedores': [
      ('SELECT COUNT(*) c FROM compras WHERE fornecedor_id = ?', 'compras'),
      ('SELECT COUNT(*) c FROM titulos WHERE fornecedor_id = ?', 'contas a pagar'),
      ('SELECT COUNT(*) c FROM itens WHERE fornecedor_id = ?', 'produtos'),
    ],
    'contas_financeiras': [
      ('SELECT COUNT(*) c FROM movimentos_financeiros WHERE conta_id = ?', 'movimentos financeiros'),
      ('SELECT COUNT(*) c FROM meios_pagamento WHERE conta_id = ?', 'meios de pagamento'),
      ('SELECT COUNT(*) c FROM compras WHERE conta_id = ?', 'compras'),
      ('SELECT COUNT(*) c FROM titulos WHERE conta_prevista_id = ?', 'contas a pagar/receber'),
    ],
    'meios_pagamento': [
      ('SELECT COUNT(*) c FROM pagamentos_pedido WHERE meio_id = ?', 'pagamentos de pedidos'),
      ('SELECT COUNT(*) c FROM movimentos_financeiros WHERE meio_id = ?', 'movimentos financeiros'),
    ],
    'categorias_financeiras': [
      ('SELECT COUNT(*) c FROM categorias_financeiras WHERE id = ? AND codigo IS NOT NULL', 'o sistema (categoria padrão)'),
      ('SELECT COUNT(*) c FROM titulos WHERE categoria_id = ?', 'contas a pagar/receber'),
      ('SELECT COUNT(*) c FROM movimentos_financeiros WHERE categoria_id = ?', 'movimentos financeiros'),
      ('SELECT COUNT(*) c FROM lancamentos_resultado WHERE categoria_id = ?', 'lançamentos da DRE'),
    ],
    'categorias': [
      ('SELECT COUNT(*) c FROM itens WHERE categoria_id = ?', 'produtos'),
    ],
    'itens': [
      ('SELECT COUNT(*) c FROM lotes WHERE item_id = ?', 'lotes de estoque'),
      ('SELECT COUNT(*) c FROM movimentos_estoque WHERE item_id = ?', 'movimentos de estoque'),
      ('SELECT COUNT(*) c FROM pedido_itens WHERE item_id = ?', 'pedidos'),
      ('SELECT COUNT(*) c FROM agendamentos WHERE item_id = ?', 'agendamentos'),
      ('SELECT COUNT(*) c FROM compra_itens WHERE item_id = ?', 'compras'),
    ],
    'variacoes': [
      ('SELECT COUNT(*) c FROM lotes WHERE variacao_id = ?', 'lotes de estoque'),
      ('SELECT COUNT(*) c FROM movimentos_estoque WHERE variacao_id = ?', 'movimentos de estoque'),
      ('SELECT COUNT(*) c FROM pedido_itens WHERE variacao_id = ?', 'pedidos'),
      ('SELECT COUNT(*) c FROM compra_itens WHERE variacao_id = ?', 'compras'),
    ],
  };

  /// Lança [RegraException] se o registro estiver em uso.
  static Future<void> verificarUso(DatabaseExecutor ex, String tabela, int id) async {
    final usos = <String>[];
    for (final (sql, desc) in dependencias[tabela] ?? const <(String, String)>[]) {
      final r = await ex.rawQuery(sql, [id]);
      if (((r.first['c'] as int?) ?? 0) > 0) usos.add(desc);
    }
    if (usos.isNotEmpty) {
      final temAtivo = ['clientes', 'fornecedores'].contains(tabela) ? '' : ' Se não for mais usar, desative o cadastro.';
      throw RegraException('Não é possível excluir: o cadastro é usado em ${usos.toSet().join(', ')}.$temAtivo');
    }
  }

  /// Exclui um cadastro simples (clientes, fornecedores, contas, meios, categorias).
  Future<void> excluirSimples(String tabela, int id) async {
    if (!dependencias.containsKey(tabela)) throw RegraException('Exclusão não permitida para este cadastro');
    await db.transaction((txn) async {
      await verificarUso(txn, tabela, id);
      await txn.delete(tabela, where: 'id = ?', whereArgs: [id]);
      await Base.auditar(txn, 'excluir_cadastro', entidade: tabela, entidadeId: id);
    });
  }

  /// Exclui um produto/insumo sem movimentação, com suas variações.
  Future<void> excluirItem(int itemId) async {
    await db.transaction((txn) async {
      await verificarUso(txn, 'itens', itemId);
      await txn.rawDelete('DELETE FROM precos_tabela WHERE variacao_id IN (SELECT id FROM variacoes WHERE item_id = ?)', [itemId]);
      await txn.delete('variacoes', where: 'item_id = ?', whereArgs: [itemId]);
      await txn.delete('itens', where: 'id = ?', whereArgs: [itemId]);
      await Base.auditar(txn, 'excluir_item', entidade: 'itens', entidadeId: itemId);
    });
  }

  /// Exclui uma variação sem movimentação (o produto precisa manter ao menos uma).
  Future<void> excluirVariacao(int variacaoId) async {
    await db.transaction((txn) async {
      final v = await txn.query('variacoes', where: 'id = ?', whereArgs: [variacaoId]);
      if (v.isEmpty) throw RegraException('Variação não encontrada');
      final irmas = await txn.rawQuery('SELECT COUNT(*) c FROM variacoes WHERE item_id = ?', [v.first['item_id']]);
      if (((irmas.first['c'] as int?) ?? 0) <= 1) {
        throw RegraException('O produto precisa ter ao menos uma variação. Edite esta em vez de excluir.');
      }
      await verificarUso(txn, 'variacoes', variacaoId);
      await txn.delete('precos_tabela', where: 'variacao_id = ?', whereArgs: [variacaoId]);
      await txn.delete('variacoes', where: 'id = ?', whereArgs: [variacaoId]);
    });
  }

  Future<int> salvarVariacao(Map<String, Object?> dados, {int? id}) async {
    if (((dados['nome'] as String?) ?? '').trim().isEmpty) throw RegraException('Informe o nome da variação');
    if (id == null) return db.insert('variacoes', dados);
    await db.update('variacoes', dados, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<List<Map<String, Object?>>> itens({List<String>? tipos, bool apenasAtivos = true}) {
    final w = <String>[];
    final a = <Object?>[];
    if (apenasAtivos) w.add('i.ativo = 1');
    if (tipos != null) {
      w.add('i.tipo IN (${List.filled(tipos.length, '?').join(',')})');
      a.addAll(tipos);
    }
    return db.rawQuery('''
      SELECT i.*, c.nome categoria FROM itens i LEFT JOIN categorias c ON c.id = i.categoria_id
      ${w.isEmpty ? '' : 'WHERE ${w.join(' AND ')}'} ORDER BY i.nome''', a);
  }

  /// Lista produto+variação para seleção em pedidos e compras.
  Future<List<Map<String, Object?>>> produtosVendaveis({List<String> tipos = const ['servico', 'acabado']}) {
    return db.rawQuery('''
      SELECT i.id item_id, v.id variacao_id, i.nome, v.nome variacao, i.tipo,
             v.preco_venda, v.unidade_venda, i.categoria_id, i.custo_medio, i.fornecedor_id, i.duracao_min,
             COALESCE(v.codigo, i.codigo) codigo, i.codigo_barras, f.nome marca, f.desconto_padrao_pct,
             (SELECT COALESCE(SUM(l.saldo),0) FROM lotes l WHERE l.item_id = i.id AND l.variacao_id = v.id) estoque
      FROM itens i JOIN variacoes v ON v.item_id = i.id
      LEFT JOIN fornecedores f ON f.id = i.fornecedor_id
      WHERE i.ativo = 1 AND v.ativo = 1 AND i.tipo IN (${List.filled(tipos.length, '?').join(',')})
      ORDER BY i.nome, v.nome''', tipos);
  }

  Future<List<Map<String, Object?>>> variacoes(int itemId) =>
      db.query('variacoes', where: 'item_id = ?', whereArgs: [itemId], orderBy: 'id');

  Future<List<Map<String, Object?>>> tabela(String nome, {String orderBy = 'nome'}) =>
      db.query(nome, orderBy: orderBy);

  Future<int> salvarSimples(String tabela, Map<String, Object?> dados, {int? id}) async {
    if (((dados['nome'] as String?) ?? '').trim().isEmpty) throw RegraException('Informe o nome');
    if (id == null) {
      final comData = ['clientes', 'fornecedores'].contains(tabela) ? {...dados, 'criado_em': agoraIso()} : dados;
      return db.insert(tabela, comData);
    }
    await db.update(tabela, dados, where: 'id = ?', whereArgs: [id]);
    return id;
  }
}

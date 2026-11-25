import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import 'base.dart';

class FiltroVendas {
  FiltroVendas({
    required this.inicio,
    required this.fim,
    this.itemId,
    this.variacaoId,
    this.categoriaId,
    this.canal,
  });
  final String inicio, fim;
  final int? itemId;
  final int? variacaoId;
  final int? categoriaId;
  final String? canal;

  bool get filtraProduto => itemId != null || variacaoId != null || categoriaId != null;
}

class LinhaProduto {
  LinhaProduto(this.itemId, this.variacaoId, this.nome, this.unidade);
  final int itemId;
  final int variacaoId;
  final String nome;
  final String unidade;
  double quantidade = 0, bruto = 0, desconto = 0, imposto = 0, cpv = 0;
  double? pctVariavel;
  bool variavelPendente = false;
  double get receitaLiquida => r2(bruto - desconto - imposto);
  double get precoMedio => quantidade > 0 ? bruto / quantidade : 0;
  double get custoUnitarioMedio => quantidade > 0 ? cpv / quantidade : 0;
  double get lucroBruto => r2(receitaLiquida - cpv);
  double? get margem => receitaLiquida > 0 ? lucroBruto / receitaLiquida * 100 : null;
}

class VendasCustos {
  VendasCustos({required this.filtro});
  final FiltroVendas filtro;
  int vendas = 0;
  double receitaBruta = 0, descontos = 0, devolucoes = 0, impostos = 0, cpv = 0;
  double despesasVariaveisVenda = 0;
  double? cpvVariavel;
  bool despesasRateadas = false;
  List<LinhaProduto> produtos = [];
  List<Map<String, Object?>> devolucoesLista = [];
  Map<String, double> custosProducao = {};
  /// Compras confirmadas no período.
  List<Map<String, Object?>> ordens = [];

  double get receitaLiquida => r2(receitaBruta - descontos - devolucoes - impostos);
  double get lucroBruto => r2(receitaLiquida - cpv);
  double? get margemBruta => receitaLiquida > 0 ? lucroBruto / receitaLiquida * 100 : null;
  double get ticketMedio => vendas > 0 ? receitaLiquida / vendas : 0;
  double? get margemContribuicao =>
      cpvVariavel == null ? null : r2(receitaLiquida - cpvVariavel! - despesasVariaveisVenda);
}

/// Monta os dados dos relatórios. Os números saem dos mesmos lançamentos da DRE,
/// garantindo que receita líquida, CPV e lucro bruto batam para o mesmo escopo.
class RelatorioService {
  RelatorioService(this.db);
  final Database db;

  Future<VendasCustos> vendasCustos(FiltroVendas f) async {
    final out = VendasCustos(filtro: f);
    final where = <String>['l.data >= ?', 'l.data <= ?', "l.ref_tipo = 'pedido'"];
    final args = <Object?>[f.inicio, f.fim];
    if (f.canal != null && f.canal!.isNotEmpty) {
      where.add('l.canal = ?');
      args.add(f.canal);
    }
    final whereProd = <String>[];
    final argsProd = <Object?>[];
    if (f.itemId != null) {
      whereProd.add('l.item_id = ?');
      argsProd.add(f.itemId);
    }
    if (f.variacaoId != null) {
      whereProd.add('l.variacao_id = ?');
      argsProd.add(f.variacaoId);
    }
    if (f.categoriaId != null) {
      whereProd.add('i.categoria_id = ?');
      argsProd.add(f.categoriaId);
    }
    final rows = await db.rawQuery('''
      SELECT l.*, i.nome item_nome, i.variavel_pct_cpv, i.unidade_venda i_unidade,
             v.nome var_nome, v.unidade_venda v_unidade
      FROM lancamentos_resultado l
      LEFT JOIN itens i ON i.id = l.item_id
      LEFT JOIN variacoes v ON v.id = l.variacao_id
      WHERE ${[...where, ...whereProd].join(' AND ')}
        AND l.grupo IN ('receita_bruta','desconto','imposto_venda','cpv','devolucao')
      ORDER BY l.data, l.id''', [...args, ...argsProd]);

    final mapa = <String, LinhaProduto>{};
    final pedidos = <int>{};
    for (final r in rows) {
      final grupo = r['grupo'] as String;
      final v = Base.d(r['valor']);
      if (grupo == 'devolucao') {
        out.devolucoes += v;
        out.devolucoesLista.add(r);
        continue;
      }
      if (r['ref_id'] != null && grupo == 'receita_bruta') pedidos.add(r['ref_id'] as int);
      switch (grupo) {
        case 'receita_bruta':
          out.receitaBruta += v;
          break;
        case 'desconto':
          out.descontos += v;
          break;
        case 'imposto_venda':
          out.impostos += v;
          break;
        case 'cpv':
          out.cpv += v;
          break;
      }
      final itemId = r['item_id'] as int?;
      final varId = (r['variacao_id'] as int?) ?? 0;
      final k = itemId == null ? 'frete' : '$itemId:$varId';
      final lp = mapa.putIfAbsent(k, () {
        if (itemId == null) return LinhaProduto(0, 0, 'Frete cobrado', 'serviço');
        final nome = r['var_nome'] != null ? '${r['item_nome']} - ${r['var_nome']}' : (r['item_nome'] as String? ?? '');
        final l = LinhaProduto(itemId, varId, nome, (r['v_unidade'] ?? r['i_unidade'] ?? 'un') as String);
        l.pctVariavel = r['variavel_pct_cpv'] == null ? null : Base.d(r['variavel_pct_cpv']);
        l.variavelPendente = r['variavel_pct_cpv'] == null;
        return l;
      });
      switch (grupo) {
        case 'receita_bruta':
          lp.bruto += v;
          if (r['quantidade'] != null) lp.quantidade += Base.d(r['quantidade']);
          break;
        case 'desconto':
          lp.desconto += v;
          break;
        case 'imposto_venda':
          lp.imposto += v;
          break;
        case 'cpv':
          lp.cpv += v;
          break;
      }
    }
    out.vendas = pedidos.length;
    out.produtos = mapa.values.toList()..sort((a, b) => b.receitaLiquida.compareTo(a.receitaLiquida));

    // Parcela variável do CPV.
    var pend = false;
    var cpvVar = 0.0;
    for (final p in out.produtos) {
      if (p.itemId == 0) continue;
      if (p.cpv.abs() < 0.005) continue;
      if (p.pctVariavel == null) {
        pend = true;
      } else {
        cpvVar += p.cpv * p.pctVariavel! / 100;
      }
    }
    out.cpvVariavel = pend ? null : r2(cpvVar);

    // Despesas variáveis de venda (taxas, comissões, fretes de entrega) no período.
    final dv = await db.rawQuery('''
      SELECT COALESCE(SUM(l.valor),0) s FROM lancamentos_resultado l
      LEFT JOIN categorias_financeiras c ON c.id = l.categoria_id
      WHERE l.data >= ? AND l.data <= ? AND l.grupo = 'despesa_variavel'
        AND c.codigo IN ('TAXA_CARTAO','COMISSAO','FRETE_ENTREGA')
        ${f.canal != null && f.canal!.isNotEmpty ? 'AND l.canal = ?' : ''}''',
        [f.inicio, f.fim, if (f.canal != null && f.canal!.isNotEmpty) f.canal]);
    var despVar = Base.d(dv.first['s']);
    if (f.filtraProduto) {
      // Rateio proporcional à receita bruta do escopo filtrado.
      final tot = await db.rawQuery('''
        SELECT COALESCE(SUM(valor),0) s FROM lancamentos_resultado
        WHERE data >= ? AND data <= ? AND grupo = 'receita_bruta' AND ref_tipo = 'pedido'
        ${f.canal != null && f.canal!.isNotEmpty ? 'AND canal = ?' : ''}''',
          [f.inicio, f.fim, if (f.canal != null && f.canal!.isNotEmpty) f.canal]);
      final totBruto = Base.d(tot.first['s']);
      despVar = totBruto > 0 ? despVar * out.receitaBruta / totBruto : 0;
      out.despesasRateadas = true;
    }
    out.despesasVariaveisVenda = r2(despVar);

    out.receitaBruta = r2(out.receitaBruta);
    out.descontos = r2(out.descontos);
    out.impostos = r2(out.impostos);
    out.devolucoes = r2(out.devolucoes);
    out.cpv = r2(out.cpv);

    // Compras de mercadorias confirmadas no período (vão para o estoque; separadas do CPV).
    final wo = <String>["c.status = 'confirmada'", 'c.data >= ?', 'c.data <= ?'];
    final ao = <Object?>[f.inicio, f.fim];
    if (f.itemId != null || f.variacaoId != null || f.categoriaId != null) {
      final sub = <String>[];
      if (f.itemId != null) {
        sub.add('ci.item_id = ?');
        ao.add(f.itemId);
      }
      if (f.variacaoId != null) {
        sub.add('ci.variacao_id = ?');
        ao.add(f.variacaoId);
      }
      if (f.categoriaId != null) {
        sub.add('i.categoria_id = ?');
        ao.add(f.categoriaId);
      }
      wo.add('EXISTS (SELECT 1 FROM compra_itens ci JOIN itens i ON i.id = ci.item_id WHERE ci.compra_id = c.id AND ${sub.join(' AND ')})');
    }
    out.ordens = await db.rawQuery('''
      SELECT c.*, COALESCE(fo.nome, 'Sem fornecedor') fornecedor, c.documento ciclo,
        (SELECT COALESCE(SUM(quantidade),0) FROM compra_itens WHERE compra_id = c.id) qtd_itens
      FROM compras c LEFT JOIN fornecedores fo ON fo.id = c.fornecedor_id
      WHERE ${wo.join(' AND ')} ORDER BY c.data, c.id''', ao);
    final porMarca = <String, double>{};
    for (final c in out.ordens) {
      final k = c['fornecedor'] as String;
      porMarca[k] = r2((porMarca[k] ?? 0) + Base.d(c['total']));
    }
    out.custosProducao = {
      for (final e in porMarca.entries) e.key: e.value,
      'Total comprado': r2(out.ordens.fold(0.0, (a, c) => a + Base.d(c['total']))),
    };
    return out;
  }

  Future<List<String>> canais() async {
    final r = await db.rawQuery("SELECT DISTINCT canal FROM pedidos WHERE canal IS NOT NULL AND canal <> '' ORDER BY canal");
    return r.map((e) => e['canal'] as String).toList();
  }
}

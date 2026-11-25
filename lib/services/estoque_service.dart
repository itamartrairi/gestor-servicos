import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';

class ConsumoLote {
  ConsumoLote(this.loteId, this.quantidade, this.custoUnitario);
  final int loteId;
  final double quantidade;
  final double custoUnitario;
  double get custoTotal => quantidade * custoUnitario;
}

class ResultadoConsumo {
  ResultadoConsumo(this.lotes);
  final List<ConsumoLote> lotes;
  double get quantidade => lotes.fold(0.0, (s, l) => s + l.quantidade);
  double get custoTotal => r2(lotes.fold(0.0, (s, l) => s + l.custoTotal));
  double get custoUnitario => quantidade <= 0 ? 0 : custoTotal / quantidade;
}

class SaldoItem {
  SaldoItem({
    required this.itemId,
    required this.variacaoId,
    required this.fisico,
    required this.vencido,
    required this.reservado,
  });
  final int itemId;
  final int variacaoId;
  final double fisico;
  final double vencido;
  final double reservado;
  double get valido => fisico - vencido;
  double get disponivel => valido - reservado;
}

/// Estoque de produtos de revenda (custo específico de cada lote comprado), com lotes, validade e reservas.
class EstoqueService {
  EstoqueService(this.db);
  final Database db;

  static String _hoje() => hojeIso();

  Future<SaldoItem> saldo(int itemId, int variacaoId, {DatabaseExecutor? ex, String? data}) async {
    final e = ex ?? db;
    final ref = data ?? _hoje();
    final r = await e.rawQuery('''
      SELECT COALESCE(SUM(saldo),0) AS fisico,
             COALESCE(SUM(CASE WHEN validade IS NOT NULL AND validade < ? THEN saldo ELSE 0 END),0) AS vencido
      FROM lotes WHERE item_id = ? AND variacao_id = ? AND saldo > 0.0000001
    ''', [ref, itemId, variacaoId]);
    final res = await e.rawQuery(
        'SELECT COALESCE(SUM(quantidade),0) AS q FROM reservas WHERE ativa = 1 AND item_id = ? AND variacao_id = ?',
        [itemId, variacaoId]);
    return SaldoItem(
      itemId: itemId,
      variacaoId: variacaoId,
      fisico: Base.d(r.first['fisico']),
      vencido: Base.d(r.first['vencido']),
      reservado: Base.d(res.first['q']),
    );
  }

  /// Entrada de insumo comprado: atualiza o custo médio ponderado.
  Future<int> entradaInsumo(
    DatabaseExecutor ex, {
    required int itemId,
    required double qtdConsumo,
    required double custoTotal,
    required String data,
    String? lote,
    String? validade,
    String refTipo = 'compra',
    int? refId,
    String tipoMov = 'compra',
    String? motivo,
  }) async {
    if (qtdConsumo <= 0) throw RegraException('Quantidade de entrada deve ser maior que zero');
    final it = await Base.item(ex, itemId);
    final s = await saldo(itemId, 0, ex: ex);
    final cmAtual = Base.d(it['custo_medio']);
    final saldoAtual = s.fisico < 0 ? 0.0 : s.fisico;
    final novoCm = (saldoAtual * cmAtual + custoTotal) / (saldoAtual + qtdConsumo);
    await ex.update('itens', {'custo_medio': r6(novoCm)}, where: 'id = ?', whereArgs: [itemId]);
    final loteId = await ex.insert('lotes', {
      'item_id': itemId,
      'variacao_id': 0,
      'codigo': (lote == null || lote.isEmpty) ? 'C${refId ?? ''}-${data.replaceAll('-', '')}' : lote,
      'data_fabricacao': null,
      'validade': (validade == null || validade.isEmpty) ? null : validade,
      'qtd_inicial': qtdConsumo,
      'saldo': qtdConsumo,
      'custo_unitario': r6(custoTotal / qtdConsumo),
      'origem': refTipo,
      'origem_id': refId,
      'criado_em': agoraIso(),
    });
    await ex.insert('movimentos_estoque', {
      'data': data,
      'item_id': itemId,
      'variacao_id': 0,
      'lote_id': loteId,
      'tipo': tipoMov,
      'quantidade': qtdConsumo,
      'custo_unitario': r6(custoTotal / qtdConsumo),
      'custo_total': r2(custoTotal),
      'ref_tipo': refTipo,
      'ref_id': refId,
      'motivo': motivo,
      'criado_em': agoraIso(),
    });
    return loteId;
  }

  /// Entrada de produto no estoque (lote com custo específico).
  Future<int> entradaProduzido(
    DatabaseExecutor ex, {
    required int itemId,
    required int variacaoId,
    required double quantidade,
    required double custoUnitario,
    required String codigoLote,
    required String fabricacao,
    String? validade,
    String refTipo = 'producao',
    int? refId,
    String tipoMov = 'producao',
    String? motivo,
  }) async {
    if (quantidade <= 0) throw RegraException('Quantidade de entrada deve ser maior que zero');
    final loteId = await ex.insert('lotes', {
      'item_id': itemId,
      'variacao_id': variacaoId,
      'codigo': codigoLote,
      'data_fabricacao': fabricacao,
      'validade': validade,
      'qtd_inicial': quantidade,
      'saldo': quantidade,
      'custo_unitario': r6(custoUnitario),
      'origem': refTipo,
      'origem_id': refId,
      'criado_em': agoraIso(),
    });
    await ex.insert('movimentos_estoque', {
      'data': fabricacao,
      'item_id': itemId,
      'variacao_id': variacaoId,
      'lote_id': loteId,
      'tipo': tipoMov,
      'quantidade': quantidade,
      'custo_unitario': r6(custoUnitario),
      'custo_total': r2(custoUnitario * quantidade),
      'ref_tipo': refTipo,
      'ref_id': refId,
      'motivo': motivo,
      'criado_em': agoraIso(),
    });
    return loteId;
  }

  /// Baixa por ordem de vencimento (PEPS por validade), bloqueando lotes vencidos,
  /// saldo negativo e quantidades reservadas para outros pedidos.
  /// [reservaPropria] é a quantidade reservada para esta própria operação.
  Future<ResultadoConsumo> consumir(
    DatabaseExecutor ex, {
    required int itemId,
    required int variacaoId,
    required double quantidade,
    required String data,
    required String tipoMov,
    String? refTipo,
    int? refId,
    String? motivo,
    double reservaPropria = 0,
    int? loteEspecifico,
    bool permitirVencido = false,
  }) async {
    if (quantidade <= Base.eps) return ResultadoConsumo([]);
    final it = await Base.item(ex, itemId);
    final insumo = Base.ehInsumo(it['tipo'] as String);
    final nome = await Base.nomeItem(ex, itemId, variacaoId);
    final s = await saldo(itemId, variacaoId, ex: ex, data: data);
    if (loteEspecifico == null) {
      final disponivel = s.valido - (s.reservado - reservaPropria);
      if (quantidade > disponivel + Base.eps) {
        throw RegraException(
            'Saldo insuficiente de $nome: necessário ${numero(quantidade)}, disponível ${numero(disponivel < 0 ? 0 : disponivel)}'
            '${s.vencido > 0 ? ' (há ${numero(s.vencido)} em lotes vencidos bloqueados)' : ''}.');
      }
    }
    final where = StringBuffer('item_id = ? AND variacao_id = ? AND saldo > 0.0000001');
    final args = <Object?>[itemId, variacaoId];
    if (loteEspecifico != null) {
      where.write(' AND id = ?');
      args.add(loteEspecifico);
    } else if (!permitirVencido) {
      where.write(' AND (validade IS NULL OR validade >= ?)');
      args.add(data);
    }
    final lotes = await ex.query('lotes',
        where: where.toString(),
        whereArgs: args,
        orderBy: 'CASE WHEN validade IS NULL THEN 1 ELSE 0 END, validade, id');
    var restante = quantidade;
    final consumos = <ConsumoLote>[];
    final cm = Base.d(it['custo_medio']);
    for (final l in lotes) {
      if (restante <= Base.eps) break;
      final saldoLote = Base.d(l['saldo']);
      final q = restante < saldoLote ? restante : saldoLote;
      final custoUnit = insumo ? cm : Base.d(l['custo_unitario']);
      final novoSaldo = saldoLote - q;
      await ex.update('lotes', {'saldo': novoSaldo.abs() < Base.eps ? 0 : novoSaldo},
          where: 'id = ?', whereArgs: [l['id']]);
      await ex.insert('movimentos_estoque', {
        'data': data,
        'item_id': itemId,
        'variacao_id': variacaoId,
        'lote_id': l['id'],
        'tipo': tipoMov,
        'quantidade': -q,
        'custo_unitario': r6(custoUnit),
        'custo_total': -r2(q * custoUnit),
        'ref_tipo': refTipo,
        'ref_id': refId,
        'motivo': motivo,
        'criado_em': agoraIso(),
      });
      consumos.add(ConsumoLote(l['id'] as int, q, custoUnit));
      restante -= q;
    }
    if (restante > Base.eps) {
      throw RegraException('Saldo insuficiente em lotes válidos de $nome (faltam ${numero(restante)}).');
    }
    return ResultadoConsumo(consumos);
  }

  /// Ajuste de inventário (contagem). Diferenças negativas são perdas; positivas
  /// entram ao custo médio (insumos) ou ao custo informado (produtos).
  Future<void> ajustar({
    required int itemId,
    required int variacaoId,
    required double novaQuantidade,
    required String motivo,
    double? custoUnitarioEntrada,
    String? validade,
  }) async {
    if (motivo.trim().isEmpty) throw RegraException('Informe o motivo do ajuste');
    await db.transaction((txn) async {
      final data = _hoje();
      final s = await saldo(itemId, variacaoId, ex: txn);
      final it = await Base.item(txn, itemId);
      final nome = await Base.nomeItem(txn, itemId, variacaoId);
      final dif = novaQuantidade - s.valido;
      if (dif.abs() < Base.eps) return;
      final catPerdas = await Base.categoriaFin(txn, 'PERDAS');
      if (dif < 0) {
        if (novaQuantidade < s.reservado - Base.eps) {
          throw RegraException('O novo saldo ficaria abaixo da quantidade reservada para pedidos (${numero(s.reservado)}).');
        }
        final r = await consumir(txn,
            itemId: itemId,
            variacaoId: variacaoId,
            quantidade: -dif,
            data: data,
            tipoMov: 'ajuste',
            refTipo: 'ajuste',
            motivo: motivo,
            reservaPropria: s.reservado);
        await Base.lancarResultado(txn,
            data: data,
            grupo: 'despesa_variavel',
            descricao: 'Ajuste de estoque (perda): $nome - $motivo',
            valor: r.custoTotal,
            categoriaId: catPerdas,
            refTipo: 'ajuste_estoque',
            itemId: itemId,
            variacaoId: variacaoId);
      } else {
        double custo;
        if (Base.ehInsumo(it['tipo'] as String)) {
          custo = custoUnitarioEntrada ?? Base.d(it['custo_medio']);
          await entradaInsumo(txn,
              itemId: itemId,
              qtdConsumo: dif,
              custoTotal: custo * dif,
              data: data,
              validade: validade,
              refTipo: 'ajuste',
              tipoMov: 'ajuste',
              lote: 'AJ-${data.replaceAll('-', '')}',
              motivo: motivo);
        } else {
          custo = custoUnitarioEntrada ?? 0;
          await entradaProduzido(txn,
              itemId: itemId,
              variacaoId: variacaoId,
              quantidade: dif,
              custoUnitario: custo,
              codigoLote: 'AJ-${data.replaceAll('-', '')}',
              fabricacao: data,
              validade: validade,
              refTipo: 'ajuste',
              tipoMov: 'ajuste',
              motivo: motivo);
        }
        await Base.lancarResultado(txn,
            data: data,
            grupo: 'despesa_variavel',
            descricao: 'Ajuste de estoque (sobra): $nome - $motivo',
            valor: -r2(custo * dif),
            categoriaId: catPerdas,
            refTipo: 'ajuste_estoque',
            itemId: itemId,
            variacaoId: variacaoId);
      }
      await Base.auditar(txn, 'ajuste_estoque',
          entidade: 'itens', entidadeId: itemId, motivo: motivo,
          detalhes: 'De ${numero(s.valido)} para ${numero(novaQuantidade)}');
    });
  }

  /// Descarta (perda) a quantidade de um lote, inclusive vencido.
  Future<void> registrarPerdaLote({
    required int loteId,
    required double quantidade,
    required String motivo,
  }) async {
    if (motivo.trim().isEmpty) throw RegraException('Informe o motivo da perda');
    await db.transaction((txn) async {
      final l = (await txn.query('lotes', where: 'id = ?', whereArgs: [loteId])).first;
      final itemId = l['item_id'] as int;
      final varId = l['variacao_id'] as int;
      final s = await saldo(itemId, varId, ex: txn);
      final venc = l['validade'] != null && (l['validade'] as String).compareTo(_hoje()) < 0;
      if (!venc && s.valido - quantidade < s.reservado - Base.eps) {
        throw RegraException('A perda deixaria o saldo abaixo das reservas de pedidos.');
      }
      final data = _hoje();
      final r = await consumir(txn,
          itemId: itemId,
          variacaoId: varId,
          quantidade: quantidade,
          data: data,
          tipoMov: 'perda',
          refTipo: 'perda',
          motivo: motivo,
          loteEspecifico: loteId);
      final nome = await Base.nomeItem(txn, itemId, varId);
      await Base.lancarResultado(txn,
          data: data,
          grupo: 'despesa_variavel',
          descricao: 'Perda de estoque: $nome (lote ${l['codigo']}) - $motivo',
          valor: r.custoTotal,
          categoriaId: await Base.categoriaFin(txn, 'PERDAS'),
          refTipo: 'perda_lote',
          refId: loteId,
          itemId: itemId,
          variacaoId: varId);
      await Base.auditar(txn, 'perda_lote', entidade: 'lotes', entidadeId: loteId, motivo: motivo,
          detalhes: 'Qtd ${numero(quantidade)}');
    });
  }

  // ----- Reservas -----

  Future<void> reservar(DatabaseExecutor ex,
      {required int pedidoId,
      required int pedidoItemId,
      required int itemId,
      required int variacaoId,
      required double quantidade}) async {
    if (quantidade <= Base.eps) return;
    final s = await saldo(itemId, variacaoId, ex: ex);
    if (quantidade > s.disponivel + Base.eps) {
      final nome = await Base.nomeItem(ex, itemId, variacaoId);
      throw RegraException('Disponível para reserva de $nome: ${numero(s.disponivel < 0 ? 0 : s.disponivel)}');
    }
    await ex.insert('reservas', {
      'pedido_id': pedidoId,
      'pedido_item_id': pedidoItemId,
      'item_id': itemId,
      'variacao_id': variacaoId,
      'quantidade': quantidade,
      'ativa': 1,
      'criado_em': agoraIso(),
    });
  }

  Future<double> reservadoPara(DatabaseExecutor ex, int pedidoItemId) async {
    final r = await ex.rawQuery(
        'SELECT COALESCE(SUM(quantidade),0) q FROM reservas WHERE ativa = 1 AND pedido_item_id = ?',
        [pedidoItemId]);
    return Base.d(r.first['q']);
  }

  /// Reserva o estoque livre para pedidos em aberto (confirmados ou aguardando
  /// a marca), do mais antigo para o mais novo, e marca como "pronto" os pedidos
  /// totalmente reservados. Chamado quando a mercadoria chega.
  Future<void> reservarPendentes(DatabaseExecutor ex, {int? itemId, int? variacaoId}) async {
    final w = StringBuffer("p.status IN ('confirmado','em_producao')");
    final a = <Object?>[];
    if (itemId != null) {
      w.write(' AND pi.item_id = ?');
      a.add(itemId);
    }
    if (variacaoId != null) {
      w.write(' AND pi.variacao_id = ?');
      a.add(variacaoId);
    }
    final pend = await ex.rawQuery('''
      SELECT pi.id, pi.pedido_id, pi.item_id, pi.variacao_id, pi.quantidade
      FROM pedido_itens pi JOIN pedidos p ON p.id = pi.pedido_id JOIN itens it ON it.id = pi.item_id
      WHERE $w AND it.tipo <> 'servico' ORDER BY p.data_pedido, p.id, pi.id''', a);
    final pedidos = <int>{};
    for (final pi in pend) {
      final ja = await reservadoPara(ex, pi['id'] as int);
      final falta = Base.d(pi['quantidade']) - ja;
      if (falta <= Base.eps) {
        pedidos.add(pi['pedido_id'] as int);
        continue;
      }
      final s = await saldo(pi['item_id'] as int, pi['variacao_id'] as int, ex: ex);
      final q = falta < s.disponivel ? falta : s.disponivel;
      if (q > Base.eps) {
        await reservar(ex,
            pedidoId: pi['pedido_id'] as int,
            pedidoItemId: pi['id'] as int,
            itemId: pi['item_id'] as int,
            variacaoId: pi['variacao_id'] as int,
            quantidade: q);
      }
      pedidos.add(pi['pedido_id'] as int);
    }
    for (final pid in pedidos) {
      await atualizarStatusPedidoPronto(ex, pid);
    }
  }

  /// Marca o pedido como pronto quando todos os itens estão reservados.
  Future<void> atualizarStatusPedidoPronto(DatabaseExecutor ex, int pedidoId) async {
    final p = (await ex.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
    if (!['confirmado', 'em_producao'].contains(p['status'])) return;
    final itens = await ex.rawQuery('''
      SELECT pi.* FROM pedido_itens pi JOIN itens i ON i.id = pi.item_id
      WHERE pi.pedido_id = ? AND i.tipo <> 'servico' ''', [pedidoId]);
    for (final pi in itens) {
      final r = await reservadoPara(ex, pi['id'] as int);
      if (r + Base.eps < Base.d(pi['quantidade'])) return;
    }
    await ex.update('pedidos', {'status': 'pronto'}, where: 'id = ?', whereArgs: [pedidoId]);
  }

  Future<void> liberarReservasPedido(DatabaseExecutor ex, int pedidoId) async {
    await ex.update('reservas', {'ativa': 0, 'liberada_em': agoraIso()},
        where: 'pedido_id = ? AND ativa = 1', whereArgs: [pedidoId]);
  }

  // ----- Consultas para telas -----

  Future<List<Map<String, Object?>>> listarSaldos({String? filtroTipo}) async {
    final hoje = _hoje();
    final where = filtroTipo == null
        ? "i.ativo = 1"
        : (filtroTipo == 'insumo'
            ? "i.ativo = 1 AND i.tipo IN ('insumo','embalagem')"
            : "i.ativo = 1 AND i.tipo = 'acabado'");
    return db.rawQuery('''
      SELECT i.id item_id, COALESCE(v.id,0) variacao_id, i.nome, v.nome variacao, i.tipo,
        CASE WHEN i.tipo IN ('insumo','embalagem') THEN i.unidade_consumo ELSE COALESCE(v.unidade_venda, i.unidade_venda, i.unidade_consumo) END unidade,
        CASE WHEN v.id IS NULL THEN i.estoque_minimo ELSE v.estoque_minimo END estoque_minimo,
        i.custo_medio,
        (SELECT COALESCE(SUM(l.saldo),0) FROM lotes l WHERE l.item_id = i.id AND l.variacao_id = COALESCE(v.id,0)) fisico,
        (SELECT COALESCE(SUM(l.saldo),0) FROM lotes l WHERE l.item_id = i.id AND l.variacao_id = COALESCE(v.id,0) AND l.validade IS NOT NULL AND l.validade < ?) vencido,
        (SELECT COALESCE(SUM(r.quantidade),0) FROM reservas r WHERE r.ativa = 1 AND r.item_id = i.id AND r.variacao_id = COALESCE(v.id,0)) reservado,
        (SELECT COALESCE(SUM(l.saldo * l.custo_unitario),0) FROM lotes l WHERE l.item_id = i.id AND l.variacao_id = COALESCE(v.id,0)) valor_lotes
      FROM itens i
      LEFT JOIN variacoes v ON v.item_id = i.id AND v.ativo = 1 AND i.tipo NOT IN ('insumo','embalagem')
      WHERE $where
      ORDER BY i.tipo, i.nome, v.nome
    ''', [hoje]);
  }

  Future<List<Map<String, Object?>>> lotesDoItem(int itemId, int variacaoId) {
    return db.query('lotes',
        where: 'item_id = ? AND variacao_id = ? AND saldo > 0.0000001',
        whereArgs: [itemId, variacaoId],
        orderBy: 'CASE WHEN validade IS NULL THEN 1 ELSE 0 END, validade, id');
  }

  Future<List<Map<String, Object?>>> movimentosDoItem(int itemId, int variacaoId) {
    return db.query('movimentos_estoque',
        where: 'item_id = ? AND variacao_id = ?',
        whereArgs: [itemId, variacaoId],
        orderBy: 'id DESC',
        limit: 200);
  }

  /// Alertas: abaixo do mínimo, vencendo em N dias e vencidos com saldo.
  Future<Map<String, List<Map<String, Object?>>>> alertas() async {
    final dias = int.tryParse(await Base(db).config('alerta_validade_dias') ?? '3') ?? 3;
    final hoje = _hoje();
    final limite = isoData(DateTime.now().add(Duration(days: dias)));
    final saldos = await listarSaldos();
    final minimo = saldos.where((s) {
      final min = Base.d(s['estoque_minimo']);
      final valido = Base.d(s['fisico']) - Base.d(s['vencido']);
      return min > 0 && valido < min;
    }).toList();
    final vencendo = await db.rawQuery('''
      SELECT l.*, i.nome, v.nome variacao FROM lotes l JOIN itens i ON i.id = l.item_id
      LEFT JOIN variacoes v ON v.id = l.variacao_id
      WHERE l.saldo > 0.0000001 AND l.validade IS NOT NULL AND l.validade >= ? AND l.validade <= ?
      ORDER BY l.validade''', [hoje, limite]);
    final vencidos = await db.rawQuery('''
      SELECT l.*, i.nome, v.nome variacao FROM lotes l JOIN itens i ON i.id = l.item_id
      LEFT JOIN variacoes v ON v.id = l.variacao_id
      WHERE l.saldo > 0.0000001 AND l.validade IS NOT NULL AND l.validade < ?
      ORDER BY l.validade''', [hoje]);
    return {'minimo': minimo, 'vencendo': vencendo, 'vencidos': vencidos};
  }
}

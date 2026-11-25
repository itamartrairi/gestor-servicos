import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';
import 'estoque_service.dart';
import 'financeiro_service.dart';

class ItemPedido {
  ItemPedido({
    required this.itemId,
    this.variacaoId = 0,
    required this.quantidade,
    required this.precoUnitario,
    this.unidadeVenda,
    this.personalizacao,
  });
  final int itemId;
  final int variacaoId;
  final double quantidade;
  final double precoUnitario;
  final String? unidadeVenda;
  final String? personalizacao;
}

class PagamentoInfo {
  PagamentoInfo({required this.meioId, required this.valor});
  final int meioId;
  final double valor;
}

/// Pedidos, vendas de balcão, encomendas e entregas.
class PedidoService {
  PedidoService(this.db)
      : estoque = EstoqueService(db),
        fin = FinanceiroService(db);
  final Database db;
  final EstoqueService estoque;
  final FinanceiroService fin;

  static const status = ['orcamento', 'confirmado', 'em_producao', 'pronto', 'entregue', 'cancelado'];
  static const rotulos = {
    'orcamento': 'Orçamento',
    'confirmado': 'Confirmado',
    'em_producao': 'Em andamento',
    'pronto': 'Pronto',
    'entregue': 'Entregue',
    'cancelado': 'Cancelado',
  };

  Future<void> _hist(DatabaseExecutor ex, int pedidoId, String evento, {double? valor, String? motivo}) async {
    await ex.insert('pedido_historico', {
      'pedido_id': pedidoId,
      'data': agoraIso(),
      'evento': evento,
      'valor': valor,
      'motivo': motivo,
    });
  }

  Future<Map<String, double>> totais(int pedidoId, {DatabaseExecutor? ex}) async {
    final e = ex ?? db;
    final p = (await e.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
    final r = await e.rawQuery(
        'SELECT COALESCE(SUM(quantidade*preco_unitario),0) s FROM pedido_itens WHERE pedido_id = ?', [pedidoId]);
    final pg = await e.rawQuery(
        'SELECT COALESCE(SUM(valor),0) s FROM pagamentos_pedido WHERE pedido_id = ? AND estornado = 0', [pedidoId]);
    final dev = await e.rawQuery(
        "SELECT COALESCE(SUM(valor),0) s FROM pedido_historico WHERE pedido_id = ? AND evento = 'devolucao_sinal'",
        [pedidoId]);
    final subtotal = r2(Base.d(r.first['s']));
    final total = r2(subtotal - Base.d(p['desconto']) + Base.d(p['frete']));
    final pago = r2(Base.d(pg.first['s']));
    final devolvido = r2(Base.d(dev.first['s']));
    double aReceber = 0;
    if (p['status'] == 'entregue') {
      final ts = await e.query('titulos',
          where: "ref_tipo = 'pedido' AND ref_id = ? AND tipo = 'receber' AND status IN ('aberto','parcial')",
          whereArgs: [pedidoId]);
      for (final t in ts) {
        aReceber += await fin.abertoDoTitulo(e, t);
      }
    } else if (p['status'] != 'cancelado') {
      aReceber = total - (pago - devolvido);
    }
    return {
      'subtotal': subtotal,
      'desconto': Base.d(p['desconto']),
      'frete': Base.d(p['frete']),
      'total': total,
      'pago': pago,
      'devolvido': devolvido,
      'saldo': r2(aReceber < 0 ? 0 : aReceber),
    };
  }

  Future<int> salvar({
    int? id,
    required String tipo, // balcao | encomenda | entrega
    int? clienteId,
    int? tabelaId,
    String? canal,
    required String dataPedido,
    String? dataEntrega,
    String? horaEntrega,
    double desconto = 0,
    double frete = 0,
    String? personalizacao,
    String? obs,
    required List<ItemPedido> itens,
  }) async {
    if (itens.isEmpty) throw RegraException('Inclua ao menos um produto');
    if (desconto < 0 || frete < 0) throw RegraException('Desconto e frete não podem ser negativos');
    final subtotal = itens.fold(0.0, (s, i) => s + i.quantidade * i.precoUnitario);
    if (desconto > subtotal + 0.005) throw RegraException('Desconto maior que o valor dos produtos');
    return db.transaction((txn) async {
      final dados = {
        'tipo': tipo,
        'cliente_id': clienteId,
        'tabela_id': tabelaId,
        'canal': canal,
        'data_pedido': dataPedido,
        'data_entrega': dataEntrega ?? dataPedido,
        'hora_entrega': horaEntrega,
        'desconto': r2(desconto),
        'frete': r2(frete),
        'personalizacao': personalizacao,
        'obs': obs,
      };
      int pid;
      if (id == null) {
        pid = await txn.insert('pedidos', {...dados, 'status': 'orcamento', 'criado_em': agoraIso()});
        await _hist(txn, pid, 'criado');
      } else {
        final p = (await txn.query('pedidos', where: 'id = ?', whereArgs: [id])).first;
        if (p['status'] != 'orcamento') {
          throw RegraException('Somente orçamentos podem ter itens alterados. Cancele e refaça se necessário.');
        }
        await txn.update('pedidos', dados, where: 'id = ?', whereArgs: [id]);
        await txn.delete('pedido_itens', where: 'pedido_id = ?', whereArgs: [id]);
        pid = id;
        await _hist(txn, pid, 'alterado');
      }
      for (final i in itens) {
        if (i.quantidade <= 0) throw RegraException('Quantidades devem ser maiores que zero');
        await txn.insert('pedido_itens', {
          'pedido_id': pid,
          'item_id': i.itemId,
          'variacao_id': i.variacaoId,
          'quantidade': i.quantidade,
          'preco_unitario': r2(i.precoUnitario),
          'unidade_venda': i.unidadeVenda,
          'personalizacao': i.personalizacao,
        });
      }
      return pid;
    });
  }

  /// Confirma o pedido e reserva o que houver disponível em estoque ([reservar]).
  /// Serviços não reservam estoque. Produtos que faltarem são reservados
  /// automaticamente quando a compra chegar.
  Future<void> confirmar(int pedidoId, {bool reservar = true}) async {
    await db.transaction((txn) async {
      final p = (await txn.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
      if (p['status'] != 'orcamento') throw RegraException('O pedido já foi confirmado');
      final itens = await txn.query('pedido_itens', where: 'pedido_id = ?', whereArgs: [pedidoId]);
      var precisaProduzir = false;
      for (final pi in itens) {
        final itemId = pi['item_id'] as int;
        final varId = pi['variacao_id'] as int;
        final qtd = Base.d(pi['quantidade']);
        var reservado = 0.0;
        if (Base.ehServico((await Base.item(txn, itemId))['tipo'] as String)) continue;
        if (reservar) {
          final s = await estoque.saldo(itemId, varId, ex: txn);
          final q = qtd < s.disponivel ? qtd : (s.disponivel > 0 ? s.disponivel : 0.0);
          if (q > Base.eps) {
            await estoque.reservar(txn,
                pedidoId: pedidoId, pedidoItemId: pi['id'] as int, itemId: itemId, variacaoId: varId, quantidade: q);
            reservado = q;
          }
        }
        final falta = qtd - reservado;
        if (falta > Base.eps) precisaProduzir = true;
      }
      await txn.update('pedidos', {'status': 'confirmado'}, where: 'id = ?', whereArgs: [pedidoId]);
      await _hist(txn, pedidoId, 'confirmado');
      if (!precisaProduzir) await estoque.atualizarStatusPedidoPronto(txn, pedidoId);
    });
  }

  Future<void> reservarItem(int pedidoItemId, double quantidade) async {
    await db.transaction((txn) async {
      final pi = (await txn.query('pedido_itens', where: 'id = ?', whereArgs: [pedidoItemId])).first;
      final p = (await txn.query('pedidos', where: 'id = ?', whereArgs: [pi['pedido_id']])).first;
      if (['entregue', 'cancelado'].contains(p['status'])) throw RegraException('Pedido encerrado');
      final ja = await estoque.reservadoPara(txn, pedidoItemId);
      if (ja + quantidade > Base.d(pi['quantidade']) + Base.eps) {
        throw RegraException('Reserva maior que a quantidade do pedido');
      }
      await estoque.reservar(txn,
          pedidoId: pi['pedido_id'] as int,
          pedidoItemId: pedidoItemId,
          itemId: pi['item_id'] as int,
          variacaoId: pi['variacao_id'] as int,
          quantidade: quantidade);
      await estoque.atualizarStatusPedidoPronto(txn, pi['pedido_id'] as int);
    });
  }

  Future<void> alterarStatus(int pedidoId, String novo) async {
    if (!['confirmado', 'em_producao', 'pronto'].contains(novo)) {
      throw RegraException('Use as ações de entrega ou cancelamento para esse status');
    }
    await db.transaction((txn) async {
      final p = (await txn.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
      if (['orcamento', 'entregue', 'cancelado'].contains(p['status'])) {
        throw RegraException('Não é possível alterar o status deste pedido');
      }
      await txn.update('pedidos', {'status': novo}, where: 'id = ?', whereArgs: [pedidoId]);
      await _hist(txn, pedidoId, 'status_$novo');
    });
  }

  /// Registra um pagamento do cliente. Antes da entrega é adiantamento (sinal):
  /// entra no caixa na data do recebimento e fica como adiantamento até a entrega.
  /// Depois da entrega, abate o título a receber. Cartão gera recebível da
  /// operadora com a taxa registrada uma única vez.
  Future<void> registrarPagamento({
    required int pedidoId,
    required int meioId,
    required double valor,
    required String data,
    DatabaseExecutor? ex,
  }) async {
    Future<void> run(DatabaseExecutor txn) async {
      if (valor <= 0) throw RegraException('Informe o valor do pagamento');
      final p = (await txn.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
      if (p['status'] == 'cancelado') throw RegraException('Pedido cancelado');
      final t = await totais(pedidoId, ex: txn);
      if (valor > t['saldo']! + 0.005) {
        throw RegraException('Valor maior que o saldo a receber (${brl(t['saldo'])}).');
      }
      final meio = (await txn.query('meios_pagamento', where: 'id = ?', whereArgs: [meioId])).first;
      final contaMeio = meio['conta_id'] as int? ?? 1;
      final entregue = p['status'] == 'entregue';
      final cliente = p['cliente_id'] as int?;
      final desc = '${entregue ? 'Recebimento' : 'Sinal/adiantamento'} pedido #$pedidoId (${meio['nome']})';
      int? movId;
      int? tituloCartao;

      // Parcelas do cliente (apenas após a entrega), das mais antigas para as mais novas.
      final partes = <(Map<String, Object?>, double)>[];
      if (entregue) {
        final ts = await txn.query('titulos',
            where: "ref_tipo = 'pedido' AND ref_id = ? AND tipo = 'receber' AND status IN ('aberto','parcial')",
            whereArgs: [pedidoId],
            orderBy: 'COALESCE(nova_previsao, vencimento), id');
        if (ts.isEmpty) throw RegraException('Não há saldo a receber neste pedido');
        var resta = r2(valor);
        for (final t in ts) {
          if (resta <= 0.005) break;
          final aberto = await fin.abertoDoTitulo(txn, t);
          if (aberto <= 0.005) continue;
          final parte = resta < aberto ? resta : aberto;
          partes.add((t, r2(parte)));
          resta = r2(resta - parte);
        }
      }
      final tituloCliente = partes.isEmpty ? null : partes.first.$1;

      if (meio['tipo'] == 'cartao') {
        final taxa = r2(valor * Base.d(meio['taxa_pct']) / 100);
        final liquido = r2(valor - taxa);
        final venc = isoData(parseIso(data).add(Duration(days: Base.i(meio['dias_repasse']))));
        tituloCartao = await fin.criarTitulo(txn,
            tipo: 'receber',
            descricao: 'Repasse ${meio['nome']} - pedido #$pedidoId',
            categoriaId: await Base.categoriaFin(txn, 'CARTAO_REPASSE'),
            valor: liquido,
            valorBruto: valor,
            taxaPrevista: taxa,
            vencimento: venc,
            competencia: data,
            refTipo: 'cartao',
            refId: pedidoId,
            contaPrevistaId: contaMeio);
        await Base.lancarResultado(txn,
            data: data,
            grupo: 'despesa_variavel',
            descricao: 'Taxa ${meio['nome']} - pedido #$pedidoId',
            valor: taxa,
            categoriaId: await Base.categoriaFin(txn, 'TAXA_CARTAO'),
            refTipo: 'pedido',
            refId: pedidoId,
            canal: p['canal'] as String?);
        for (final (t, parte) in partes) {
          final atual = (await txn.query('titulos', where: 'id = ?', whereArgs: [t['id']])).first;
          await txn.update('titulos', {
            'valor_compensado': r2(Base.d(atual['valor_compensado']) + parte),
          }, where: 'id = ?', whereArgs: [t['id']]);
          final pago = await fin.pagoDoTitulo(txn, t['id'] as int);
          await txn.update('titulos', {'status': pago >= Base.d(atual['valor']) - 0.005 ? 'quitado' : 'parcial'},
              where: 'id = ?', whereArgs: [t['id']]);
        }
      } else if (tituloCliente != null) {
        for (final (t, parte) in partes) {
          movId = await fin.baixarTitulo(
              ex: txn, tituloId: t['id'] as int, data: data, contaId: contaMeio, principal: parte, meioId: meioId);
        }
      } else {
        movId = await fin.criarMovimento(txn,
            data: data,
            contaId: contaMeio,
            tipo: 'entrada',
            valor: valor,
            categoriaId: await Base.categoriaFin(txn, 'ADIANT_CLIENTE'),
            descricao: desc,
            refTipo: 'pedido_pagamento',
            refId: pedidoId,
            meioId: meioId);
      }
      await txn.insert('pagamentos_pedido', {
        'pedido_id': pedidoId,
        'data': data,
        'meio_id': meioId,
        'valor': r2(valor),
        'movimento_id': movId,
        'titulo_cartao_id': tituloCartao,
        'criado_em': agoraIso(),
      });
      if (cliente != null && tituloCartao != null) {
        await txn.update('titulos', {'cliente_id': cliente}, where: 'id = ?', whereArgs: [tituloCartao]);
      }
      await _hist(txn, pedidoId, entregue ? 'recebimento' : 'sinal', valor: valor);
    }

    if (ex != null) return run(ex);
    return db.transaction(run);
  }

  /// Entrega/finaliza: baixa o estoque uma única vez (lotes válidos por vencimento),
  /// reconhece receita e CPV, abate adiantamentos e gera o saldo a receber.
  Future<void> entregar({
    required int pedidoId,
    required String data,
    List<PagamentoInfo> pagamentos = const [],
    String? vencimentoSaldo,
    int parcelas = 1,
    int intervaloDias = 30,
    bool ignorarLimite = false,
  }) async {
    if (parcelas < 1 || parcelas > 24) throw RegraException('Parcelas devem estar entre 1 e 24');
    if (intervaloDias < 1) throw RegraException('Intervalo entre parcelas inválido');
    await db.transaction((txn) async {
      final p = (await txn.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
      if (p['status'] == 'entregue') throw RegraException('Este pedido já foi entregue.');
      if (p['status'] == 'cancelado') throw RegraException('Pedido cancelado');
      final upd = await txn.update('pedidos', {'status': 'entregue', 'entregue_em': agoraIso(), 'data_competencia': data},
          where: "id = ? AND status NOT IN ('entregue','cancelado')", whereArgs: [pedidoId]);
      if (upd != 1) throw RegraException('Entrega duplicada bloqueada.');
      final itens = await txn.query('pedido_itens', where: 'pedido_id = ?', whereArgs: [pedidoId]);
      final canal = p['canal'] as String?;
      final t0 = await totais(pedidoId, ex: txn);
      final subtotal = t0['subtotal']!;
      final desconto = Base.d(p['desconto']);
      final frete = Base.d(p['frete']);
      final pctImposto = double.tryParse((await Base(db).config('pct_imposto_vendas', ex: txn)) ?? '0') ?? 0;
      final catImposto = await Base.categoriaFin(txn, 'IMPOSTO_VENDA');

      // Libera reservas do próprio pedido antes de baixar (não conta como reservado por terceiros).
      await estoque.liberarReservasPedido(txn, pedidoId);
      var descontoAlocado = 0.0;
      for (var idx = 0; idx < itens.length; idx++) {
        final pi = itens[idx];
        final itemId = pi['item_id'] as int;
        final varId = pi['variacao_id'] as int;
        final qtd = Base.d(pi['quantidade']);
        final bruto = r2(qtd * Base.d(pi['preco_unitario']));
        final itemInfo = await Base.item(txn, itemId);
        double custoItem;
        if (Base.ehServico(itemInfo['tipo'] as String)) {
          // Serviço: sem estoque; o custo é o material previsto por atendimento.
          custoItem = r2(Base.d(itemInfo['custo_medio']) * qtd);
        } else {
          final res = await estoque.consumir(txn,
              itemId: itemId,
              variacaoId: varId,
              quantidade: qtd,
              data: data,
              tipoMov: 'venda',
              refTipo: 'pedido',
              refId: pedidoId);
          custoItem = res.custoTotal;
        }
        await txn.update('pedido_itens', {'custo_total': custoItem}, where: 'id = ?', whereArgs: [pi['id']]);
        final nome = await Base.nomeItem(txn, itemId, varId);
        double descItem;
        if (idx == itens.length - 1) {
          descItem = r2(desconto - descontoAlocado);
        } else {
          descItem = subtotal > 0 ? r2(desconto * bruto / subtotal) : 0;
          descontoAlocado += descItem;
        }
        final base = '$pedidoId:${pi['id']}';
        await Base.lancarResultado(txn,
            data: data, grupo: 'receita_bruta', descricao: 'Venda: $nome (pedido #$pedidoId)',
            valor: bruto, refTipo: 'pedido', refId: pedidoId, itemId: itemId, variacaoId: varId,
            quantidade: qtd, canal: canal, chave: 'ped:$base:receita');
        if (descItem.abs() >= 0.005) {
          await Base.lancarResultado(txn,
              data: data, grupo: 'desconto', descricao: 'Desconto: $nome (pedido #$pedidoId)',
              valor: descItem, refTipo: 'pedido', refId: pedidoId, itemId: itemId, variacaoId: varId,
              canal: canal, chave: 'ped:$base:desconto');
        }
        if (pctImposto > 0) {
          await Base.lancarResultado(txn,
              data: data, grupo: 'imposto_venda', descricao: 'Imposto sobre venda: $nome (pedido #$pedidoId)',
              valor: r2((bruto - descItem) * pctImposto / 100), categoriaId: catImposto, refTipo: 'pedido',
              refId: pedidoId, itemId: itemId, variacaoId: varId, canal: canal, chave: 'ped:$base:imposto');
        }
        await Base.lancarResultado(txn,
            data: data, grupo: 'cpv', descricao: 'CPV: $nome (pedido #$pedidoId)',
            valor: custoItem, refTipo: 'pedido', refId: pedidoId, itemId: itemId, variacaoId: varId,
            quantidade: qtd, canal: canal, chave: 'ped:$base:cpv');
      }
      if (frete >= 0.005) {
        await Base.lancarResultado(txn,
            data: data, grupo: 'receita_bruta', descricao: 'Frete cobrado (pedido #$pedidoId)',
            valor: frete, refTipo: 'pedido', refId: pedidoId, canal: canal, chave: 'ped:$pedidoId:frete');
        if (pctImposto > 0) {
          await Base.lancarResultado(txn,
              data: data, grupo: 'imposto_venda', descricao: 'Imposto sobre frete (pedido #$pedidoId)',
              valor: r2(frete * pctImposto / 100), categoriaId: catImposto, refTipo: 'pedido', refId: pedidoId,
              canal: canal, chave: 'ped:$pedidoId:frete_imposto');
        }
      }

      // Adiantamentos já recebidos abatem o total; só o saldo vira conta a receber.
      final total = t0['total']!;
      final adiantado = r2(t0['pago']! - t0['devolvido']!);
      if (adiantado > total + 0.005) {
        throw RegraException('Os adiantamentos (${brl(adiantado)}) superam o total do pedido. Registre a devolução da diferença antes de entregar.');
      }
      final saldo = r2(total - adiantado);
      final pagoAgora = r2(pagamentos.fold(0.0, (s, pg) => s + (pg.valor > 0 ? pg.valor : 0)));
      final fiado = r2(saldo - pagoAgora);
      final clienteId = p['cliente_id'] as int?;
      if (fiado >= 0.005) {
        if (clienteId == null) {
          throw RegraException('Para vender a prazo (fiado), informe o cliente.');
        }
        final cli = (await txn.query('clientes', where: 'id = ?', whereArgs: [clienteId])).first;
        final limite = Base.d(cli['limite_credito']);
        if (limite > 0 && !ignorarLimite) {
          final r = await txn.rawQuery('''
            SELECT t.* FROM titulos t WHERE t.tipo = 'receber' AND t.ref_tipo = 'pedido'
            AND t.cliente_id = ? AND t.status IN ('aberto','parcial')''', [clienteId]);
          var devendo = 0.0;
          for (final t in r) {
            devendo += await fin.abertoDoTitulo(txn, t);
          }
          if (devendo + fiado > limite + 0.005) {
            throw RegraException('Limite de crédito de ${cli['nome']} excedido: limite ${brl(limite)}, '
                'em aberto ${brl(devendo)}, esta venda ${brl(fiado)}.');
          }
        }
      }
      if (saldo >= 0.005) {
        // O valor pago na hora quita a 1ª parte; o restante (fiado) é parcelado.
        final n = fiado >= 0.005 ? parcelas : 1;
        final partes = <double>[
          if (pagoAgora >= 0.005) pagoAgora,
          if (fiado >= 0.005) ...FinanceiroService.dividir(fiado, n),
        ];
        final venc0 = parseIso(vencimentoSaldo ?? isoData(parseIso(data).add(Duration(days: intervaloDias))));
        final catReceb = await Base.categoriaFin(txn, 'VENDA_RECEB');
        var k = 0;
        for (var idx = 0; idx < partes.length; idx++) {
          final avista = pagoAgora >= 0.005 && idx == 0;
          final venc = avista ? data : isoData(venc0.add(Duration(days: intervaloDias * k)));
          final rotulo = avista
              ? 'Pedido #$pedidoId - pagamento na entrega'
              : (n > 1 ? 'Pedido #$pedidoId - parcela ${k + 1}/$n' : 'Pedido #$pedidoId - saldo');
          await fin.criarTitulo(txn,
              tipo: 'receber',
              descricao: rotulo,
              categoriaId: catReceb,
              valor: partes[idx],
              vencimento: venc,
              competencia: data,
              clienteId: clienteId,
              refTipo: 'pedido',
              refId: pedidoId,
              parcela: avista ? 1 : k + 1,
              totalParcelas: avista ? 1 : n);
          if (!avista) k++;
        }
      }
      await _hist(txn, pedidoId, 'entregue', valor: total,
          motivo: adiantado > 0 ? 'Adiantamentos abatidos: ${brl(adiantado)}' : null);
      for (final pg in pagamentos) {
        if (pg.valor <= 0) continue;
        await registrarPagamento(pedidoId: pedidoId, meioId: pg.meioId, valor: pg.valor, data: data, ex: txn);
      }
    });
  }

  /// Venda de balcão: cria e finaliza na hora, com pagamentos (inclusive mistos).
  Future<int> vendaBalcao({
    int? clienteId,
    int? tabelaId,
    String canal = 'Venda direta',
    required String data,
    double desconto = 0,
    required List<ItemPedido> itens,
    required List<PagamentoInfo> pagamentos,
    int parcelas = 1,
    int intervaloDias = 30,
    String? vencimentoSaldo,
    bool ignorarLimite = false,
  }) async {
    final id = await salvar(
        tipo: 'balcao',
        clienteId: clienteId,
        tabelaId: tabelaId,
        canal: canal,
        dataPedido: data,
        desconto: desconto,
        itens: itens);
    try {
      await entregar(
          pedidoId: id,
          data: data,
          pagamentos: pagamentos,
          parcelas: parcelas,
          intervaloDias: intervaloDias,
          vencimentoSaldo: vencimentoSaldo,
          ignorarLimite: ignorarLimite);
    } catch (e) {
      await db.delete('pedido_historico', where: 'pedido_id = ?', whereArgs: [id]);
      await db.delete('pedidos', where: 'id = ?', whereArgs: [id]);
      rethrow;
    }
    return id;
  }

  /// Exclui um pedido que não teve efeito financeiro (orçamento, confirmado sem
  /// pagamento ou cancelado sem sinal): libera as reservas e apaga o pedido.
  /// Pedidos entregues ou com pagamentos devem ser cancelados/estornados.
  Future<void> excluir(int pedidoId) async {
    await db.transaction((txn) async {
      final r = await txn.query('pedidos', where: 'id = ?', whereArgs: [pedidoId]);
      if (r.isEmpty) throw RegraException('Pedido não encontrado');
      final p = r.first;
      if (p['status'] == 'entregue') {
        throw RegraException('Pedido entregue não pode ser excluído: use o estorno de venda.');
      }
      final pags = await txn.rawQuery('SELECT COUNT(*) c FROM pagamentos_pedido WHERE pedido_id = ?', [pedidoId]);
      if (Base.i(pags.first['c']) > 0) {
        throw RegraException('O pedido tem pagamento/sinal registrado. Cancele o pedido (devolvendo o sinal) em vez de excluir.');
      }
      final fin1 = await txn.rawQuery(
          "SELECT COUNT(*) c FROM titulos WHERE ref_tipo = 'pedido' AND ref_id = ?", [pedidoId]);
      final dre = await txn.rawQuery(
          "SELECT COUNT(*) c FROM lancamentos_resultado WHERE ref_tipo = 'pedido' AND ref_id = ?", [pedidoId]);
      if (Base.i(fin1.first['c']) > 0 || Base.i(dre.first['c']) > 0) {
        throw RegraException('O pedido já gerou lançamentos financeiros e não pode ser excluído.');
      }
      await txn.delete('reservas', where: 'pedido_id = ?', whereArgs: [pedidoId]);
      await desvincularPedido(txn, pedidoId);
      await txn.delete('pedido_historico', where: 'pedido_id = ?', whereArgs: [pedidoId]);
      await txn.delete('pedido_itens', where: 'pedido_id = ?', whereArgs: [pedidoId]);
      await txn.delete('pedidos', where: 'id = ?', whereArgs: [pedidoId]);
      await Base.auditar(txn, 'excluir_pedido', entidade: 'pedidos', entidadeId: pedidoId);
    });
  }

  /// Remove vínculos de outras tabelas com o pedido antes de excluí-lo.
  Future<void> desvincularPedido(DatabaseExecutor txn, int pedidoId) async {
    // Nada a desvincular nesta versão (reservas já são removidas).
  }

  /// Cancela pedido não entregue: libera reservas e registra a devolução do sinal.
  /// O valor não devolvido fica como receita de sinal retido.
  Future<void> cancelar({
    required int pedidoId,
    required String motivo,
    double valorDevolvido = 0,
    int? contaDevolucaoId,
    String? data,
  }) async {
    if (motivo.trim().isEmpty) throw RegraException('Informe o motivo do cancelamento');
    await db.transaction((txn) async {
      final p = (await txn.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
      if (p['status'] == 'entregue') throw RegraException('Pedido entregue: use o estorno de venda');
      if (p['status'] == 'cancelado') throw RegraException('Pedido já cancelado');
      final dt = data ?? hojeIso();
      final t = await totais(pedidoId, ex: txn);
      final adiantado = r2(t['pago']! - t['devolvido']!);
      if (valorDevolvido > adiantado + 0.005) {
        throw RegraException('Devolução maior que o valor recebido (${brl(adiantado)}).');
      }
      await estoque.liberarReservasPedido(txn, pedidoId);
      if (valorDevolvido > 0) {
        if (contaDevolucaoId == null) throw RegraException('Selecione a conta da devolução');
        final saldoConta = await fin.saldoConta(contaDevolucaoId, ex: txn);
        if (valorDevolvido > saldoConta + 0.005) {
          throw RegraException('Saldo insuficiente na conta (${brl(saldoConta)}).');
        }
        await fin.criarMovimento(txn,
            data: dt,
            contaId: contaDevolucaoId,
            tipo: 'saida',
            valor: valorDevolvido,
            categoriaId: await Base.categoriaFin(txn, 'DEVOL_CLIENTE'),
            descricao: 'Devolução de sinal - pedido #$pedidoId',
            refTipo: 'pedido_devolucao',
            refId: pedidoId,
            motivo: motivo);
        await _hist(txn, pedidoId, 'devolucao_sinal', valor: valorDevolvido, motivo: motivo);
      }
      final retido = r2(adiantado - valorDevolvido);
      if (retido >= 0.005) {
        await Base.lancarResultado(txn,
            data: dt,
            grupo: 'receita_financeira',
            descricao: 'Sinal retido - pedido #$pedidoId cancelado',
            valor: retido,
            categoriaId: await Base.categoriaFin(txn, 'OUTRAS_REC'),
            refTipo: 'pedido',
            refId: pedidoId,
            chave: 'ped:$pedidoId:sinal_retido');
      }
      await txn.update('pedidos', {'status': 'cancelado', 'cancelado_em': agoraIso(), 'motivo_cancelamento': motivo},
          where: 'id = ?', whereArgs: [pedidoId]);
      await _hist(txn, pedidoId, 'cancelado', motivo: motivo);
      await Base.auditar(txn, 'cancelar_pedido', entidade: 'pedidos', entidadeId: pedidoId, motivo: motivo);
    });
  }

  /// Estorno/devolução de venda entregue. Reduz a receita (devolução) na data do
  /// estorno, abate do saldo a receber e devolve o restante em dinheiro.
  Future<void> estornarVenda({
    required int pedidoId,
    required double valor,
    required String motivo,
    int? contaDevolucaoId,
    String? data,
  }) async {
    if (motivo.trim().isEmpty) throw RegraException('Informe o motivo do estorno');
    if (valor <= 0) throw RegraException('Informe o valor do estorno');
    await db.transaction((txn) async {
      final p = (await txn.query('pedidos', where: 'id = ?', whereArgs: [pedidoId])).first;
      if (p['status'] != 'entregue') throw RegraException('Somente vendas entregues podem ser estornadas');
      final t = await totais(pedidoId, ex: txn);
      final jaEstornado = await txn.rawQuery(
          "SELECT COALESCE(SUM(valor),0) s FROM pedido_historico WHERE pedido_id = ? AND evento = 'estorno_venda'",
          [pedidoId]);
      final limite = r2(t['total']! - Base.d(jaEstornado.first['s']));
      if (valor > limite + 0.005) throw RegraException('Estorno maior que o valor da venda (${brl(limite)})');
      final dt = data ?? hojeIso();
      await Base.lancarResultado(txn,
          data: dt,
          grupo: 'devolucao',
          descricao: 'Devolução/estorno - pedido #$pedidoId: $motivo',
          valor: valor,
          refTipo: 'pedido',
          refId: pedidoId,
          canal: p['canal'] as String?);
      var restante = valor;
      final ts = await txn.query('titulos',
          where: "ref_tipo = 'pedido' AND ref_id = ? AND tipo = 'receber' AND status IN ('aberto','parcial')",
          whereArgs: [pedidoId]);
      for (final ti in ts) {
        if (restante <= 0.005) break;
        final aberto = await fin.abertoDoTitulo(txn, ti);
        final abate = restante < aberto ? restante : aberto;
        await txn.update('titulos', {'valor_compensado': r2(Base.d(ti['valor_compensado']) + abate)},
            where: 'id = ?', whereArgs: [ti['id']]);
        final pago = await fin.pagoDoTitulo(txn, ti['id'] as int);
        await txn.update('titulos', {'status': pago >= Base.d(ti['valor']) - 0.005 ? 'quitado' : 'parcial'},
            where: 'id = ?', whereArgs: [ti['id']]);
        restante = r2(restante - abate);
      }
      if (restante > 0.005) {
        if (contaDevolucaoId == null) throw RegraException('Selecione a conta para devolver ${brl(restante)}');
        await fin.criarMovimento(txn,
            data: dt,
            contaId: contaDevolucaoId,
            tipo: 'saida',
            valor: restante,
            categoriaId: await Base.categoriaFin(txn, 'DEVOL_CLIENTE'),
            descricao: 'Estorno de venda - pedido #$pedidoId',
            refTipo: 'pedido_estorno',
            refId: pedidoId,
            motivo: motivo);
      }
      await _hist(txn, pedidoId, 'estorno_venda', valor: valor, motivo: motivo);
      await Base.auditar(txn, 'estorno_venda', entidade: 'pedidos', entidadeId: pedidoId, motivo: motivo,
          detalhes: 'Valor ${brl(valor)}');
    });
  }

  // ----- Consultas -----

  Future<List<Map<String, Object?>>> listar({List<String>? statusIn, String? busca}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (statusIn != null && statusIn.isNotEmpty) {
      where.add('p.status IN (${List.filled(statusIn.length, '?').join(',')})');
      args.addAll(statusIn);
    }
    if (busca != null && busca.isNotEmpty) {
      where.add('(c.nome LIKE ? OR CAST(p.id AS TEXT) = ?)');
      args.addAll(['%$busca%', busca]);
    }
    return db.rawQuery('''
      SELECT p.*, c.nome cliente,
        (SELECT COALESCE(SUM(quantidade*preco_unitario),0) FROM pedido_itens WHERE pedido_id = p.id) - p.desconto + p.frete total
      FROM pedidos p LEFT JOIN clientes c ON c.id = p.cliente_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY CASE WHEN p.status IN ('entregue','cancelado') THEN 1 ELSE 0 END,
        COALESCE(p.data_entrega, p.data_pedido) ${statusIn != null && statusIn.contains('entregue') ? 'DESC' : 'ASC'}, p.hora_entrega, p.id DESC
      LIMIT 300''', args);
  }

  Future<List<Map<String, Object?>>> itens(int pedidoId) => db.rawQuery('''
      SELECT pi.*, i.nome, i.tipo, v.nome variacao,
        (SELECT COALESCE(SUM(quantidade),0) FROM reservas r WHERE r.pedido_item_id = pi.id AND r.ativa = 1) reservado
      FROM pedido_itens pi JOIN itens i ON i.id = pi.item_id LEFT JOIN variacoes v ON v.id = pi.variacao_id
      WHERE pi.pedido_id = ?''', [pedidoId]);

  Future<List<Map<String, Object?>>> historico(int pedidoId) =>
      db.query('pedido_historico', where: 'pedido_id = ?', whereArgs: [pedidoId], orderBy: 'id');

  Future<List<Map<String, Object?>>> pagamentos(int pedidoId) => db.rawQuery('''
      SELECT pp.*, m.nome meio FROM pagamentos_pedido pp JOIN meios_pagamento m ON m.id = pp.meio_id
      WHERE pp.pedido_id = ? ORDER BY pp.id''', [pedidoId]);

  Future<List<Map<String, Object?>>> proximasEntregas({int limite = 10}) => db.rawQuery('''
      SELECT p.*, c.nome cliente FROM pedidos p LEFT JOIN clientes c ON c.id = p.cliente_id
      WHERE p.status IN ('confirmado','em_producao','pronto')
      ORDER BY p.data_entrega, p.hora_entrega LIMIT ?''', [limite]);
}

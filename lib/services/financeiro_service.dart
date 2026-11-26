import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';

/// Contas a pagar/receber, movimentos de caixa, transferências e fluxo de caixa.
class FinanceiroService {
  FinanceiroService(this.db);
  final Database db;

  // ---------- Saldos ----------

  Future<double> saldoConta(int contaId, {String? ateData, DatabaseExecutor? ex}) async {
    final e = ex ?? db;
    final c = await e.query('contas_financeiras', where: 'id = ?', whereArgs: [contaId]);
    if (c.isEmpty) return 0;
    final ini = Base.d(c.first['saldo_inicial']);
    final r = await e.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN tipo='entrada' THEN valor ELSE -valor END),0) s
      FROM movimentos_financeiros WHERE conta_id = ? ${ateData != null ? 'AND data <= ?' : ''}
    ''', [contaId, if (ateData != null) ateData]);
    return r2(ini + Base.d(r.first['s']));
  }

  /// Saldo consolidado (todas as contas) ou de uma conta, até a data (inclusive).
  Future<double> saldo({int? contaId, String? ateData}) async {
    if (contaId != null) return saldoConta(contaId, ateData: ateData);
    final contas = await db.query('contas_financeiras');
    var total = 0.0;
    for (final c in contas) {
      total += await saldoConta(c['id'] as int, ateData: ateData);
    }
    return r2(total);
  }

  Future<double> pagoDoTitulo(DatabaseExecutor ex, int tituloId) async {
    final r = await ex.rawQuery('''
      SELECT COALESCE(SUM(CASE WHEN estorno_de IS NULL THEN valor_principal ELSE -valor_principal END),0) p
      FROM movimentos_financeiros WHERE titulo_id = ?''', [tituloId]);
    final t = await ex.query('titulos', columns: ['valor_compensado'], where: 'id = ?', whereArgs: [tituloId]);
    return r2(Base.d(r.first['p']) + (t.isEmpty ? 0 : Base.d(t.first['valor_compensado'])));
  }

  Future<double> abertoDoTitulo(DatabaseExecutor ex, Map<String, Object?> t) async {
    if (t['status'] == 'cancelado') return 0;
    return r2(Base.d(t['valor']) - await pagoDoTitulo(ex, t['id'] as int));
  }

  Future<void> _atualizarStatus(DatabaseExecutor ex, int tituloId) async {
    final t = (await ex.query('titulos', where: 'id = ?', whereArgs: [tituloId])).first;
    if (t['status'] == 'cancelado') return;
    final pago = await pagoDoTitulo(ex, tituloId);
    final valor = Base.d(t['valor']);
    final st = pago >= valor - 0.005 ? 'quitado' : (pago > 0.005 ? 'parcial' : 'aberto');
    await ex.update('titulos', {'status': st}, where: 'id = ?', whereArgs: [tituloId]);
  }

  // ---------- Movimentos ----------

  Future<int> criarMovimento(
    DatabaseExecutor ex, {
    required String data,
    required int contaId,
    required String tipo,
    required double valor,
    required int categoriaId,
    required String descricao,
    int? tituloId,
    double valorPrincipal = 0,
    double juros = 0,
    double desconto = 0,
    double tarifa = 0,
    String? refTipo,
    int? refId,
    String? transferenciaId,
    int? meioId,
    int? estornoDe,
    String? motivo,
    String? chave,
  }) async {
    if (valor < 0) throw RegraException('Valor do movimento não pode ser negativo');
    try {
      return await ex.insert('movimentos_financeiros', {
        'data': data,
        'conta_id': contaId,
        'tipo': tipo,
        'valor': r2(valor),
        'categoria_id': categoriaId,
        'descricao': descricao,
        'titulo_id': tituloId,
        'valor_principal': r2(valorPrincipal),
        'juros': r2(juros),
        'desconto': r2(desconto),
        'tarifa': r2(tarifa),
        'ref_tipo': refTipo,
        'ref_id': refId,
        'transferencia_id': transferenciaId,
        'meio_id': meioId,
        'estorno_de': estornoDe,
        'motivo': motivo,
        'chave': chave,
        'criado_em': agoraIso(),
      });
    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        throw RegraException('Este lançamento já foi registrado (confirmação duplicada bloqueada).');
      }
      rethrow;
    }
  }

  Future<int> criarTitulo(
    DatabaseExecutor ex, {
    required String tipo,
    required String descricao,
    required int categoriaId,
    required double valor,
    required String vencimento,
    required String competencia,
    int? clienteId,
    int? fornecedorId,
    String? refTipo,
    int? refId,
    int parcela = 1,
    int totalParcelas = 1,
    double? valorBruto,
    double? taxaPrevista,
    int? contaPrevistaId,
  }) async {
    if (valor <= 0) throw RegraException('Valor do título deve ser maior que zero');
    return ex.insert('titulos', {
      'tipo': tipo,
      'descricao': descricao,
      'categoria_id': categoriaId,
      'cliente_id': clienteId,
      'fornecedor_id': fornecedorId,
      'ref_tipo': refTipo,
      'ref_id': refId,
      'parcela': parcela,
      'total_parcelas': totalParcelas,
      'valor': r2(valor),
      'valor_bruto': valorBruto,
      'taxa_prevista': taxaPrevista,
      'vencimento': vencimento,
      'competencia': competencia,
      'conta_prevista_id': contaPrevistaId,
      'status': 'aberto',
      'criado_em': agoraIso(),
    });
  }

  /// Divide [total] em [n] parcelas com ajuste de centavos na última.
  static List<double> dividir(double total, int n) {
    if (n <= 1) return [r2(total)];
    final base = (total / n * 100).floorToDouble() / 100;
    final lista = List<double>.filled(n, base);
    lista[n - 1] = r2(total - base * (n - 1));
    return lista;
  }

  /// Baixa (total ou parcial) de um título. [principal] abate o saldo do título;
  /// juros e descontos vão para o resultado financeiro. O caixa recebe/paga
  /// principal + juros − desconto, na data efetiva.
  Future<int> baixarTitulo({
    required int tituloId,
    required String data,
    required int contaId,
    required double principal,
    double juros = 0,
    double desconto = 0,
    int? meioId,
    DatabaseExecutor? ex,
  }) async {
    Future<int> run(DatabaseExecutor txn) async {
      final rows = await txn.query('titulos', where: 'id = ?', whereArgs: [tituloId]);
      if (rows.isEmpty) throw RegraException('Título não encontrado');
      final t = rows.first;
      if (t['status'] == 'cancelado') throw RegraException('Título cancelado');
      final aberto = await abertoDoTitulo(txn, t);
      if (aberto <= 0.005) throw RegraException('Este título já está quitado.');
      if (principal <= 0) throw RegraException('Informe o valor a baixar');
      if (principal > aberto + 0.005) {
        throw RegraException('Valor maior que o saldo em aberto (${brl(aberto)}).');
      }
      final pagar = t['tipo'] == 'pagar';
      final cartao = t['ref_tipo'] == 'cartao';
      final caixa = r2(principal + juros - desconto);
      if (caixa < 0) throw RegraException('Desconto maior que o valor baixado');
      final movId = await criarMovimento(txn,
          data: data,
          contaId: contaId,
          tipo: pagar ? 'saida' : 'entrada',
          valor: caixa,
          categoriaId: t['categoria_id'] as int,
          descricao: t['descricao'] as String,
          tituloId: tituloId,
          valorPrincipal: principal,
          juros: juros,
          desconto: desconto,
          refTipo: t['ref_tipo'] as String?,
          refId: t['ref_id'] as int?,
          meioId: meioId);
      if (cartao) {
        // Diferença entre o líquido previsto e o depositado ajusta a taxa (uma única vez).
        final ajuste = r2(desconto - juros);
        if (ajuste.abs() >= 0.005) {
          await Base.lancarResultado(txn,
              data: data,
              grupo: 'despesa_variavel',
              descricao: 'Ajuste de taxa de cartão na conciliação',
              valor: ajuste,
              categoriaId: await Base.categoriaFin(txn, 'TAXA_CARTAO'),
              refTipo: 'movimento',
              refId: movId);
        }
      } else {
        if (juros >= 0.005) {
          await Base.lancarResultado(txn,
              data: data,
              grupo: pagar ? 'despesa_financeira' : 'receita_financeira',
              descricao: '${pagar ? 'Juros pagos' : 'Juros recebidos'}: ${t['descricao']}',
              valor: juros,
              categoriaId: await Base.categoriaFin(txn, pagar ? 'JUROS_PAGOS' : 'JUROS_RECEB'),
              refTipo: 'movimento',
              refId: movId);
        }
        if (desconto >= 0.005) {
          await Base.lancarResultado(txn,
              data: data,
              grupo: pagar ? 'receita_financeira' : 'despesa_financeira',
              descricao: '${pagar ? 'Desconto obtido' : 'Desconto concedido'}: ${t['descricao']}',
              valor: desconto,
              categoriaId: await Base.categoriaFin(txn, pagar ? 'DESC_OBTIDOS' : 'DESC_CONCEDIDOS'),
              refTipo: 'movimento',
              refId: movId);
        }
      }
      await _atualizarStatus(txn, tituloId);
      return movId;
    }

    if (ex != null) return run(ex);
    return db.transaction(run);
  }

  /// Concilia o repasse de cartão com o valor efetivamente depositado.
  Future<int> conciliarCartao({
    required int tituloId,
    required String data,
    required int contaId,
    required double valorDepositado,
  }) async {
    return db.transaction((txn) async {
      final t = (await txn.query('titulos', where: 'id = ?', whereArgs: [tituloId])).first;
      final aberto = await abertoDoTitulo(txn, t);
      final dif = r2(valorDepositado - aberto);
      return baixarTitulo(
        ex: txn,
        tituloId: tituloId,
        data: data,
        contaId: contaId,
        principal: aberto,
        juros: dif > 0 ? dif : 0,
        desconto: dif < 0 ? -dif : 0,
      );
    });
  }

  /// Transferência entre contas do negócio: saída e entrada vinculadas (efeito zero no consolidado).
  Future<void> transferir({
    required int origemId,
    required int destinoId,
    required double valor,
    required String data,
    String? descricao,
  }) async {
    if (origemId == destinoId) throw RegraException('Escolha contas diferentes');
    if (valor <= 0) throw RegraException('Informe o valor');
    await db.transaction((txn) async {
      final cat = await Base.categoriaFin(txn, 'TRANSF');
      final tid = 'T${DateTime.now().microsecondsSinceEpoch}';
      final desc = descricao?.isNotEmpty == true ? descricao! : 'Transferência entre contas';
      await criarMovimento(txn,
          data: data, contaId: origemId, tipo: 'saida', valor: valor, categoriaId: cat,
          descricao: desc, transferenciaId: tid, refTipo: 'transferencia');
      await criarMovimento(txn,
          data: data, contaId: destinoId, tipo: 'entrada', valor: valor, categoriaId: cat,
          descricao: desc, transferenciaId: tid, refTipo: 'transferencia');
    });
  }

  /// Estorno de um movimento: gera o movimento inverso na data informada,
  /// reabre o título e reverte juros/descontos lançados no resultado.
  Future<void> estornarMovimento({required int movimentoId, required String motivo, String? data}) async {
    await db.transaction((txn) async {
      final m = (await txn.query('movimentos_financeiros', where: 'id = ?', whereArgs: [movimentoId])).first;
      if (Base.i(m['estornado']) == 1) throw RegraException('Movimento já estornado');
      if (m['estorno_de'] != null) throw RegraException('Não é possível estornar um estorno');
      final dt = data ?? hojeIso();
      final movs = m['transferencia_id'] != null
          ? await txn.query('movimentos_financeiros',
              where: 'transferencia_id = ? AND estorno_de IS NULL', whereArgs: [m['transferencia_id']])
          : [m];
      for (final mv in movs) {
        await criarMovimento(txn,
            data: dt,
            contaId: mv['conta_id'] as int,
            tipo: mv['tipo'] == 'entrada' ? 'saida' : 'entrada',
            valor: Base.d(mv['valor']),
            categoriaId: mv['categoria_id'] as int,
            descricao: 'Estorno: ${mv['descricao']}',
            tituloId: mv['titulo_id'] as int?,
            valorPrincipal: Base.d(mv['valor_principal']),
            refTipo: mv['ref_tipo'] as String?,
            refId: mv['ref_id'] as int?,
            estornoDe: mv['id'] as int,
            motivo: motivo);
        await txn.update('movimentos_financeiros', {'estornado': 1}, where: 'id = ?', whereArgs: [mv['id']]);
        final lancs = await txn.query('lancamentos_resultado',
            where: "ref_tipo = 'movimento' AND ref_id = ?", whereArgs: [mv['id']]);
        for (final l in lancs) {
          await Base.lancarResultado(txn,
              data: dt,
              grupo: l['grupo'] as String,
              descricao: 'Estorno: ${l['descricao']}',
              valor: -Base.d(l['valor']),
              categoriaId: l['categoria_id'] as int?,
              refTipo: 'estorno_movimento',
              refId: mv['id'] as int);
        }
        if (mv['titulo_id'] != null) await _atualizarStatus(txn, mv['titulo_id'] as int);
        if (mv['ref_tipo'] == 'pedido_pagamento') {
          await txn.update('pagamentos_pedido', {'estornado': 1},
              where: 'movimento_id = ?', whereArgs: [mv['id']]);
        }
      }
      await Base.auditar(txn, 'estorno_movimento',
          entidade: 'movimentos_financeiros', entidadeId: movimentoId, motivo: motivo,
          detalhes: 'Valor ${brl(Base.d(m['valor']))}');
    });
  }

  /// Lança despesa ou receita avulsa (aluguel, energia, etc.) com competência,
  /// parcelas e, opcionalmente, quitação imediata.
  Future<void> lancarContaAvulsa({
    required String tipo, // pagar | receber
    required String descricao,
    required int categoriaId,
    required double valor,
    required String competencia,
    required String primeiroVencimento,
    int parcelas = 1,
    int intervaloDias = 30,
    int? fornecedorId,
    int? clienteId,
    int? contaQuitacaoId,
    int? contaPrevistaId,
  }) async {
    if (valor <= 0) throw RegraException('Informe o valor');
    await db.transaction((txn) async {
      final cat = await Base.categoriaFinPorId(txn, categoriaId);
      final grupo = cat['grupo_dre'] as String;
      final valores = dividir(valor, parcelas);
      final venc0 = parseIso(primeiroVencimento);
      for (var p = 0; p < parcelas; p++) {
        final venc = isoData(venc0.add(Duration(days: intervaloDias * p)));
        final tid = await criarTitulo(txn,
            tipo: tipo,
            descricao: parcelas > 1 ? '$descricao (${p + 1}/$parcelas)' : descricao,
            categoriaId: categoriaId,
            valor: valores[p],
            vencimento: venc,
            competencia: competencia,
            fornecedorId: fornecedorId,
            clienteId: clienteId,
            refTipo: 'avulso',
            parcela: p + 1,
            totalParcelas: parcelas,
            contaPrevistaId: contaPrevistaId ?? contaQuitacaoId);
        if (contaQuitacaoId != null && p == 0 && parcelas == 1) {
          await baixarTitulo(
              ex: txn, tituloId: tid, data: primeiroVencimento, contaId: contaQuitacaoId, principal: valores[p]);
        }
      }
      if (grupo != 'nao_dre') {
        // Para receitas avulsas o grupo é o da categoria (ex.: receita financeira).
        await Base.lancarResultado(txn,
            data: competencia,
            grupo: grupo,
            descricao: descricao,
            valor: valor,
            categoriaId: categoriaId,
            refTipo: 'avulso',
            variavel: grupo == 'despesa_variavel');
      }
    });
  }

  /// Movimento direto no caixa (aporte, retirada, tarifa…). Se a categoria
  /// pertence à DRE, também lança no resultado na mesma data.
  Future<void> movimentoAvulso({
    required int contaId,
    required String tipo,
    required double valor,
    required int categoriaId,
    required String data,
    required String descricao,
  }) async {
    if (valor <= 0) throw RegraException('Informe o valor');
    await db.transaction((txn) async {
      if (tipo == 'saida') {
      }
      final movId = await criarMovimento(txn,
          data: data, contaId: contaId, tipo: tipo, valor: valor, categoriaId: categoriaId, descricao: descricao, refTipo: 'avulso_caixa');
      final cat = await Base.categoriaFinPorId(txn, categoriaId);
      final grupo = cat['grupo_dre'] as String;
      if (grupo != 'nao_dre') {
        await Base.lancarResultado(txn,
            data: data, grupo: grupo, descricao: descricao, valor: valor, categoriaId: categoriaId, refTipo: 'movimento', refId: movId);
      }
    });
  }

  Future<void> remarcarTitulo(int tituloId, String novaPrevisao) async {
    await db.update('titulos', {'nova_previsao': novaPrevisao}, where: 'id = ?', whereArgs: [tituloId]);
    await Base.auditar(db, 'remarcar_titulo', entidade: 'titulos', entidadeId: tituloId,
        detalhes: 'Nova previsão $novaPrevisao');
  }

  Future<void> cancelarTitulo(int tituloId, String motivo) async {
    await db.transaction((txn) async {
      final pago = await pagoDoTitulo(txn, tituloId);
      if (pago > 0.005) throw RegraException('Estorne os pagamentos antes de cancelar o título.');
      final t = (await txn.query('titulos', where: 'id = ?', whereArgs: [tituloId])).first;
      await txn.update('titulos', {'status': 'cancelado', 'motivo_cancelamento': motivo},
          where: 'id = ?', whereArgs: [tituloId]);
      if (t['ref_tipo'] == 'avulso') {
        final cat = await Base.categoriaFinPorId(txn, t['categoria_id'] as int);
        if (cat['grupo_dre'] != 'nao_dre') {
          await Base.lancarResultado(txn,
              data: hojeIso(),
              grupo: cat['grupo_dre'] as String,
              descricao: 'Cancelamento: ${t['descricao']} - $motivo',
              valor: -Base.d(t['valor']),
              categoriaId: t['categoria_id'] as int,
              refTipo: 'cancelamento_titulo',
              refId: tituloId);
        }
      }
      await Base.auditar(txn, 'cancelar_titulo', entidade: 'titulos', entidadeId: tituloId, motivo: motivo);
    });
  }

  // ---------- Consultas ----------

  Future<List<Map<String, Object?>>> titulosAbertos({String? tipo, int? contaId}) async {
    final rows = await db.rawQuery('''
      SELECT t.*, c.nome categoria, cl.nome cliente, f.nome fornecedor
      FROM titulos t
      LEFT JOIN categorias_financeiras c ON c.id = t.categoria_id
      LEFT JOIN clientes cl ON cl.id = t.cliente_id
      LEFT JOIN fornecedores f ON f.id = t.fornecedor_id
      WHERE t.status IN ('aberto','parcial') ${tipo != null ? 'AND t.tipo = ?' : ''}
        ${contaId != null ? 'AND t.conta_prevista_id = ?' : ''}
      ORDER BY COALESCE(t.nova_previsao, t.vencimento)
    ''', [if (tipo != null) tipo, if (contaId != null) contaId]);
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      final m = Map<String, Object?>.from(r);
      m['aberto'] = await abertoDoTitulo(db, r);
      out.add(m);
    }
    return out;
  }

  Future<double> totalAberto(String tipo) async {
    final l = await titulosAbertos(tipo: tipo);
    return r2(l.fold(0.0, (s, t) => s + Base.d(t['aberto'])));
  }

  Future<List<Map<String, Object?>>> movimentos({
    required String inicio,
    required String fim,
    int? contaId,
  }) {
    return db.rawQuery('''
      SELECT m.*, c.nome categoria, c.grupo_dre, cf.nome conta
      FROM movimentos_financeiros m
      LEFT JOIN categorias_financeiras c ON c.id = m.categoria_id
      JOIN contas_financeiras cf ON cf.id = m.conta_id
      WHERE m.data >= ? AND m.data <= ? ${contaId != null ? 'AND m.conta_id = ?' : ''}
      ORDER BY m.data, m.id
    ''', [inicio, fim, if (contaId != null) contaId]);
  }

  /// Fluxo realizado: usa a data efetiva dos movimentos.
  Future<FluxoRealizado> fluxoRealizado({required String inicio, required String fim, int? contaId}) async {
    final diaAnterior = isoData(parseIso(inicio).subtract(const Duration(days: 1)));
    final saldoInicial = await saldo(contaId: contaId, ateData: diaAnterior);
    final movs = await movimentos(inicio: inicio, fim: fim, contaId: contaId);
    var acumulado = saldoInicial;
    var entradas = 0.0, saidas = 0.0;
    final porCategoria = <String, Map<String, double>>{};
    final linhas = <Map<String, Object?>>[];
    for (final m in movs) {
      final v = Base.d(m['valor']);
      final ent = m['tipo'] == 'entrada';
      if (ent) {
        entradas += v;
      } else {
        saidas += v;
      }
      acumulado += ent ? v : -v;
      final cat = (m['categoria'] as String?) ?? 'Sem categoria';
      final pc = porCategoria.putIfAbsent(cat, () => {'entradas': 0, 'saidas': 0});
      pc[ent ? 'entradas' : 'saidas'] = pc[ent ? 'entradas' : 'saidas']! + v;
      final l = Map<String, Object?>.from(m);
      l['saldo_acumulado'] = r2(acumulado);
      linhas.add(l);
    }
    return FluxoRealizado(
      saldoInicial: saldoInicial,
      entradas: r2(entradas),
      saidas: r2(saidas),
      saldoFinal: r2(saldoInicial + entradas - saidas),
      porCategoria: porCategoria,
      movimentos: linhas,
    );
  }

  /// Fluxo projetado: saldo na data de referência + parcelas em aberto pelas datas previstas.
  Future<FluxoProjetado> fluxoProjetado({required String dataRef, required String ate, int? contaId}) async {
    final saldoRef = await saldo(contaId: contaId, ateData: dataRef);
    final titulos = await titulosAbertos(contaId: contaId);
    final itens = <Map<String, Object?>>[];
    var aReceber = 0.0, aPagar = 0.0, vencReceber = 0.0, vencPagar = 0.0;
    for (final t in titulos) {
      final prev = (t['nova_previsao'] as String?) ?? (t['vencimento'] as String);
      if (prev.compareTo(ate) > 0) continue;
      final aberto = Base.d(t['aberto']);
      final vencido = (t['vencimento'] as String).compareTo(dataRef) < 0;
      final m = Map<String, Object?>.from(t);
      m['data_prevista'] = prev;
      m['vencido'] = vencido ? 1 : 0;
      itens.add(m);
      if (t['tipo'] == 'receber') {
        aReceber += aberto;
        if (vencido) vencReceber += aberto;
      } else {
        aPagar += aberto;
        if (vencido) vencPagar += aberto;
      }
    }
    itens.sort((a, b) => (a['data_prevista'] as String).compareTo(b['data_prevista'] as String));
    var acc = saldoRef;
    for (final m in itens) {
      final v = Base.d(m['aberto']);
      acc += m['tipo'] == 'receber' ? v : -v;
      m['saldo_projetado'] = r2(acc);
    }
    return FluxoProjetado(
      dataRef: dataRef,
      ate: ate,
      saldoRef: saldoRef,
      aReceber: r2(aReceber),
      aPagar: r2(aPagar),
      vencidosReceber: r2(vencReceber),
      vencidosPagar: r2(vencPagar),
      saldoProjetado: r2(saldoRef + aReceber - aPagar),
      itens: itens,
    );
  }

  /// Fluxo agrupado por dia, semana ou mês para a tela Financeiro.
  Future<List<Map<String, Object?>>> fluxoAgrupado({
    required String inicio,
    required String fim,
    required String agrupamento, // dia | semana | mes
    int? contaId,
  }) async {
    final f = await fluxoRealizado(inicio: inicio, fim: fim, contaId: contaId);
    final grupos = <String, Map<String, Object?>>{};
    String chave(String data) {
      final d = parseIso(data);
      if (agrupamento == 'mes') return '${d.year}-${d.month.toString().padLeft(2, '0')}';
      if (agrupamento == 'semana') {
        final seg = d.subtract(Duration(days: d.weekday - 1));
        return isoData(seg);
      }
      return data;
    }

    var saldo = f.saldoInicial;
    for (final m in f.movimentos) {
      final k = chave(m['data'] as String);
      final g = grupos.putIfAbsent(k, () => {
            'periodo': k,
            'saldo_inicial': saldo,
            'entradas': 0.0,
            'saidas': 0.0,
            'categorias': <String, List<Map<String, Object?>>>{},
          });
      final v = Base.d(m['valor']);
      if (m['tipo'] == 'entrada') {
        g['entradas'] = (g['entradas'] as double) + v;
        saldo += v;
      } else {
        g['saidas'] = (g['saidas'] as double) + v;
        saldo -= v;
      }
      g['saldo_final'] = r2(saldo);
      final cats = g['categorias'] as Map<String, List<Map<String, Object?>>>;
      cats.putIfAbsent((m['categoria'] as String?) ?? 'Sem categoria', () => []).add(m);
    }
    return grupos.values.toList();
  }
}

class FluxoRealizado {
  FluxoRealizado({
    required this.saldoInicial,
    required this.entradas,
    required this.saidas,
    required this.saldoFinal,
    required this.porCategoria,
    required this.movimentos,
  });
  final double saldoInicial, entradas, saidas, saldoFinal;
  final Map<String, Map<String, double>> porCategoria;
  final List<Map<String, Object?>> movimentos;
}

class FluxoProjetado {
  FluxoProjetado({
    required this.dataRef,
    required this.ate,
    required this.saldoRef,
    required this.aReceber,
    required this.aPagar,
    required this.vencidosReceber,
    required this.vencidosPagar,
    required this.saldoProjetado,
    required this.itens,
  });
  final String dataRef, ate;
  final double saldoRef, aReceber, aPagar, vencidosReceber, vencidosPagar, saldoProjetado;
  final List<Map<String, Object?>> itens;
}

import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';
import 'estoque_service.dart';
import 'financeiro_service.dart';

class ItemCompra {
  ItemCompra({
    required this.itemId,
    this.variacaoId = 0,
    required this.quantidade,
    required this.custoTotal,
    this.lote,
    this.validade,
  });
  final int itemId;
  /// Variação do produto (cor, fragrância, tamanho). 0 para insumos.
  final int variacaoId;
  /// Quantidade comprada (unidades do produto).
  final double quantidade;
  final double custoTotal;
  final String? lote;
  final String? validade;
}

class CompraService {
  CompraService(this.db)
      : estoque = EstoqueService(db),
        fin = FinanceiroService(db);
  final Database db;
  final EstoqueService estoque;
  final FinanceiroService fin;

  /// Salva a compra como rascunho e devolve o id.
  Future<int> salvar({
    int? id,
    int? fornecedorId,
    required String data,
    String? documento,
    required String condicao, // avista | prazo
    int parcelas = 1,
    String? primeiroVencimento,
    int intervaloDias = 30,
    int? contaId,
    String? obs,
    required List<ItemCompra> itens,
  }) async {
    if (itens.isEmpty) throw RegraException('Inclua ao menos um item');
    return db.transaction((txn) async {
      final dados = {
        'fornecedor_id': fornecedorId,
        'data': data,
        'documento': documento,
        'condicao': condicao,
        'parcelas': condicao == 'avista' ? 1 : (parcelas < 1 ? 1 : parcelas),
        'primeiro_vencimento': primeiroVencimento,
        'intervalo_dias': intervaloDias,
        'conta_id': contaId,
        'obs': obs,
        'total': r2(itens.fold(0.0, (s, i) => s + i.custoTotal)),
      };
      int compraId;
      if (id == null) {
        compraId = await txn.insert('compras', {...dados, 'status': 'rascunho', 'criado_em': agoraIso()});
      } else {
        final c = await txn.query('compras', where: 'id = ?', whereArgs: [id]);
        if (c.first['status'] != 'rascunho') throw RegraException('Compra já confirmada não pode ser editada');
        await txn.update('compras', dados, where: 'id = ?', whereArgs: [id]);
        await txn.delete('compra_itens', where: 'compra_id = ?', whereArgs: [id]);
        compraId = id;
      }
      for (final i in itens) {
        if (i.quantidade <= 0 || i.custoTotal < 0) throw RegraException('Quantidade e custo devem ser positivos');
        await txn.insert('compra_itens', {
          'compra_id': compraId,
          'item_id': i.itemId,
          'variacao_id': i.variacaoId,
          'quantidade': i.quantidade,
          'custo_total': r2(i.custoTotal),
          'lote': i.lote,
          'validade': i.validade,
        });
      }
      return compraId;
    });
  }

  /// Confirma a compra: entrada dos produtos no estoque (lote com o custo de
  /// compra), reserva automática para pedidos que aguardavam a mercadoria,
  /// obrigação financeira e, se à vista, a quitação. Tudo numa transação.
  Future<void> confirmar(int compraId) async {
    await db.transaction((txn) async {
      final rows = await txn.query('compras', where: 'id = ?', whereArgs: [compraId]);
      if (rows.isEmpty) throw RegraException('Compra não encontrada');
      final c = rows.first;
      if (c['status'] != 'rascunho') throw RegraException('Esta compra já foi confirmada.');
      final upd = await txn.update('compras', {'status': 'confirmada', 'confirmada_em': agoraIso()},
          where: "id = ? AND status = 'rascunho'", whereArgs: [compraId]);
      if (upd != 1) throw RegraException('Confirmação duplicada bloqueada.');
      final data = c['data'] as String;
      final itens = await txn.query('compra_itens', where: 'compra_id = ?', whereArgs: [compraId]);
      for (final i in itens) {
        final it = await Base.item(txn, i['item_id'] as int);
        final qtd = Base.d(i['quantidade']);
        final custoTotal = Base.d(i['custo_total']);
        if (Base.ehInsumo(it['tipo'] as String)) {
          final fator = Base.d(it['fator_conversao']) <= 0 ? 1.0 : Base.d(it['fator_conversao']);
          await estoque.entradaInsumo(txn,
              itemId: i['item_id'] as int,
              qtdConsumo: qtd * fator,
              custoTotal: custoTotal,
              data: data,
              lote: i['lote'] as String?,
              validade: i['validade'] as String?,
              refTipo: 'compra',
              refId: compraId);
          continue;
        }
        var varId = Base.i(i['variacao_id']);
        if (varId == 0) {
          final v = await txn.query('variacoes', where: 'item_id = ?', whereArgs: [i['item_id']], orderBy: 'id', limit: 1);
          if (v.isEmpty) throw RegraException('${it['nome']} não possui variação cadastrada.');
          varId = v.first['id'] as int;
        }
        // Custo médio do produto (referência para preço sugerido e relatórios).
        final s = await estoque.saldo(i['item_id'] as int, varId, ex: txn);
        final saldoAtual = s.fisico < 0 ? 0.0 : s.fisico;
        final cmAtual = Base.d(it['custo_medio']);
        await txn.update('itens', {'custo_medio': r6((saldoAtual * cmAtual + custoTotal) / (saldoAtual + qtd))},
            where: 'id = ?', whereArgs: [i['item_id']]);
        final lote = (i['lote'] as String?)?.trim();
        await estoque.entradaProduzido(txn,
            itemId: i['item_id'] as int,
            variacaoId: varId,
            quantidade: qtd,
            custoUnitario: custoTotal / qtd,
            codigoLote: (lote == null || lote.isEmpty) ? 'C$compraId-${data.replaceAll('-', '')}' : lote,
            fabricacao: data,
            validade: (i['validade'] as String?)?.isEmpty == true ? null : i['validade'] as String?,
            refTipo: 'compra',
            refId: compraId,
            tipoMov: 'compra');
        await estoque.reservarPendentes(txn, itemId: i['item_id'] as int, variacaoId: varId);
      }
      final total = Base.d(c['total']);
      if (total <= 0) return;
      final cat = await Base.categoriaFin(txn, 'COMPRA_INSUMO');
      String nomeForn = '';
      if (c['fornecedor_id'] != null) {
        final f = await txn.query('fornecedores', where: 'id = ?', whereArgs: [c['fornecedor_id']]);
        if (f.isNotEmpty) nomeForn = ' - ${f.first['nome']}';
      }
      final doc = (c['documento'] as String?)?.isNotEmpty == true ? ' doc ${c['documento']}' : '';
      final desc = 'Compra #$compraId$doc$nomeForn';
      if (c['condicao'] == 'avista') {
        final conta = c['conta_id'] as int?;
        if (conta == null) throw RegraException('Selecione a conta de pagamento da compra à vista');
        final tid = await fin.criarTitulo(txn,
            tipo: 'pagar',
            descricao: desc,
            categoriaId: cat,
            valor: total,
            vencimento: data,
            competencia: data,
            fornecedorId: c['fornecedor_id'] as int?,
            refTipo: 'compra',
            refId: compraId,
            contaPrevistaId: conta);
        await fin.baixarTitulo(ex: txn, tituloId: tid, data: data, contaId: conta, principal: total);
      } else {
        final n = Base.i(c['parcelas']) < 1 ? 1 : Base.i(c['parcelas']);
        final valores = FinanceiroService.dividir(total, n);
        final venc0 = parseIso((c['primeiro_vencimento'] as String?) ??
            isoData(parseIso(data).add(Duration(days: Base.i(c['intervalo_dias'])))));
        for (var p = 0; p < n; p++) {
          await fin.criarTitulo(txn,
              tipo: 'pagar',
              descricao: n > 1 ? '$desc (${p + 1}/$n)' : desc,
              categoriaId: cat,
              valor: valores[p],
              vencimento: isoData(venc0.add(Duration(days: Base.i(c['intervalo_dias']) * p))),
              competencia: data,
              fornecedorId: c['fornecedor_id'] as int?,
              refTipo: 'compra',
              refId: compraId,
              parcela: p + 1,
              totalParcelas: n,
              contaPrevistaId: c['conta_id'] as int?);
        }
      }
      await Base.auditar(txn, 'confirmar_compra', entidade: 'compras', entidadeId: compraId,
          detalhes: 'Total ${brl(total)}');
    });
  }

  Future<void> excluirRascunho(int compraId) => excluir(compraId);

  /// Exclui a compra. Rascunho: apenas apaga. Confirmada: estorna a entrada no
  /// estoque e as contas a pagar, desde que os itens ainda não tenham sido
  /// usados/vendidos e não haja pagamento manual registrado.
  Future<void> excluir(int compraId) async {
    await db.transaction((txn) async {
      final rows = await txn.query('compras', where: 'id = ?', whereArgs: [compraId]);
      if (rows.isEmpty) throw RegraException('Compra não encontrada');
      final c = rows.first;
      if (c['status'] == 'confirmada') {
        // 1. Estoque: os lotes da compra precisam estar intactos.
        final lotes = await txn.query('lotes', where: "origem = 'compra' AND origem_id = ?", whereArgs: [compraId]);
        for (final l in lotes) {
          final it = await Base.item(txn, l['item_id'] as int);
          if ((Base.d(l['saldo']) - Base.d(l['qtd_inicial'])).abs() > Base.eps) {
            throw RegraException('Não é possível excluir: parte de ${it['nome']} desta compra já foi usada ou vendida.');
          }
        }
        // 2. Financeiro: apaga as contas a pagar e os pagamentos feitos (com juros/descontos).
        final titulos = await txn.query('titulos', where: "ref_tipo = 'compra' AND ref_id = ?", whereArgs: [compraId]);
        for (final t in titulos) {
          final movs = await txn.query('movimentos_financeiros', where: 'titulo_id = ?', whereArgs: [t['id']]);
          for (final m in movs) {
            await txn.delete('lancamentos_resultado',
                where: "ref_tipo IN ('movimento','estorno_movimento') AND ref_id = ?", whereArgs: [m['id']]);
            await txn.delete('movimentos_financeiros', where: 'estorno_de = ?', whereArgs: [m['id']]);
          }
          await txn.delete('movimentos_financeiros', where: 'titulo_id = ?', whereArgs: [t['id']]);
          await txn.delete('titulos', where: 'id = ?', whereArgs: [t['id']]);
        }
        // 3. Desfaz o custo médio dos insumos e apaga lotes e movimentos.
        for (final l in lotes) {
          final it = await Base.item(txn, l['item_id'] as int);
          final qtd = Base.d(l['qtd_inicial']);
          final s = await estoque.saldo(l['item_id'] as int, l['variacao_id'] as int, ex: txn);
          final resto = s.fisico - qtd;
          final cm = Base.d(it['custo_medio']);
          final novoCm = resto > Base.eps ? (s.fisico * cm - qtd * Base.d(l['custo_unitario'])) / resto : cm;
          await txn.update('itens', {'custo_medio': r6(novoCm < 0 ? 0 : novoCm)}, where: 'id = ?', whereArgs: [l['item_id']]);
          await txn.delete('movimentos_estoque', where: 'lote_id = ?', whereArgs: [l['id']]);
          await txn.delete('lotes', where: 'id = ?', whereArgs: [l['id']]);
        }
      }
      await txn.delete('compra_itens', where: 'compra_id = ?', whereArgs: [compraId]);
      await txn.delete('compras', where: 'id = ?', whereArgs: [compraId]);
      await Base.auditar(txn, 'excluir_compra', entidade: 'compras', entidadeId: compraId,
          detalhes: 'Status ${c['status']} • total ${brl(Base.d(c['total']))}');
    });
  }

  Future<List<Map<String, Object?>>> listar({int? fornecedorId}) => db.rawQuery('''
      SELECT c.*, f.nome fornecedor FROM compras c
      LEFT JOIN fornecedores f ON f.id = c.fornecedor_id
      ${fornecedorId != null ? 'WHERE c.fornecedor_id = ?' : ''}
      ORDER BY c.data DESC, c.id DESC''', [if (fornecedorId != null) fornecedorId]);

  Future<List<Map<String, Object?>>> itens(int compraId) => db.rawQuery('''
      SELECT ci.*, i.nome, i.codigo, v.nome variacao, v.codigo v_codigo, i.unidade_compra, i.unidade_consumo,
             i.fator_conversao, i.tipo, COALESCE(v.unidade_venda, i.unidade_venda, 'un') unidade
      FROM compra_itens ci JOIN itens i ON i.id = ci.item_id
      LEFT JOIN variacoes v ON v.id = ci.variacao_id
      WHERE ci.compra_id = ?''', [compraId]);
}

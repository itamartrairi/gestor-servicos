import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';
import 'financeiro_service.dart';
import 'pedido_service.dart';

/// Vendas a prazo (fiado / crediário): saldo em aberto por cliente, parcelas
/// vencidas, limite de crédito e recebimento que quita as parcelas mais antigas.
class FiadoService {
  FiadoService(this.db)
      : fin = FinanceiroService(db),
        pedidos = PedidoService(db);
  final Database db;
  final FinanceiroService fin;
  final PedidoService pedidos;

  /// Parcelas em aberto de vendas (títulos a receber ligados a pedidos).
  Future<List<Map<String, Object?>>> parcelasAbertas({int? clienteId, DatabaseExecutor? ex}) async {
    final e = ex ?? db;
    final r = await e.rawQuery('''
      SELECT t.*, c.nome cliente FROM titulos t LEFT JOIN clientes c ON c.id = t.cliente_id
      WHERE t.tipo = 'receber' AND t.ref_tipo = 'pedido' AND t.status IN ('aberto','parcial')
      ${clienteId != null ? 'AND t.cliente_id = ?' : ''}
      ORDER BY COALESCE(t.nova_previsao, t.vencimento), t.id''', [if (clienteId != null) clienteId]);
    final out = <Map<String, Object?>>[];
    for (final t in r) {
      final m = Map<String, Object?>.from(t);
      m['aberto'] = await fin.abertoDoTitulo(e, t);
      if (Base.d(m['aberto']) > 0.005) out.add(m);
    }
    return out;
  }

  Future<double> saldoDevedor(int clienteId, {DatabaseExecutor? ex}) async {
    final l = await parcelasAbertas(clienteId: clienteId, ex: ex);
    return r2(l.fold(0.0, (s, t) => s + Base.d(t['aberto'])));
  }

  /// Clientes com saldo em aberto, valor vencido e próxima parcela.
  Future<List<Map<String, Object?>>> devedores() async {
    final hoje = hojeIso();
    final parcelas = await parcelasAbertas();
    final mapa = <int, Map<String, Object?>>{};
    for (final t in parcelas) {
      final cid = t['cliente_id'] as int?;
      if (cid == null) continue;
      final venc = (t['nova_previsao'] ?? t['vencimento']) as String;
      final m = mapa.putIfAbsent(cid, () => {
            'cliente_id': cid,
            'cliente': t['cliente'],
            'aberto': 0.0,
            'vencido': 0.0,
            'parcelas': 0,
            'proximo_vencimento': null,
          });
      m['aberto'] = r2(Base.d(m['aberto']) + Base.d(t['aberto']));
      if (venc.compareTo(hoje) < 0) m['vencido'] = r2(Base.d(m['vencido']) + Base.d(t['aberto']));
      m['parcelas'] = Base.i(m['parcelas']) + 1;
      if (m['proximo_vencimento'] == null || venc.compareTo(m['proximo_vencimento'] as String) < 0) {
        m['proximo_vencimento'] = venc;
      }
    }
    final lista = mapa.values.toList();
    for (final m in lista) {
      final c = await db.query('clientes', columns: ['limite_credito', 'telefone'], where: 'id = ?', whereArgs: [m['cliente_id']]);
      m['limite_credito'] = c.isEmpty ? 0.0 : Base.d(c.first['limite_credito']);
      m['telefone'] = c.isEmpty ? null : c.first['telefone'];
    }
    lista.sort((a, b) => Base.d(b['vencido']).compareTo(Base.d(a['vencido'])) != 0
        ? Base.d(b['vencido']).compareTo(Base.d(a['vencido']))
        : Base.d(b['aberto']).compareTo(Base.d(a['aberto'])));
    return lista;
  }

  /// Recebe um valor do cliente e quita as parcelas mais antigas primeiro
  /// (cada parte é registrada como pagamento no respectivo pedido).
  Future<void> receberDoCliente({
    required int clienteId,
    required double valor,
    required int meioId,
    required String data,
  }) async {
    if (valor <= 0) throw RegraException('Informe o valor recebido');
    await db.transaction((txn) async {
      final parcelas = await parcelasAbertas(clienteId: clienteId, ex: txn);
      final total = r2(parcelas.fold(0.0, (s, t) => s + Base.d(t['aberto'])));
      if (valor > total + 0.005) throw RegraException('Valor maior que o saldo devedor (${brl(total)}).');
      // Agrupa por pedido mantendo a ordem de vencimento.
      final porPedido = <int, double>{};
      var resta = r2(valor);
      for (final t in parcelas) {
        if (resta <= 0.005) break;
        final parte = resta < Base.d(t['aberto']) ? resta : Base.d(t['aberto']);
        final pid = t['ref_id'] as int;
        porPedido[pid] = r2((porPedido[pid] ?? 0) + parte);
        resta = r2(resta - parte);
      }
      for (final e in porPedido.entries) {
        await pedidos.registrarPagamento(pedidoId: e.key, meioId: meioId, valor: e.value, data: data, ex: txn);
      }
    });
  }
}

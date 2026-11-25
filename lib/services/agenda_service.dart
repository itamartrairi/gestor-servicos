import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import '../data/db.dart';
import 'base.dart';
import 'pedido_service.dart';

/// Agenda de atendimentos: marcar, remarcar, confirmar presença, concluir
/// (gera a venda com pagamento ou fiado), cancelar e registrar falta.
class AgendaService {
  AgendaService(this.db) : pedidos = PedidoService(db);
  final Database db;
  final PedidoService pedidos;

  static const rotulos = {
    'agendado': 'Agendado',
    'concluido': 'Concluído',
    'cancelado': 'Cancelado',
    'faltou': 'Faltou',
  };

  static int _minutos(String hora) {
    final p = hora.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  static String horaFim(String hora, int duracao) {
    final m = _minutos(hora) + duracao;
    return '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  /// Atendimentos que se sobrepõem ao horário (mesma profissional, ou todos
  /// quando a profissional não é informada).
  Future<List<Map<String, Object?>>> conflitos({
    required String data,
    required String hora,
    required int duracao,
    String? profissional,
    int? excetoId,
  }) async {
    final ini = _minutos(hora), fim = ini + duracao;
    final r = await db.rawQuery('''
      SELECT a.*, c.nome cliente, i.nome servico FROM agendamentos a
      LEFT JOIN clientes c ON c.id = a.cliente_id JOIN itens i ON i.id = a.item_id
      WHERE a.data = ? AND a.status = 'agendado' ${excetoId != null ? 'AND a.id <> ?' : ''}''',
        [data, if (excetoId != null) excetoId]);
    final prof = (profissional ?? '').trim().toLowerCase();
    return r.where((a) {
      final p = ((a['profissional'] as String?) ?? '').trim().toLowerCase();
      if (prof.isNotEmpty && p.isNotEmpty && p != prof) return false;
      final i2 = _minutos(a['hora'] as String), f2 = i2 + (a['duracao_min'] as int);
      return ini < f2 && i2 < fim;
    }).toList();
  }

  Future<int> salvar({
    int? id,
    int? clienteId,
    required int itemId,
    int variacaoId = 0,
    required String data,
    required String hora,
    int duracao = 60,
    String? profissional,
    double valor = 0,
    String? obs,
  }) async {
    if (!RegExp(r'^\d{2}:\d{2}$').hasMatch(hora)) throw RegraException('Informe o horário (ex.: 14:30)');
    if (duracao <= 0) throw RegraException('Informe a duração');
    if (valor < 0) throw RegraException('O valor não pode ser negativo');
    final dados = {
      'cliente_id': clienteId,
      'item_id': itemId,
      'variacao_id': variacaoId,
      'data': data,
      'hora': hora,
      'duracao_min': duracao,
      'profissional': (profissional == null || profissional.trim().isEmpty) ? null : profissional.trim(),
      'valor': r2(valor),
      'obs': (obs == null || obs.trim().isEmpty) ? null : obs.trim(),
    };
    if (id == null) return db.insert('agendamentos', {...dados, 'status': 'agendado', 'criado_em': agoraIso()});
    final a = await obter(id);
    if (a['status'] != 'agendado') throw RegraException('Só é possível editar atendimentos ainda agendados');
    await db.update('agendamentos', dados, where: 'id = ?', whereArgs: [id]);
    return id;
  }

  Future<Map<String, Object?>> obter(int id) async {
    final r = await db.rawQuery('''
      SELECT a.*, c.nome cliente, c.telefone, i.nome servico, v.nome variacao
      FROM agendamentos a LEFT JOIN clientes c ON c.id = a.cliente_id
      JOIN itens i ON i.id = a.item_id LEFT JOIN variacoes v ON v.id = a.variacao_id
      WHERE a.id = ?''', [id]);
    if (r.isEmpty) throw RegraException('Atendimento não encontrado');
    return r.first;
  }

  Future<List<Map<String, Object?>>> doDia(String data) => db.rawQuery('''
      SELECT a.*, c.nome cliente, c.telefone, i.nome servico, v.nome variacao
      FROM agendamentos a LEFT JOIN clientes c ON c.id = a.cliente_id
      JOIN itens i ON i.id = a.item_id LEFT JOIN variacoes v ON v.id = a.variacao_id
      WHERE a.data = ? ORDER BY a.hora, a.id''', [data]);

  /// Quantidade de atendimentos agendados por dia num período (para a semana).
  Future<Map<String, int>> contagemPorDia(String inicio, String fim) async {
    final r = await db.rawQuery('''
      SELECT data, COUNT(*) q FROM agendamentos WHERE data BETWEEN ? AND ? AND status IN ('agendado','concluido')
      GROUP BY data''', [inicio, fim]);
    return {for (final x in r) x['data'] as String: x['q'] as int};
  }

  Future<List<Map<String, Object?>>> proximos({int limite = 6}) {
    final h = DateTime.now();
    final agora = '${h.hour.toString().padLeft(2, '0')}:${h.minute.toString().padLeft(2, '0')}';
    return db.rawQuery('''
      SELECT a.*, c.nome cliente, i.nome servico, v.nome variacao
      FROM agendamentos a LEFT JOIN clientes c ON c.id = a.cliente_id
      JOIN itens i ON i.id = a.item_id LEFT JOIN variacoes v ON v.id = a.variacao_id
      WHERE a.status = 'agendado' AND (a.data > ? OR (a.data = ? AND a.hora >= ?))
      ORDER BY a.data, a.hora LIMIT ?''', [hojeIso(), hojeIso(), agora, limite]);
  }

  /// Conclui o atendimento: registra a venda do serviço (com pagamentos; o que
  /// faltar vai para o fiado do cliente) e marca como concluído.
  Future<int> concluir({
    required int id,
    required List<PagamentoInfo> pagamentos,
    double? valor,
    double desconto = 0,
    String? data,
    int parcelas = 1,
    int intervaloDias = 30,
    String? vencimentoSaldo,
    bool ignorarLimite = false,
  }) async {
    final a = await obter(id);
    if (a['status'] != 'agendado') throw RegraException('Este atendimento já foi ${rotulos[a['status']]?.toLowerCase()}.');
    final v = valor ?? Base.d(a['valor']);
    if (v <= 0) throw RegraException('Informe o valor do atendimento');
    final it = await Base.item(db, a['item_id'] as int);
    final pid = await pedidos.vendaBalcao(
      clienteId: a['cliente_id'] as int?,
      canal: 'Agenda',
      data: data ?? (a['data'] as String),
      desconto: desconto,
      itens: [
        ItemPedido(
          itemId: a['item_id'] as int,
          variacaoId: a['variacao_id'] as int,
          quantidade: 1,
          precoUnitario: v,
          unidadeVenda: (it['unidade_venda'] as String?) ?? 'atendimento',
          personalizacao: a['profissional'] != null ? 'Profissional: ${a['profissional']}' : null,
        ),
      ],
      pagamentos: pagamentos,
      parcelas: parcelas,
      intervaloDias: intervaloDias,
      vencimentoSaldo: vencimentoSaldo,
      ignorarLimite: ignorarLimite,
    );
    await db.update('agendamentos', {'status': 'concluido', 'pedido_id': pid, 'valor': r2(v)},
        where: 'id = ?', whereArgs: [id]);
    return pid;
  }

  Future<void> alterarStatus(int id, String status) async {
    if (!['cancelado', 'faltou', 'agendado'].contains(status)) throw RegraException('Situação inválida');
    final a = await obter(id);
    if (a['status'] == 'concluido') throw RegraException('Atendimento concluído: estorne a venda em Vendas se precisar.');
    await db.update('agendamentos', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> excluir(int id) async {
    final a = await obter(id);
    if (a['status'] == 'concluido') {
      throw RegraException('Atendimento concluído já gerou venda. Para desfazer, estorne a venda em Vendas.');
    }
    await db.delete('agendamentos', where: 'id = ?', whereArgs: [id]);
  }

  /// Totais para o painel: atendimentos e faturamento do dia.
  Future<({int agendados, int concluidos, double previsto})> resumoDia(String data) async {
    final r = await db.rawQuery('''
      SELECT SUM(CASE WHEN status = 'agendado' THEN 1 ELSE 0 END) ag,
             SUM(CASE WHEN status = 'concluido' THEN 1 ELSE 0 END) co,
             COALESCE(SUM(CASE WHEN status IN ('agendado','concluido') THEN valor ELSE 0 END),0) pv
      FROM agendamentos WHERE data = ?''', [data]);
    return (agendados: Base.i(r.first['ag']), concluidos: Base.i(r.first['co']), previsto: Base.d(r.first['pv']));
  }
}

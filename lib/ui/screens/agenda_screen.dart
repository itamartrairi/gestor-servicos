import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../services/agenda_service.dart';
import '../../services/base.dart';
import '../widgets/comum.dart';
import '../widgets/pagamentos_dialog.dart';
import '../widgets/seletores.dart';
import 'pedido_detalhe_screen.dart';

const _diasSemana = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

Color corStatusAgenda(String st) => switch (st) {
      'concluido' => Colors.green.shade700,
      'cancelado' => Colors.grey.shade600,
      'faltou' => Colors.red.shade700,
      _ => const Color(0xFFB4457A),
    };

/// Aba "Agenda": semana, atendimentos do dia e ações rápidas.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});
  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _dia = DateTime.now();
  int _v = 0;

  DateTime get _inicioSemana => DateTime(_dia.year, _dia.month, _dia.day).subtract(Duration(days: _dia.weekday - 1));

  Future<(List<Map<String, Object?>>, Map<String, int>)> _dados() async {
    final ini = _inicioSemana;
    return (
      await S.agenda.doDia(isoData(_dia)),
      await S.agenda.contagemPorDia(isoData(ini), isoData(ini.add(const Duration(days: 6)))),
    );
  }

  void _recarregar() => setState(() => _v++);

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final hoje = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          TextButton(onPressed: () => setState(() => _dia = DateTime.now()), child: const Text('Hoje')),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Escolher data',
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: _dia, firstDate: DateTime(2020), lastDate: DateTime(2100), locale: const Locale('pt', 'BR'));
              if (d != null) setState(() => _dia = d);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'agendar',
        icon: const Icon(Icons.add),
        label: const Text('Agendar'),
        onPressed: () async {
          await abrir(context, AgendamentoFormScreen(data: isoData(_dia)));
          _recarregar();
        },
      ),
      body: Carregar<(List<Map<String, Object?>>, Map<String, int>)>(
        key: ValueKey('${isoData(_dia)}|$_v'),
        futuro: _dados,
        builder: (context, d, rec) {
          final (lista, contagem) = d;
          final ini = _inicioSemana;
          final ativos = lista.where((a) => a['status'] == 'agendado' || a['status'] == 'concluido');
          final previsto = ativos.fold<double>(0, (s, a) => s + Base.d(a['valor']));
          return Column(children: [
            Container(
              color: tema.colorScheme.primary.withOpacity(0.06),
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Row(children: [
                IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _dia = _dia.subtract(const Duration(days: 7)))),
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Builder(builder: (context) {
                      final dia = ini.add(Duration(days: i));
                      final sel = isoData(dia) == isoData(_dia);
                      final eHoje = isoData(dia) == isoData(hoje);
                      final q = contagem[isoData(dia)] ?? 0;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _dia = dia),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: sel ? tema.colorScheme.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: eHoje && !sel ? Border.all(color: tema.colorScheme.primary) : null,
                          ),
                          child: Column(children: [
                            Text(_diasSemana[i], style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.grey.shade700)),
                            Text('${dia.day}',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: sel ? Colors.white : null)),
                            Container(
                              height: 6,
                              width: 6,
                              margin: const EdgeInsets.only(top: 2),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: q > 0 ? (sel ? Colors.white : tema.colorScheme.primary) : Colors.transparent,
                              ),
                            ),
                          ]),
                        ),
                      );
                    }),
                  ),
                IconButton(
                    icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _dia = _dia.add(const Duration(days: 7)))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Row(children: [
                Expanded(
                  child: Text('${dataBrDe(_dia)} • ${ativos.length} atendimento(s)', style: tema.textTheme.titleSmall),
                ),
                Text('Previsto ${brl(previsto)}', style: TextStyle(color: tema.colorScheme.primary, fontWeight: FontWeight.w600)),
              ]),
            ),
            Expanded(
              child: lista.isEmpty
                  ? const Vazio('Nenhum atendimento neste dia.\nToque em Agendar para marcar um horário.')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 90),
                      itemCount: lista.length,
                      itemBuilder: (c, i) => CartaoAtendimento(
                        a: lista[i],
                        onTap: () async {
                          await acoesAtendimento(context, lista[i]);
                          rec();
                        },
                      ),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class CartaoAtendimento extends StatelessWidget {
  const CartaoAtendimento({super.key, required this.a, required this.onTap, this.mostrarData = false});
  final Map<String, Object?> a;
  final VoidCallback onTap;
  final bool mostrarData;

  @override
  Widget build(BuildContext context) {
    final st = a['status'] as String;
    final cor = corStatusAgenda(st);
    final servico = nomeComVariacao({'nome': a['servico'], 'variacao': a['variacao']});
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Colors.grey.shade200)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 5,
              decoration: BoxDecoration(color: cor, borderRadius: const BorderRadius.horizontal(left: Radius.circular(14))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (mostrarData) Text(dataBr(a['data'] as String).substring(0, 5), style: const TextStyle(fontSize: 11)),
                Text(a['hora'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(AgendaService.horaFim(a['hora'] as String, a['duracao_min'] as int),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text((a['cliente'] as String?) ?? 'Cliente não informado',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          decoration: st == 'cancelado' ? TextDecoration.lineThrough : null)),
                  Text(servico, style: TextStyle(color: Colors.grey.shade700)),
                  if (a['profissional'] != null)
                    Text('com ${a['profissional']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(brl(Base.d(a['valor'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Etiqueta(AgendaService.rotulos[st] ?? st, cor: cor),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Folha de ações de um atendimento.
Future<void> acoesAtendimento(BuildContext context, Map<String, Object?> a) async {
  final st = a['status'] as String;
  final op = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          title: Text((a['cliente'] as String?) ?? 'Cliente não informado', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${nomeComVariacao({'nome': a['servico'], 'variacao': a['variacao']})} • '
              '${dataBr(a['data'] as String)} às ${a['hora']} • ${brl(Base.d(a['valor']))}'),
        ),
        const Divider(height: 1),
        if (st == 'agendado') ...[
          ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.green.shade700),
              title: const Text('Concluir e receber'),
              onTap: () => Navigator.pop(c, 'concluir')),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Editar / remarcar'), onTap: () => Navigator.pop(c, 'editar')),
          ListTile(
              leading: Icon(Icons.person_off_outlined, color: Colors.red.shade700),
              title: const Text('Cliente faltou'),
              onTap: () => Navigator.pop(c, 'faltou')),
          ListTile(leading: const Icon(Icons.event_busy_outlined), title: const Text('Cancelar atendimento'), onTap: () => Navigator.pop(c, 'cancelado')),
        ],
        if (st == 'cancelado' || st == 'faltou')
          ListTile(leading: const Icon(Icons.undo), title: const Text('Voltar para agendado'), onTap: () => Navigator.pop(c, 'agendado')),
        if (st == 'concluido' && a['pedido_id'] != null) ...[
          ListTile(leading: const Icon(Icons.receipt_long_outlined), title: const Text('Ver venda'), onTap: () => Navigator.pop(c, 'venda')),
          ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Desfazer conclusão'),
              subtitle: const Text('Apaga o recebimento e volta para agendado'),
              onTap: () => Navigator.pop(c, 'desfazer')),
        ],
        ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Excluir', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(c, 'excluir')),
      ]),
    ),
  );
  if (op == null || !context.mounted) return;
  final id = a['id'] as int;
  switch (op) {
    case 'concluir':
      await concluirAtendimento(context, a);
    case 'editar':
      await abrir(context, AgendamentoFormScreen(id: id));
    case 'faltou' || 'cancelado' || 'agendado':
      await executar(context, () => S.agenda.alterarStatus(id, op), sucesso: 'Atendimento atualizado');
    case 'venda':
      await abrir(context, PedidoDetalheScreen(pedidoId: a['pedido_id'] as int));
    case 'desfazer':
      if (await confirmar(context, 'Desfazer conclusão?',
              'O recebimento deste atendimento será apagado (sai do caixa e do fiado) e ele volta para agendado.',
              ok: 'Desfazer') &&
          context.mounted) {
        await executar(context, () => S.agenda.alterarStatus(id, 'agendado'), sucesso: 'Conclusão desfeita');
      }
    case 'excluir':
      if (await confirmarExclusao(context, 'este atendimento',
              detalhe: st == 'concluido' ? 'O recebimento deste atendimento também será apagado.' : null) &&
          context.mounted) {
        await executar(context, () => S.agenda.excluir(id), sucesso: 'Atendimento excluído');
      }
  }
}

/// Recebe o pagamento (o que faltar vai para o fiado) e conclui.
Future<void> concluirAtendimento(BuildContext context, Map<String, Object?> a) async {
  final valor = TextEditingController(text: fmtCampo(Base.d(a['valor'])));
  final desconto = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Concluir atendimento'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        CampoNumero('Valor do serviço', valor, prefixo: 'R\$ '),
        CampoNumero('Desconto', desconto, prefixo: 'R\$ '),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Receber')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final v = parseNum(valor.text), desc = parseNum(desconto.text);
  final total = r2(v - desc);
  final pags = await coletarPagamentos(context, valorSugerido: total, titulo: 'Receber (o que faltar fica no fiado)');
  if (pags == null || !context.mounted) return;
  final fiado = r2(total - pags.fold(0.0, (s, p) => s + p.valor));
  var parcelas = 1, intervalo = 30;
  String? venc;
  if (fiado >= 0.005) {
    if (a['cliente_id'] == null) {
      mostrarErro(context, 'Para deixar no fiado, o atendimento precisa ter cliente. Edite e escolha a cliente.');
      return;
    }
    final r = await pedirParcelamento(context, fiado);
    if (r == null || !context.mounted) return;
    (parcelas, intervalo, venc) = r;
  }
  Future<int> concluir(bool liberar) => S.agenda.concluir(
      id: a['id'] as int,
      pagamentos: pags,
      valor: v,
      desconto: desc,
      parcelas: parcelas,
      intervaloDias: intervalo,
      vencimentoSaldo: venc,
      ignorarLimite: liberar);
  try {
    await concluir(false);
    if (context.mounted) mostrarOk(context, 'Atendimento concluído e recebido');
  } on RegraException catch (e) {
    if (!context.mounted) return;
    if (e.mensagem.startsWith('Limite de crédito') &&
        await confirmar(context, 'Limite de crédito', '${e.mensagem}\n\nConcluir mesmo assim?', ok: 'Concluir')) {
      if (context.mounted) await executar(context, () => concluir(true), sucesso: 'Atendimento concluído');
    } else if (!e.mensagem.startsWith('Limite de crédito')) {
      mostrarErro(context, e);
    }
  }
}

class AgendamentoFormScreen extends StatefulWidget {
  const AgendamentoFormScreen({super.key, this.id, this.data});
  final int? id;
  final String? data;
  @override
  State<AgendamentoFormScreen> createState() => _AgendamentoFormScreenState();
}

class _AgendamentoFormScreenState extends State<AgendamentoFormScreen> {
  int? _clienteId;
  String? _clienteNome;
  Map<String, Object?>? _servico;
  late String _data = widget.data ?? hojeIso();
  String _hora = '09:00';
  final _duracao = TextEditingController(text: '60');
  final _valor = TextEditingController();
  final _prof = TextEditingController();
  final _obs = TextEditingController();
  bool _ok = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    if (widget.id != null) {
      final a = await S.agenda.obter(widget.id!);
      _clienteId = a['cliente_id'] as int?;
      _clienteNome = a['cliente'] as String?;
      _servico = {'item_id': a['item_id'], 'variacao_id': a['variacao_id'], 'nome': a['servico'], 'variacao': a['variacao']};
      _data = a['data'] as String;
      _hora = a['hora'] as String;
      _duracao.text = '${a['duracao_min']}';
      _valor.text = fmtCampo(Base.d(a['valor']));
      _prof.text = (a['profissional'] as String?) ?? '';
      _obs.text = (a['obs'] as String?) ?? '';
    } else {
      final h = DateTime.now();
      if (_data == hojeIso()) {
        final prox = h.minute < 30 ? DateTime(h.year, h.month, h.day, h.hour, 30) : DateTime(h.year, h.month, h.day, h.hour + 1);
        _hora = '${prox.hour.toString().padLeft(2, '0')}:${prox.minute.toString().padLeft(2, '0')}';
      }
    }
    if (mounted) setState(() => _ok = true);
  }

  Future<void> _salvar() async {
    if (_servico == null) {
      mostrarErro(context, 'Escolha o serviço');
      return;
    }
    final dur = int.tryParse(_duracao.text) ?? 60;
    setState(() => _salvando = true);
    try {
      final conf = await S.agenda.conflitos(data: _data, hora: _hora, duracao: dur, profissional: _prof.text, excetoId: widget.id);
      if (conf.isNotEmpty && mounted) {
        final lista = conf.map((c) => '• ${c['hora']} ${(c['cliente'] as String?) ?? ''} (${c['servico']})').join('\n');
        if (!await confirmar(context, 'Horário ocupado', 'Já existe atendimento neste horário:\n$lista\n\nAgendar mesmo assim?',
            ok: 'Agendar')) {
          return;
        }
      }
      if (!mounted) return;
      final ok = await executar(
          context,
          () => S.agenda.salvar(
                id: widget.id,
                clienteId: _clienteId,
                itemId: _servico!['item_id'] as int,
                variacaoId: _servico!['variacao_id'] as int,
                data: _data,
                hora: _hora,
                duracao: dur,
                profissional: _prof.text,
                valor: parseNum(_valor.text),
                obs: _obs.text,
              ),
          sucesso: widget.id == null ? 'Atendimento agendado' : 'Atendimento atualizado');
      if (ok && mounted) Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ok) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final dur = int.tryParse(_duracao.text) ?? 60;
    return Scaffold(
      appBar: AppBar(title: Text(widget.id == null ? 'Novo agendamento' : 'Editar agendamento')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: const Icon(Icons.event_available),
            label: const Padding(padding: EdgeInsets.all(10), child: Text('Salvar agendamento')),
            onPressed: _salvando ? null : _salvar,
          ),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(_clienteNome ?? 'Escolher cliente'),
            subtitle: _clienteNome == null ? const Text('Opcional, mas necessário para fiado e histórico') : null,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_clienteId != null)
                IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _clienteId = _clienteNome = null)),
              IconButton(
                icon: const Icon(Icons.person_add_alt),
                tooltip: 'Nova cliente',
                onPressed: () async {
                  final nome = await pedirTexto(context, 'Nova cliente', rotulo: 'Nome');
                  if (nome == null || nome.isEmpty) return;
                  final id = await S.cad.salvarSimples('clientes', {'nome': nome});
                  setState(() {
                    _clienteId = id;
                    _clienteNome = nome;
                  });
                },
              ),
            ]),
            onTap: () async {
              final c = await escolherCliente(context);
              if (c != null) {
                setState(() {
                  _clienteId = c['id'] as int;
                  _clienteNome = c['nome'] as String;
                });
              }
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.spa_outlined),
            title: Text(_servico == null ? 'Escolher serviço' : nomeComVariacao(_servico!)),
            trailing: const Icon(Icons.search),
            onTap: () async {
              final s = await escolherProduto(context, tipos: const ['servico']);
              if (s == null) return;
              setState(() {
                _servico = s;
                _valor.text = fmtCampo(Base.d(s['preco_venda']));
                _duracao.text = '${Base.i(s['duracao_min']) > 0 ? Base.i(s['duracao_min']) : 60}';
              });
            },
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: CampoData('Data', _data, (v) => setState(() => _data = v ?? _data))),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () async {
                final p = _hora.split(':');
                final t = await showTimePicker(
                    context: context, initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])));
                if (t != null) {
                  setState(() => _hora = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                }
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Horário', border: OutlineInputBorder(), isDense: true, suffixIcon: Icon(Icons.schedule, size: 18)),
                child: Text(_hora),
              ),
            ),
          ),
        ]),
        Row(children: [
          Expanded(child: CampoNumero('Duração', _duracao, sufixo: 'min', inteiro: true, onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: CampoNumero('Valor', _valor, prefixo: 'R\$ ')),
        ]),
        Text('Termina às ${AgendaService.horaFim(_hora, dur)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        CampoTexto('Profissional (opcional)', _prof),
        CampoTexto('Observações', _obs, linhas: 2),
      ]),
    );
  }
}

/// Usado pela tela inicial: abre o formulário de novo agendamento.
Future<void> novoAgendamento(BuildContext context) => abrir(context, const AgendamentoFormScreen());


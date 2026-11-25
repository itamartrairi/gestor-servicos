import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../services/base.dart';
import '../../services/pedido_service.dart';
import '../widgets/comum.dart';
import '../widgets/pagamentos_dialog.dart';
import '../widgets/resumo_pedido_pdf.dart';
import '../widgets/seletores.dart';
import 'pedido_form_screen.dart';

class PedidoDetalheScreen extends StatefulWidget {
  const PedidoDetalheScreen({super.key, required this.pedidoId});
  final int pedidoId;
  @override
  State<PedidoDetalheScreen> createState() => _PedidoDetalheScreenState();
}

class _PedidoDetalheScreenState extends State<PedidoDetalheScreen> {
  int _v = 0;
  void _rec() => setState(() => _v++);

  Future<Map<String, Object?>> _dados() async {
    final id = widget.pedidoId;
    final p = (await banco.rawQuery(
            'SELECT p.*, c.nome cliente, c.telefone, tp.nome tabela FROM pedidos p '
            'LEFT JOIN clientes c ON c.id = p.cliente_id LEFT JOIN tabelas_preco tp ON tp.id = p.tabela_id '
            'WHERE p.id = ?', [id]))
        .first;
    return {
      'p': p,
      'itens': await S.pedidos.itens(id),
      'totais': await S.pedidos.totais(id),
      'pagamentos': await S.pedidos.pagamentos(id),
      'historico': await S.pedidos.historico(id),
    };
  }

  Future<void> _confirmar() async {
    var reservar = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Confirmar pedido'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            CheckboxListTile(value: reservar, onChanged: (v) => set(() => reservar = v!), title: const Text('Reservar produtos disponíveis no estoque')),
            const Text('Serviços não usam estoque. Produtos que faltarem são reservados quando a compra chegar.', style: TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await executar(context, () => S.pedidos.confirmar(widget.pedidoId, reservar: reservar), sucesso: 'Pedido confirmado');
    _rec();
  }

  Future<void> _receber(double saldo) async {
    final data = ValueNotifier<String>(hojeIso());
    final pags = await coletarPagamentos(context, valorSugerido: saldo, titulo: 'Registrar pagamento / sinal', permitirZero: false);
    if (pags == null || !mounted) return;
    await executar(context, () async {
      for (final p in pags) {
        await S.pedidos.registrarPagamento(pedidoId: widget.pedidoId, meioId: p.meioId, valor: p.valor, data: data.value);
      }
    }, sucesso: 'Pagamento registrado');
    _rec();
  }

  Future<void> _entregar(Map<String, double> t) async {
    String data = hojeIso();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Entregar / finalizar'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinhaValor('Total do pedido', brl(t['total'])),
            LinhaValor('Adiantamentos recebidos', brl(t['pago']! - t['devolvido']!)),
            LinhaValor('Saldo', brl(t['saldo']), negrito: true),
            CampoData('Data da entrega', data, (v) => set(() => data = v ?? hojeIso())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continuar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    List<PagamentoInfo> pags = [];
    var parcelas = 1, intervalo = 30;
    String? venc;
    if (t['saldo']! > 0.005) {
      final r = await coletarPagamentos(context,
          valorSugerido: t['saldo']!, titulo: 'Receber na entrega (o que faltar fica no fiado)');
      if (r == null || !mounted) return;
      pags = r;
      final fiado = r2(t['saldo']! - pags.fold(0.0, (s, p) => s + p.valor));
      if (fiado >= 0.005) {
        final pp = await pedirParcelamento(context, fiado);
        if (pp == null || !mounted) return;
        (parcelas, intervalo, venc) = pp;
      }
    }
    if (!mounted) return;
    Future<void> entregar(bool ignorarLimite) => S.pedidos.entregar(
        pedidoId: widget.pedidoId,
        data: data,
        pagamentos: pags,
        vencimentoSaldo: venc,
        parcelas: parcelas,
        intervaloDias: intervalo,
        ignorarLimite: ignorarLimite);
    try {
      await entregar(false);
      if (mounted) mostrarOk(context, 'Pedido entregue');
    } on RegraException catch (e) {
      if (!mounted) return;
      if (e.mensagem.startsWith('Limite de crédito') &&
          await confirmar(context, 'Limite de crédito', '${e.mensagem}\n\nEntregar mesmo assim?', ok: 'Entregar')) {
        if (!mounted) return;
        await executar(context, () => entregar(true), sucesso: 'Pedido entregue');
      } else if (mounted && !e.mensagem.startsWith('Limite de crédito')) {
        mostrarErro(context, e);
      }
    } catch (e) {
      if (mounted) mostrarErro(context, e);
    }
    _rec();
  }

  Future<void> _cancelar(Map<String, double> t) async {
    final motivo = TextEditingController();
    final adiant = r2(t['pago']! - t['devolvido']!);
    final dev = TextEditingController(text: fmtCampo(adiant));
    final contas = await opcoesTabela('contas_financeiras');
    int conta = contas.keys.first;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Cancelar pedido'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CampoTexto('Motivo', motivo),
              if (adiant > 0) ...[
                LinhaValor('Sinal recebido', brl(adiant)),
                CampoNumero('Valor a devolver', dev, prefixo: 'R\$ '),
                CampoLista<int>('Conta de saída', conta, contas, (v) => set(() => conta = v!)),
                const Text('O valor não devolvido fica registrado como sinal retido.', style: TextStyle(fontSize: 12)),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancelar pedido')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await executar(
        context,
        () => S.pedidos.cancelar(
            pedidoId: widget.pedidoId, motivo: motivo.text, valorDevolvido: parseNum(dev.text), contaDevolucaoId: conta),
        sucesso: 'Pedido cancelado');
    _rec();
  }

  Future<void> _estornar(Map<String, double> t) async {
    final motivo = TextEditingController();
    final valor = TextEditingController(text: fmtCampo(t['total']));
    final contas = await opcoesTabela('contas_financeiras');
    int conta = contas.keys.first;
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Estornar / devolver venda'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            CampoTexto('Motivo', motivo),
            CampoNumero('Valor do estorno', valor, prefixo: 'R\$ '),
            CampoLista<int>('Conta para devolver dinheiro', conta, contas, (v) => set(() => conta = v!)),
            const Text('O estorno abate primeiro o saldo a receber; o restante sai da conta escolhida.', style: TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Estornar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await executar(
        context,
        () => S.pedidos.estornarVenda(
            pedidoId: widget.pedidoId, valor: parseNum(valor.text), motivo: motivo.text, contaDevolucaoId: conta),
        sucesso: 'Estorno registrado');
    _rec();
  }

  @override
  Widget build(BuildContext context) {
    return Carregar<Map<String, Object?>>(
      key: ValueKey(_v),
      futuro: _dados,
      builder: (context, d, rec) {
        final p = d['p'] as Map<String, Object?>;
        final itens = d['itens'] as List<Map<String, Object?>>;
        final t = d['totais'] as Map<String, double>;
        final pags = d['pagamentos'] as List<Map<String, Object?>>;
        final hist = d['historico'] as List<Map<String, Object?>>;
        final st = p['status'] as String;
        final aberto = ['confirmado', 'em_producao', 'pronto'].contains(st);
        return Scaffold(
          appBar: AppBar(
            title: Text('Pedido #${widget.pedidoId}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Imprimir ou compartilhar resumo',
                onPressed: () async {
                  final bytes = await gerarResumoPedido(widget.pedidoId);
                  await Printing.sharePdf(bytes: bytes, filename: 'pedido_${widget.pedidoId}.pdf');
                },
              ),
              if (st == 'orcamento')
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Editar',
                  onPressed: () async {
                    await abrir(context, PedidoFormScreen(tipo: p['tipo'] as String, pedidoId: widget.pedidoId));
                    _rec();
                  },
                ),
              if (st != 'entregue')
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Excluir',
                  onPressed: () async {
                    if (!await confirmarExclusao(context, 'o pedido #${widget.pedidoId}',
                        detalhe: 'Só é possível excluir pedidos sem pagamento. Com sinal recebido, use Cancelar.')) {
                      return;
                    }
                    if (!context.mounted) return;
                    final ok = await executar(context, () => S.pedidos.excluir(widget.pedidoId), sucesso: 'Pedido excluído');
                    if (ok && context.mounted) Navigator.pop(context);
                  },
                ),
            ],
          ),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              Etiqueta(PedidoService.rotulos[st] ?? st),
              const SizedBox(width: 8),
              Text(const {'balcao': 'Venda direta', 'encomenda': 'Encomenda', 'entrega': 'Entrega'}[p['tipo']] ?? ''),
              const Spacer(),
              if (p['canal'] != null) Text(p['canal'] as String),
            ]),
            const SizedBox(height: 6),
            Text((p['cliente'] as String?) ?? 'Sem cliente', style: Theme.of(context).textTheme.titleMedium),
            if (p['telefone'] != null) Text(p['telefone'] as String),
            if (p['tabela'] != null) Text('Tabela de preço: ${p['tabela']}'),
            if (p['tipo'] != 'balcao')
              Text('Entrega: ${dataBr(p['data_entrega'] as String?)} ${(p['hora_entrega'] as String?) ?? ''}'),
            if ((p['personalizacao'] as String?)?.isNotEmpty == true) Text('Entrega: ${p['personalizacao']}'),
            if ((p['obs'] as String?)?.isNotEmpty == true) Text('Obs.: ${p['obs']}'),
            const Secao('Produtos'),
            for (final i in itens)
              Card(
                child: ListTile(
                  title: Text(nomeComVariacao(i)),
                  subtitle: Text([
                    '${numero(Base.d(i['quantidade']))} ${i['unidade_venda'] ?? ''} × ${brl(Base.d(i['preco_unitario']))}',
                    if ((aberto || st == 'orcamento') && i['tipo'] != 'servico') 'Reservado: ${numero(Base.d(i['reservado']))}',
                    if ((i['personalizacao'] as String?)?.isNotEmpty == true) '${i['personalizacao']}',
                  ].join(' • ')),
                  trailing: aberto && i['tipo'] != 'servico' && Base.d(i['reservado']) + 0.0001 < Base.d(i['quantidade'])
                      ? TextButton(
                          child: const Text('Reservar'),
                          onPressed: () async {
                            final falta = Base.d(i['quantidade']) - Base.d(i['reservado']);
                            await executar(context, () => S.pedidos.reservarItem(i['id'] as int, falta), sucesso: 'Reservado');
                            _rec();
                          },
                        )
                      : Text(brl(Base.d(i['quantidade']) * Base.d(i['preco_unitario']))),
                ),
              ),
            const Secao('Valores'),
            LinhaValor('Subtotal', brl(t['subtotal'])),
            if (t['desconto']! > 0) LinhaValor('Desconto', '- ${brl(t['desconto'])}'),
            if (t['frete']! > 0) LinhaValor('Frete', brl(t['frete'])),
            LinhaValor('Total', brl(t['total']), negrito: true),
            LinhaValor('Recebido (sinal/pagamentos)', brl(t['pago'])),
            if (t['devolvido']! > 0) LinhaValor('Devolvido', '- ${brl(t['devolvido'])}'),
            LinhaValor(st == 'entregue' ? 'Saldo em contas a receber' : 'Saldo a receber', brl(t['saldo']),
                negrito: true, cor: t['saldo']! > 0 ? Colors.orange.shade800 : Colors.green.shade700),
            if (pags.isNotEmpty) ...[
              const Secao('Pagamentos'),
              for (final pg in pags)
                ListTile(
                  dense: true,
                  title: Text('${pg['meio']} • ${brl(Base.d(pg['valor']))}${Base.i(pg['estornado']) == 1 ? ' (estornado)' : ''}'),
                  subtitle: Text(dataBr(pg['data'] as String)),
                ),
            ],
            const Secao('Histórico'),
            for (final h in hist)
              ListTile(
                dense: true,
                title: Text('${h['evento']}${h['valor'] != null ? ' • ${brl(Base.d(h['valor']))}' : ''}'),
                subtitle: Text('${dataHoraBr(h['data'] as String)}${h['motivo'] != null ? ' • ${h['motivo']}' : ''}'),
              ),
            const SizedBox(height: 90),
          ]),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
                if (st == 'orcamento') FilledButton.icon(icon: const Icon(Icons.check), label: const Text('Confirmar'), onPressed: _confirmar),
                if ((st == 'orcamento' || aberto || st == 'entregue') && t['saldo']! > 0.005)
                  OutlinedButton.icon(icon: const Icon(Icons.payments_outlined), label: Text(st == 'entregue' ? 'Receber' : 'Sinal'), onPressed: () => _receber(t['saldo']!)),
                if (aberto) FilledButton.icon(icon: const Icon(Icons.done_all), label: const Text('Entregar'), onPressed: () => _entregar(t)),
                if (aberto && st != 'pronto')
                  OutlinedButton(
                    child: const Text('Marcar pronto'),
                    onPressed: () async {
                      await executar(context, () => S.pedidos.alterarStatus(widget.pedidoId, 'pronto'));
                      _rec();
                    },
                  ),
                if (st == 'orcamento' || aberto)
                  TextButton(onPressed: () => _cancelar(t), child: const Text('Cancelar', style: TextStyle(color: Colors.red))),
                if (st == 'entregue') TextButton(onPressed: () => _estornar(t), child: const Text('Estornar venda')),
              ]),
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/pedido_service.dart';
import '../widgets/comum.dart';
import 'pedido_detalhe_screen.dart';
import 'pedido_form_screen.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});
  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  String _filtro = 'abertos';
  String _busca = '';
  int _v = 0;

  List<String>? get _status => switch (_filtro) {
        'abertos' => ['orcamento', 'confirmado', 'em_producao', 'pronto'],
        'entregues' => ['entregue'],
        'cancelados' => ['cancelado'],
        _ => null,
      };

  Color _cor(String s) => switch (s) {
        'orcamento' => Colors.blueGrey,
        'confirmado' => Colors.blue,
        'em_producao' => Colors.orange.shade800,
        'pronto' => Colors.teal,
        'entregue' => Colors.green.shade700,
        _ => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendas e encomendas')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
        onPressed: () async {
          final tipo = await showModalBottomSheet<String>(
            context: context,
            builder: (c) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(leading: const Icon(Icons.point_of_sale), title: const Text('Venda rápida (serviço ou produto, à vista ou fiado)'), onTap: () => Navigator.pop(c, 'balcao')),
                ListTile(leading: const Icon(Icons.event_note), title: const Text('Encomenda (bolo, costura, decoração…) com sinal'), onTap: () => Navigator.pop(c, 'encomenda')),
                ListTile(leading: const Icon(Icons.delivery_dining), title: const Text('Entrega'), onTap: () => Navigator.pop(c, 'entrega')),
              ]),
            ),
          );
          if (tipo == null || !context.mounted) return;
          final id = await abrir<int>(context, PedidoFormScreen(tipo: tipo));
          setState(() => _v++);
          if (id != null && tipo != 'balcao' && context.mounted) {
            await abrir(context, PedidoDetalheScreen(pedidoId: id));
            setState(() => _v++);
          }
        },
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Cliente ou nº do pedido', border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _busca = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            for (final f in const {'abertos': 'Em aberto', 'entregues': 'Entregues', 'cancelados': 'Cancelados', 'todos': 'Todos'}.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(f.value), selected: _filtro == f.key, onSelected: (_) => setState(() => _filtro = f.key)),
              ),
          ]),
        ),
        Expanded(
          child: Carregar<List<Map<String, Object?>>>(
            key: ValueKey('$_filtro|$_busca|$_v'),
            futuro: () => S.pedidos.listar(statusIn: _status, busca: _busca),
            builder: (context, lista, rec) {
              if (lista.isEmpty) return const Vazio('Nenhum pedido.');
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: lista.length,
                itemBuilder: (c, i) {
                  final p = lista[i];
                  final st = p['status'] as String;
                  return Card(
                    child: ListTile(
                      title: Text('#${p['id']} • ${(p['cliente'] as String?) ?? (p['tipo'] == 'balcao' ? 'Venda direta' : 'Sem cliente')}'),
                      subtitle: Text([
                        if (p['tipo'] != 'balcao') 'Entrega ${dataBr(p['data_entrega'] as String?)} ${(p['hora_entrega'] as String?) ?? ''}',
                        if (p['tipo'] == 'balcao') 'Venda direta ${dataBr(p['data_pedido'] as String?)}',
                        if (p['canal'] != null) p['canal'] as String,
                      ].join(' • ')),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(brl(Base.d(p['total'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Etiqueta(PedidoService.rotulos[st] ?? st, cor: _cor(st)),
                        ]),
                        PopupMenuButton<String>(
                            tooltip: 'Editar ou excluir',
                            onSelected: (op) async {
                              if (op == 'editar') {
                                await abrir(context, PedidoFormScreen(tipo: p['tipo'] as String, pedidoId: p['id'] as int));
                              } else if (op == 'excluir') {
                                if (!await confirmarExclusao(context, 'a venda #${p['id']}', detalhe: avisoExcluirVenda)) {
                                  return;
                                }
                                if (!context.mounted) return;
                                await executar(context, () => S.pedidos.excluir(p['id'] as int), sucesso: 'Venda excluída');
                              }
                              rec();
                            },
                            itemBuilder: (_) => [
                              if (st == 'orcamento') const PopupMenuItem(value: 'editar', child: Text('Editar')),
                              const PopupMenuItem(value: 'excluir', child: Text('Excluir', style: TextStyle(color: Colors.red))),
                            ],
                          ),
                      ]),
                      onTap: () async {
                        await abrir(context, PedidoDetalheScreen(pedidoId: p['id'] as int));
                        rec();
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

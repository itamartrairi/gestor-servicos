import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../widgets/comum.dart';
import 'pedido_detalhe_screen.dart';

/// Vendas a prazo (fiado): clientes devedores, parcelas e recebimentos.
class FiadoScreen extends StatefulWidget {
  const FiadoScreen({super.key});
  @override
  State<FiadoScreen> createState() => _FiadoScreenState();
}

class _FiadoScreenState extends State<FiadoScreen> {
  int _v = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fiado / vendas a prazo')),
      body: Carregar<List<Map<String, Object?>>>(
        key: ValueKey(_v),
        futuro: () => S.fiado.devedores(),
        builder: (context, lista, rec) {
          if (lista.isEmpty) return const Vazio('Nenhum cliente com saldo em aberto.');
          final total = lista.fold(0.0, (s, m) => s + Base.d(m['aberto']));
          final vencido = lista.fold(0.0, (s, m) => s + Base.d(m['vencido']));
          return ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  LinhaValor('Total a receber', brl(total), negrito: true),
                  LinhaValor('Vencido', brl(vencido), cor: vencido > 0 ? Colors.red : null),
                  LinhaValor('Clientes devendo', '${lista.length}'),
                ]),
              ),
            ),
            for (final m in lista)
              Card(
                child: ListTile(
                  leading: Icon(Icons.person_outline, color: Base.d(m['vencido']) > 0 ? Colors.red : null),
                  title: Text('${m['cliente']}'),
                  subtitle: Text([
                    '${m['parcelas']} parcela(s)',
                    if (m['proximo_vencimento'] != null) 'próximo venc. ${dataBr(m['proximo_vencimento'] as String)}',
                    if (Base.d(m['limite_credito']) > 0) 'limite ${brl(Base.d(m['limite_credito']))}',
                  ].join(' • ')),
                  trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(brl(Base.d(m['aberto'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (Base.d(m['vencido']) > 0)
                      Text('vencido ${brl(Base.d(m['vencido']))}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ]),
                  onTap: () async {
                    await abrir(context, FiadoClienteScreen(clienteId: m['cliente_id'] as int, nome: '${m['cliente']}'));
                    rec();
                  },
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class FiadoClienteScreen extends StatefulWidget {
  const FiadoClienteScreen({super.key, required this.clienteId, required this.nome});
  final int clienteId;
  final String nome;
  @override
  State<FiadoClienteScreen> createState() => _FiadoClienteScreenState();
}

class _FiadoClienteScreenState extends State<FiadoClienteScreen> {
  int _v = 0;

  Future<void> _receber(double saldo) async {
    final meios = await banco.query('meios_pagamento', where: "ativo = 1 AND tipo <> 'cartao'", orderBy: 'id');
    if (!mounted || meios.isEmpty) return;
    var meio = meios.first['id'] as int;
    var data = hojeIso();
    final valor = TextEditingController(text: fmtCampo(saldo));
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Receber de ${widget.nome}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            LinhaValor('Saldo devedor', brl(saldo), negrito: true),
            CampoNumero('Valor recebido', valor, prefixo: 'R\$ '),
            CampoLista<int>('Meio', meio, {for (final m in meios) m['id'] as int: m['nome'] as String}, (v) => set(() => meio = v ?? meio)),
            CampoData('Data', data, (v) => set(() => data = v ?? hojeIso())),
            const Text('O valor quita as parcelas mais antigas primeiro.', style: TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Receber')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await executar(
      context,
      () => S.fiado.receberDoCliente(clienteId: widget.clienteId, valor: parseNum(valor.text), meioId: meio, data: data),
      sucesso: 'Recebimento registrado',
    );
    if (mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Carregar<List<Map<String, Object?>>>(
      key: ValueKey(_v),
      futuro: () => S.fiado.parcelasAbertas(clienteId: widget.clienteId),
      builder: (context, parcelas, rec) {
        final hoje = hojeIso();
        final saldo = parcelas.fold(0.0, (s, t) => s + Base.d(t['aberto']));
        return Scaffold(
          appBar: AppBar(title: Text(widget.nome)),
          bottomNavigationBar: saldo <= 0.005
              ? null
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.payments_outlined),
                      label: Text('Receber • saldo ${brl(saldo)}'),
                      onPressed: () => _receber(r2(saldo)),
                    ),
                  ),
                ),
          body: parcelas.isEmpty
              ? const Vazio('Nenhuma parcela em aberto.')
              : ListView(padding: const EdgeInsets.all(8), children: [
                  for (final t in parcelas)
                    Builder(builder: (context) {
                      final venc = (t['nova_previsao'] ?? t['vencimento']) as String;
                      final atrasada = venc.compareTo(hoje) < 0;
                      return Card(
                        child: ListTile(
                          title: Text('${t['descricao']}'),
                          subtitle: Text('Vencimento ${dataBr(venc)}${atrasada ? ' • em atraso' : ''}',
                              style: TextStyle(color: atrasada ? Colors.red : null)),
                          trailing: Text(brl(Base.d(t['aberto'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                          onTap: () async {
                            await abrir(context, PedidoDetalheScreen(pedidoId: t['ref_id'] as int));
                            rec();
                          },
                        ),
                      );
                    }),
                ]),
        );
      },
    );
  }
}

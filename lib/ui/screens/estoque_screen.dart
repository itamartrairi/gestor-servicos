import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/estoque_service.dart';
import '../widgets/comum.dart';
import '../widgets/seletores.dart';

class EstoqueScreen extends StatelessWidget {
  const EstoqueScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Estoque')),
      body: const _ListaEstoque('produto'),
    );
  }
}

class _ListaEstoque extends StatefulWidget {
  const _ListaEstoque(this.tipo);
  final String tipo;
  @override
  State<_ListaEstoque> createState() => _ListaEstoqueState();
}

class _ListaEstoqueState extends State<_ListaEstoque> {
  int _v = 0;
  String _busca = '';
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Pesquisar', border: OutlineInputBorder()),
          onChanged: (v) => setState(() => _busca = v.toLowerCase()),
        ),
      ),
      Expanded(
        child: Carregar<List<Map<String, Object?>>>(
          key: ValueKey(_v),
          futuro: () => S.estoque.listarSaldos(filtroTipo: widget.tipo),
          builder: (context, lista, rec) {
            final l = lista.where((s) => nomeComVariacao(s).toLowerCase().contains(_busca)).toList();
            if (l.isEmpty) return const Vazio('Nenhum item. Cadastre em Mais > Cadastros.');
            return ListView.builder(
              itemCount: l.length,
              itemBuilder: (c, i) {
                final s = l[i];
                final fisico = Base.d(s['fisico']);
                final venc = Base.d(s['vencido']);
                final res = Base.d(s['reservado']);
                final disp = fisico - venc - res;
                final min = Base.d(s['estoque_minimo']);
                final abaixo = min > 0 && fisico - venc < min;
                final insumo = widget.tipo == 'insumo';
                return ListTile(
                  leading: Icon(
                    venc > 0 ? Icons.dangerous_outlined : (abaixo ? Icons.warning_amber : Icons.inventory_2_outlined),
                    color: venc > 0 ? Colors.red : (abaixo ? Colors.amber.shade900 : null),
                  ),
                  title: Text(nomeComVariacao(s)),
                  subtitle: Text([
                    'Físico ${numero(fisico)}',
                    if (!insumo) 'Reservado ${numero(res)}',
                    'Disponível ${numero(disp)}',
                    if (venc > 0) 'Vencido ${numero(venc)}',
                    if (min > 0) 'Mín. ${numero(min)}',
                    if (insumo) 'Custo médio ${brl(Base.d(s['custo_medio']))}/${s['unidade']}',
                  ].join(' • ')),
                  trailing: Text('${s['unidade']}'),
                  onTap: () async {
                    await abrir(context, ItemEstoqueScreen(itemId: s['item_id'] as int, variacaoId: s['variacao_id'] as int));
                    setState(() => _v++);
                  },
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

class ItemEstoqueScreen extends StatefulWidget {
  const ItemEstoqueScreen({super.key, required this.itemId, required this.variacaoId});
  final int itemId, variacaoId;
  @override
  State<ItemEstoqueScreen> createState() => _ItemEstoqueScreenState();
}

class _ItemEstoqueScreenState extends State<ItemEstoqueScreen> {
  int _v = 0;

  Future<Map<String, Object?>> _dados() async {
    final it = (await banco.query('itens', where: 'id = ?', whereArgs: [widget.itemId])).first;
    String nome = it['nome'] as String;
    if (widget.variacaoId != 0) {
      final v = await banco.query('variacoes', where: 'id = ?', whereArgs: [widget.variacaoId]);
      if (v.isNotEmpty && v.first['nome'] != 'Padrão') nome = '$nome - ${v.first['nome']}';
    }
    return {
      'it': it,
      'nome': nome,
      'saldo': await S.estoque.saldo(widget.itemId, widget.variacaoId),
      'lotes': await S.estoque.lotesDoItem(widget.itemId, widget.variacaoId),
      'movs': await S.estoque.movimentosDoItem(widget.itemId, widget.variacaoId),
    };
  }

  Future<void> _ajustar(double atual, bool insumo) async {
    final qtd = TextEditingController(text: fmtCampo(atual));
    final custo = TextEditingController();
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Ajuste de inventário'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Saldo válido atual: ${numero(atual)}'),
          CampoNumero('Quantidade contada', qtd),
          if (!insumo) CampoNumero('Custo unitário (se houver sobra)', custo, prefixo: 'R\$ '),
          CampoTexto('Motivo', motivo),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Ajustar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await executar(
        context,
        () => S.estoque.ajustar(
              itemId: widget.itemId,
              variacaoId: widget.variacaoId,
              novaQuantidade: parseNum(qtd.text),
              motivo: motivo.text,
              custoUnitarioEntrada: custo.text.isEmpty ? null : parseNum(custo.text),
            ),
        sucesso: 'Estoque ajustado');
    setState(() => _v++);
  }

  Future<void> _perda(Map<String, Object?> lote) async {
    final qtd = TextEditingController(text: fmtCampo(Base.d(lote['saldo'])));
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Registrar perda – lote ${lote['codigo']}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          CampoNumero('Quantidade', qtd),
          CampoTexto('Motivo (vencido, avaria…)', motivo),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Registrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await executar(
        context, () => S.estoque.registrarPerdaLote(loteId: lote['id'] as int, quantidade: parseNum(qtd.text), motivo: motivo.text),
        sucesso: 'Perda registrada');
    setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Carregar<Map<String, Object?>>(
      key: ValueKey(_v),
      futuro: _dados,
      builder: (context, d, rec) {
        final it = d['it'] as Map<String, Object?>;
        final s = d['saldo'] as SaldoItem;
        final lotes = d['lotes'] as List<Map<String, Object?>>;
        final movs = d['movs'] as List<Map<String, Object?>>;
        final insumo = Base.ehInsumo(it['tipo'] as String);
        final hoje = hojeIso();
        final valido = s.valido;
        return Scaffold(
          appBar: AppBar(title: Text(d['nome'] as String)),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _ajustar(valido, insumo),
            icon: const Icon(Icons.tune),
            label: const Text('Ajustar'),
          ),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            LinhaValor('Saldo físico', numero(s.fisico)),
            LinhaValor('Em lotes vencidos (bloqueado)', numero(s.vencido), cor: s.vencido > 0 ? Colors.red : null),
            LinhaValor('Reservado para pedidos', numero(s.reservado)),
            LinhaValor('Disponível', numero(s.disponivel), negrito: true),
            if (insumo) LinhaValor('Custo médio ponderado', '${brl(Base.d(it['custo_medio']))} / ${it['unidade_consumo']}'),
            const Secao('Lotes (consumo sugerido por vencimento)'),
            if (lotes.isEmpty) const Vazio('Sem saldo em lotes.'),
            for (final l in lotes)
              Card(
                child: ListTile(
                  leading: Icon(
                    l['validade'] != null && (l['validade'] as String).compareTo(hoje) < 0 ? Icons.block : Icons.inventory,
                    color: l['validade'] != null && (l['validade'] as String).compareTo(hoje) < 0 ? Colors.red : null,
                  ),
                  title: Text('Lote ${l['codigo']} • saldo ${numero(Base.d(l['saldo']))}'),
                  subtitle: Text([
                    if (l['data_fabricacao'] != null) 'Fab. ${dataBr(l['data_fabricacao'] as String)}',
                    'Validade ${l['validade'] == null ? '—' : dataBr(l['validade'] as String)}',
                    if (!insumo) 'Custo ${brl(Base.d(l['custo_unitario']))}',
                  ].join(' • ')),
                  trailing: IconButton(icon: const Icon(Icons.delete_sweep_outlined), tooltip: 'Registrar perda', onPressed: () => _perda(l)),
                ),
              ),
            const Secao('Movimentações recentes'),
            for (final m in movs)
              ListTile(
                dense: true,
                title: Text('${m['tipo']} • ${numero(Base.d(m['quantidade']))}'),
                subtitle: Text('${dataBr(m['data'] as String)} • ${brl(Base.d(m['custo_total']))}${m['motivo'] != null ? ' • ${m['motivo']}' : ''}'),
              ),
            const SizedBox(height: 80),
          ]),
        );
      },
    );
  }
}

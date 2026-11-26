import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/preco_service.dart';
import '../widgets/comum.dart';
import '../widgets/seletores.dart';

/// Tabelas de preço: varejo, atacado, promoção… com ajuste % sobre
/// o preço de varejo e preço manual por produto.
class TabelasPrecoScreen extends StatefulWidget {
  const TabelasPrecoScreen({super.key});
  @override
  State<TabelasPrecoScreen> createState() => _TabelasPrecoScreenState();
}

class _TabelasPrecoScreenState extends State<TabelasPrecoScreen> {
  int _v = 0;

  Future<void> _editar([Map<String, Object?>? t]) async {
    final nome = TextEditingController(text: (t?['nome'] as String?) ?? '');
    final ajuste = TextEditingController(text: t == null ? '' : fmtCampo(Base.d(t['ajuste_pct'])));
    var padrao = t != null && Base.i(t['padrao']) == 1;
    var ativo = t == null || Base.i(t['ativo']) == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(t == null ? 'Nova tabela de preço' : 'Editar tabela'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CampoTexto('Nome (ex.: Atacado)', nome),
              CampoNumero('Ajuste sobre o preço de varejo', ajuste, sufixo: '%'),
              const Text('Use negativo para desconto (−15 = 15% abaixo do varejo) e positivo para acréscimo.',
                  style: TextStyle(fontSize: 12)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: padrao,
                  onChanged: (v) => set(() => padrao = v),
                  title: const Text('Tabela padrão para novos pedidos')),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero, value: ativo, onChanged: (v) => set(() => ativo = v), title: const Text('Ativa')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await executar(
        context,
        () => S.precos.salvarTabela(
            id: t?['id'] as int?, nome: nome.text, ajustePct: parseNum(ajuste.text), padrao: padrao, ativo: ativo),
        sucesso: 'Tabela salva');
    if (mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tabelas de preço')),
      floatingActionButton: FloatingActionButton(onPressed: () => _editar(), child: const Icon(Icons.add)),
      body: Carregar<List<Map<String, Object?>>>(
        key: ValueKey(_v),
        futuro: () => S.precos.tabelas(apenasAtivas: false),
        builder: (context, lista, rec) => ListView(children: [
          for (final t in lista)
            ListTile(
              leading: Icon(Icons.sell_outlined, color: Base.i(t['ativo']) == 1 ? null : Colors.grey),
              title: Text('${t['nome']}${Base.i(t['padrao']) == 1 ? ' (padrão)' : ''}'),
              subtitle: Text(Base.d(t['ajuste_pct']) == 0
                  ? 'Preço de varejo'
                  : '${Base.d(t['ajuste_pct']) > 0 ? '+' : ''}${numero(Base.d(t['ajuste_pct']), casas: 2)}% sobre o varejo'),
              trailing: BotoesEditarExcluir(
                onEditar: () => _editar(t),
                onExcluir: () async {
                  if (!await confirmarExclusao(context, 'a tabela "${t['nome']}"')) return;
                  if (!context.mounted) return;
                  await executar(context, () async { final m = await S.precos.excluirTabela(t['id'] as int); if (context.mounted) mostrarOk(context, m); });
                  rec();
                },
              ),
              onTap: () => abrir(context, ListaPrecosScreen(tabela: t)),
            ),
        ]),
      ),
    );
  }
}

class ListaPrecosScreen extends StatefulWidget {
  const ListaPrecosScreen({super.key, required this.tabela});
  final Map<String, Object?> tabela;
  @override
  State<ListaPrecosScreen> createState() => _ListaPrecosScreenState();
}

class _ListaPrecosScreenState extends State<ListaPrecosScreen> {
  int _v = 0;

  Future<void> _precoManual(Map<String, Object?> l, double margem) async {
    final ctrl = TextEditingController(text: l['manual'] == null ? '' : fmtCampo(Base.d(l['manual'])));
    final custo = Base.d(l['custo_medio']);
    final sug = PrecoService.precoSugerido(custoUnitario: custo, pctTaxas: 0, pctImpostos: 0, pctFixas: 0, pctMargem: margem);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(nomeComVariacao(l)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          LinhaValor('Preço de varejo', brl(Base.d(l['catalogo']))),
          LinhaValor('Custo médio', custo > 0 ? brl(custo) : '—'),
          if (custo > 0 && sug.preco != null) LinhaValor('Sugerido p/ margem de ${pct(margem)}', brl(sug.preco)),
          CampoNumero('Preço manual nesta tabela (vazio = automático)', ctrl, prefixo: 'R\$ '),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(c, ''), child: const Text('Usar automático')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Salvar')),
        ],
      ),
    );
    if (r == null || !mounted) return;
    await executar(context,
        () => S.precos.definirPreco(widget.tabela['id'] as int, l['variacao_id'] as int, r.trim().isEmpty ? null : parseNum(r)));
    if (mounted) setState(() => _v++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.tabela['nome']}')),
      body: Carregar<(List<Map<String, Object?>>, double)>(
        key: ValueKey(_v),
        futuro: () async => (await S.precos.listaDePrecos(widget.tabela['id'] as int), await S.precos.margemPadrao()),
        builder: (context, d, rec) {
          final (lista, margem) = d;
          if (lista.isEmpty) return const Vazio('Nenhum produto cadastrado.');
          return ListView.builder(
            itemCount: lista.length,
            itemBuilder: (c, i) {
              final l = lista[i];
              final preco = Base.d(l['preco']);
              final custo = Base.d(l['custo_medio']);
              final mg = preco > 0 && custo > 0 ? (preco - custo) / preco * 100 : null;
              return ListTile(
                dense: true,
                title: Text('${(l['codigo'] as String?)?.isNotEmpty == true ? '${l['codigo']} • ' : ''}${nomeComVariacao(l)}'),
                subtitle: Text([
                  'Varejo ${brl(Base.d(l['catalogo']))}',
                  if (custo > 0) 'custo ${brl(custo)}',
                  if (mg != null) 'margem ${pct(mg)}',
                  if (l['manual'] != null) 'preço manual',
                ].join(' • ')),
                trailing: Text(brl(preco), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => _precoManual(l, margem),
              );
            },
          );
        },
      ),
    );
  }
}

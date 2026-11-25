import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/compra_service.dart';
import '../../services/preco_service.dart';
import '../widgets/comum.dart';
import '../widgets/seletores.dart';

class ComprasScreen extends StatefulWidget {
  const ComprasScreen({super.key});
  @override
  State<ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends State<ComprasScreen> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Compras')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Compra'),
        onPressed: () async {
          await abrir(context, const CompraFormScreen());
          setState(() => _v++);
        },
      ),
      body: Carregar<List<Map<String, Object?>>>(
        key: ValueKey(_v),
        futuro: () => S.compras.listar(),
        builder: (context, lista, rec) {
          if (lista.isEmpty) return const Vazio('Nenhuma compra registrada.');
          return ListView(children: [
            for (final c in lista)
              ListTile(
                title: Text('#${c['id']} • ${(c['fornecedor'] as String?) ?? 'Sem fornecedor'}'),
                subtitle: Text('${dataBr(c['data'] as String)} • ${c['condicao'] == 'avista' ? 'À vista' : 'A prazo (${c['parcelas']}x)'}'
                    '${(c['documento'] as String?)?.isNotEmpty == true ? ' • ${c['documento']}' : ''}'),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(brl(Base.d(c['total']))),
                  Etiqueta(c['status'] == 'confirmada' ? 'Confirmada' : 'Rascunho',
                      cor: c['status'] == 'confirmada' ? Colors.green.shade700 : Colors.blueGrey),
                ]),
                onTap: () async {
                  await abrir(context, CompraFormScreen(compraId: c['id'] as int));
                  rec();
                },
              ),
          ]);
        },
      ),
    );
  }
}

class _LinhaCompra {
  _LinhaCompra(this.itemId, this.variacaoId, this.nome, this.unidade,
      {double qtd = 1, double custo = 0, String? lote, this.validade})
      : qtd = TextEditingController(text: fmtCampo(qtd)),
        custo = TextEditingController(text: fmtCampo(custo)),
        lote = TextEditingController(text: lote ?? '');
  final int itemId, variacaoId;
  final String nome, unidade;
  final TextEditingController qtd, custo, lote;
  String? validade;
  double get unitario => parseNum(qtd.text) <= 0 ? 0 : parseNum(custo.text) / parseNum(qtd.text);
}

class CompraFormScreen extends StatefulWidget {
  const CompraFormScreen({super.key, this.compraId});
  final int? compraId;
  @override
  State<CompraFormScreen> createState() => _CompraFormScreenState();
}

class _CompraFormScreenState extends State<CompraFormScreen> {
  int? _fornecedor;
  Map<int, String> _fornecedores = {};
  Map<int, String> _contas = {};
  String _data = hojeIso();
  final _doc = TextEditingController();
  String _condicao = 'avista';
  final _parcelas = TextEditingController(text: '1');
  final _intervalo = TextEditingController(text: '30');
  String? _primeiroVenc;
  int? _conta;
  final _linhas = <_LinhaCompra>[];
  String _status = 'rascunho';
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    _fornecedores = await opcoesTabela('fornecedores', where: '1=1');
    _contas = await opcoesTabela('contas_financeiras');
    _conta = _contas.keys.isEmpty ? null : _contas.keys.first;
    if (widget.compraId != null) {
      final c = (await banco.query('compras', where: 'id = ?', whereArgs: [widget.compraId])).first;
      _fornecedor = c['fornecedor_id'] as int?;
      _data = c['data'] as String;
      _doc.text = (c['documento'] as String?) ?? '';
      _condicao = c['condicao'] as String;
      _parcelas.text = '${c['parcelas']}';
      _intervalo.text = '${c['intervalo_dias']}';
      _primeiroVenc = c['primeiro_vencimento'] as String?;
      _conta = c['conta_id'] as int? ?? _conta;
      _status = c['status'] as String;
      for (final i in await S.compras.itens(widget.compraId!)) {
        _linhas.add(_LinhaCompra(i['item_id'] as int, Base.i(i['variacao_id']), nomeComVariacao(i), (i['unidade'] as String?) ?? 'un',
            qtd: Base.d(i['quantidade']), custo: Base.d(i['custo_total']), lote: i['lote'] as String?, validade: i['validade'] as String?));
      }
    }
    setState(() => _ok = true);
  }

  double get _total => _linhas.fold(0.0, (s, l) => s + parseNum(l.custo.text));

  Future<int?> _salvar() async {
    try {
      return await S.compras.salvar(
        id: widget.compraId,
        fornecedorId: _fornecedor,
        data: _data,
        documento: _doc.text,
        condicao: _condicao,
        parcelas: int.tryParse(_parcelas.text) ?? 1,
        primeiroVencimento: _condicao == 'prazo' ? (_primeiroVenc ?? isoData(parseIso(_data).add(Duration(days: int.tryParse(_intervalo.text) ?? 30)))) : null,
        intervaloDias: int.tryParse(_intervalo.text) ?? 30,
        contaId: _conta,
        itens: [
          for (final l in _linhas)
            ItemCompra(
              itemId: l.itemId,
              variacaoId: l.variacaoId,
              quantidade: parseNum(l.qtd.text),
              custoTotal: parseNum(l.custo.text),
              lote: l.lote.text.isEmpty ? null : l.lote.text,
              validade: l.validade,
            ),
        ],
      );
    } catch (e) {
      if (mounted) mostrarErro(context, e);
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ok) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final editavel = _status == 'rascunho';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.compraId == null ? 'Nova compra' : 'Compra #${widget.compraId}'),
        actions: [
          if (widget.compraId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir',
              onPressed: () async {
                final msg = editavel
                    ? 'Excluir esta compra não confirmada?'
                    : 'Excluir esta compra confirmada? A entrada no estoque e as contas a pagar serão estornadas. '
                        'Só é possível se os itens ainda não foram usados/vendidos e não houver pagamento manual.';
                if (!await confirmar(context, 'Excluir compra', msg, ok: 'Excluir')) return;
                if (!context.mounted) return;
                final ok = await executar(context, () => S.compras.excluir(widget.compraId!), sucesso: 'Compra excluída');
                if (ok && context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      bottomNavigationBar: !editavel
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final id = await _salvar();
                        if (id != null && context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Salvar rascunho'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (!await confirmar(context, 'Confirmar compra',
                            'Dar entrada de ${_linhas.length} item(ns) no estoque e gerar a conta a pagar de ${brl(_total)}?')) {
                          return;
                        }
                        final id = await _salvar();
                        if (id == null || !context.mounted) return;
                        final ok = await executar(context, () => S.compras.confirmar(id), sucesso: 'Compra confirmada');
                        if (ok && context.mounted) Navigator.pop(context);
                      },
                      child: Text('Confirmar ${brl(_total)}'),
                    ),
                  ),
                ]),
              ),
            ),
      body: AbsorbPointer(
        absorbing: !editavel,
        child: ListView(padding: const EdgeInsets.all(12), children: [
          if (!editavel) const Text('Compra confirmada (somente leitura).', style: TextStyle(color: Colors.green)),
          Row(children: [
            Expanded(child: CampoLista<int>('Fornecedor', _fornecedor, _fornecedores, (v) => setState(() => _fornecedor = v))),
            IconButton(
              icon: const Icon(Icons.add_business_outlined),
              onPressed: () async {
                final n = await pedirTexto(context, 'Novo fornecedor', rotulo: 'Nome');
                if (n == null || n.isEmpty) return;
                final id = await S.cad.salvarSimples('fornecedores', {'nome': n});
                _fornecedores = await opcoesTabela('fornecedores', where: '1=1');
                setState(() => _fornecedor = id);
              },
            ),
          ]),
          Row(children: [
            Expanded(child: CampoData('Data', _data, (v) => setState(() => _data = v ?? hojeIso()))),
            const SizedBox(width: 8),
            Expanded(child: CampoTexto('Documento / NF', _doc)),
          ]),
          CampoLista<String>('Condição de pagamento', _condicao, const {'avista': 'À vista', 'prazo': 'A prazo'},
              (v) => setState(() => _condicao = v!)),
          if (_condicao == 'prazo') ...[
            Row(children: [
              Expanded(child: CampoNumero('Parcelas', _parcelas, inteiro: true)),
              const SizedBox(width: 8),
              Expanded(child: CampoNumero('Intervalo', _intervalo, sufixo: 'dias', inteiro: true)),
            ]),
            CampoData('1º vencimento', _primeiroVenc, (v) => setState(() => _primeiroVenc = v), permiteVazio: true),
          ],
          CampoLista<int>(_condicao == 'avista' ? 'Conta de pagamento' : 'Conta prevista para pagamento', _conta, _contas,
              (v) => setState(() => _conta = v)),
          Secao('Itens',
              acao: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Adicionar'),
                onPressed: () async {
                  final p = await escolherProduto(context, tipos: const ['acabado']);
                  if (p == null) return;
                  // Custo sugerido: último custo médio ou preço de venda menos o desconto do fornecedor.
                  final custo = Base.d(p['custo_medio']) > 0
                      ? Base.d(p['custo_medio'])
                      : PrecoService.custoComDesconto(Base.d(p['preco_venda']), Base.d(p['desconto_padrao_pct']));
                  setState(() => _linhas.add(_LinhaCompra(p['item_id'] as int, p['variacao_id'] as int, nomeComVariacao(p),
                      (p['unidade_venda'] as String?) ?? 'un', custo: custo)));
                },
              )),
          for (var i = 0; i < _linhas.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 2, 2, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_linhas[i].nome, style: const TextStyle(fontWeight: FontWeight.w600))),
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _linhas.removeAt(i))),
                  ]),
                  Row(children: [
                    Expanded(child: CampoNumero('Qtd', _linhas[i].qtd, sufixo: _linhas[i].unidade, onChanged: (_) => setState(() {}))),
                    const SizedBox(width: 8),
                    Expanded(child: CampoNumero('Custo total', _linhas[i].custo, prefixo: 'R\$ ', onChanged: (_) => setState(() {}))),
                  ]),
                  Text('Custo unitário: ${brl(_linhas[i].unitario)}', style: const TextStyle(fontSize: 12)),
                  Row(children: [
                    Expanded(child: CampoTexto('Lote', _linhas[i].lote)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: CampoData('Validade', _linhas[i].validade, (v) => setState(() => _linhas[i].validade = v), permiteVazio: true)),
                  ]),
                ]),
              ),
            ),
          LinhaValor('Total', brl(_total), negrito: true),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

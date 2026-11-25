import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../widgets/comum.dart';
import '../widgets/seletores.dart';

class FinanceiroScreen extends StatefulWidget {
  const FinanceiroScreen({super.key});
  @override
  State<FinanceiroScreen> createState() => _FinanceiroScreenState();
}

class _FinanceiroScreenState extends State<FinanceiroScreen> {
  int _v = 0;
  void _rec() => setState(() => _v++);

  Future<void> _novaConta(String tipo) async {
    final cats = await banco.query('categorias_financeiras',
        where: "ativo = 1 AND (tipo = ? OR tipo = 'ambos') AND COALESCE(codigo,'') NOT IN ('COMPRA_INSUMO','VENDA_RECEB','ADIANT_CLIENTE','CARTAO_REPASSE','TRANSF','DEVOL_CLIENTE')",
        whereArgs: [tipo == 'pagar' ? 'saida' : 'entrada'],
        orderBy: 'nome');
    final contas = await opcoesTabela('contas_financeiras');
    final pessoas = await opcoesTabela(tipo == 'pagar' ? 'fornecedores' : 'clientes', where: '1=1');
    if (!mounted) return;
    final desc = TextEditingController();
    final valor = TextEditingController();
    final parcelas = TextEditingController(text: '1');
    int? cat = cats.isEmpty ? null : cats.first['id'] as int;
    int? pessoa;
    int? conta = contas.keys.first;
    String comp = hojeIso(), venc = hojeIso();
    bool quitar = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(tipo == 'pagar' ? 'Nova conta a pagar / despesa' : 'Nova conta a receber / receita'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CampoTexto('Descrição', desc),
              CampoLista<int>('Categoria', cat, {for (final x in cats) x['id'] as int: x['nome'] as String}, (v) => set(() => cat = v)),
              CampoLista<int>(tipo == 'pagar' ? 'Fornecedor' : 'Cliente', pessoa, pessoas, (v) => set(() => pessoa = v)),
              CampoNumero('Valor total', valor, prefixo: 'R\$ '),
              CampoNumero('Parcelas', parcelas, inteiro: true),
              CampoData('Competência (mês da DRE)', comp, (v) => set(() => comp = v ?? hojeIso())),
              CampoData('1º vencimento', venc, (v) => set(() => venc = v ?? hojeIso())),
              CampoLista<int>('Conta', conta, contas, (v) => set(() => conta = v)),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: quitar,
                onChanged: (v) => set(() => quitar = v!),
                title: const Text('Já foi pago/recebido (na data do vencimento)'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || cat == null || !mounted) return;
    final n = int.tryParse(parcelas.text) ?? 1;
    await executar(
        context,
        () => S.fin.lancarContaAvulsa(
              tipo: tipo,
              descricao: desc.text.isEmpty ? 'Lançamento' : desc.text,
              categoriaId: cat!,
              valor: parseNum(valor.text),
              competencia: comp,
              primeiroVencimento: venc,
              parcelas: n < 1 ? 1 : n,
              fornecedorId: tipo == 'pagar' ? pessoa : null,
              clienteId: tipo == 'receber' ? pessoa : null,
              contaQuitacaoId: quitar && n <= 1 ? conta : null,
              contaPrevistaId: conta,
            ),
        sucesso: 'Lançamento salvo');
    _rec();
  }

  Future<void> _transferir() async {
    final contas = await opcoesTabela('contas_financeiras');
    if (!mounted || contas.length < 2) return;
    int origem = contas.keys.first, destino = contas.keys.elementAt(1);
    final valor = TextEditingController();
    String data = hojeIso();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Transferência entre contas'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            CampoLista<int>('De', origem, contas, (v) => set(() => origem = v!)),
            CampoLista<int>('Para', destino, contas, (v) => set(() => destino = v!)),
            CampoNumero('Valor', valor, prefixo: 'R\$ '),
            CampoData('Data', data, (v) => set(() => data = v ?? hojeIso())),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Transferir')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await executar(context, () => S.fin.transferir(origemId: origem, destinoId: destino, valor: parseNum(valor.text), data: data),
        sucesso: 'Transferência registrada');
    _rec();
  }

  Future<void> _movimentoAvulso() async {
    final contas = await opcoesTabela('contas_financeiras');
    final cats = await banco.query('categorias_financeiras',
        where: "ativo = 1 AND codigo IN ('SOCIOS','TARIFA','JUROS_RECEB','OUTRAS_REC','OUTRAS_DESP') OR (codigo IS NULL AND ativo = 1)",
        orderBy: 'nome');
    if (!mounted) return;
    int conta = contas.keys.first;
    int cat = cats.first['id'] as int;
    String tipo = 'entrada';
    String data = hojeIso();
    final valor = TextEditingController();
    final desc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Aporte, retirada ou tarifa'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CampoLista<String>('Tipo', tipo, const {'entrada': 'Entrada', 'saida': 'Saída'}, (v) => set(() => tipo = v!)),
              CampoLista<int>('Categoria', cat, {for (final x in cats) x['id'] as int: x['nome'] as String}, (v) => set(() => cat = v!)),
              CampoLista<int>('Conta', conta, contas, (v) => set(() => conta = v!)),
              CampoNumero('Valor', valor, prefixo: 'R\$ '),
              CampoData('Data', data, (v) => set(() => data = v ?? hojeIso())),
              CampoTexto('Descrição', desc),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Lançar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await executar(
        context,
        () => S.fin.movimentoAvulso(
            contaId: conta, tipo: tipo, valor: parseNum(valor.text), categoriaId: cat, data: data,
            descricao: desc.text.isEmpty ? 'Movimento avulso' : desc.text),
        sucesso: 'Lançado');
    _rec();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Financeiro'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Contas'),
            Tab(text: 'A receber'),
            Tab(text: 'A pagar'),
            Tab(text: 'Fluxo de caixa'),
            Tab(text: 'Movimentos'),
          ]),
        ),
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final op = await showModalBottomSheet<String>(
              context: context,
              builder: (c) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  ListTile(leading: const Icon(Icons.call_made), title: const Text('Conta a pagar / despesa'), onTap: () => Navigator.pop(c, 'pagar')),
                  ListTile(leading: const Icon(Icons.call_received), title: const Text('Conta a receber / outra receita'), onTap: () => Navigator.pop(c, 'receber')),
                  ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('Transferência entre contas'), onTap: () => Navigator.pop(c, 'transf')),
                  ListTile(leading: const Icon(Icons.savings_outlined), title: const Text('Aporte, retirada ou tarifa'), onTap: () => Navigator.pop(c, 'avulso')),
                ]),
              ),
            );
            if (op == 'pagar' || op == 'receber') await _novaConta(op!);
            if (op == 'transf') await _transferir();
            if (op == 'avulso') await _movimentoAvulso();
          },
        ),
        body: TabBarView(children: [
          _Contas(key: ValueKey('c$_v')),
          _Titulos('receber', key: ValueKey('r$_v'), onChange: _rec),
          _Titulos('pagar', key: ValueKey('p$_v'), onChange: _rec),
          _Fluxo(key: ValueKey('f$_v')),
          _Movimentos(key: ValueKey('m$_v'), onChange: _rec),
        ]),
      ),
    );
  }
}

class _Contas extends StatelessWidget {
  const _Contas({super.key});
  @override
  Widget build(BuildContext context) {
    return Carregar<List<Map<String, Object?>>>(
      futuro: () async {
        final contas = await banco.query('contas_financeiras', orderBy: 'id');
        return [
          for (final c in contas) {...c, 'saldo': await S.fin.saldoConta(c['id'] as int)}
        ];
      },
      builder: (context, contas, rec) {
        final total = contas.fold(0.0, (s, c) => s + Base.d(c['saldo']));
        return ListView(padding: const EdgeInsets.all(12), children: [
          for (final c in contas)
            Card(child: ListTile(title: Text(c['nome'] as String), subtitle: Text(c['tipo'] as String), trailing: Text(brl(Base.d(c['saldo']))))),
          LinhaValor('Saldo consolidado em ${dataBrDe(DateTime.now())}', brl(total), negrito: true),
          const SizedBox(height: 8),
          const Text('Cadastre contas e saldos iniciais em Mais > Cadastros > Contas financeiras.', style: TextStyle(fontSize: 12)),
        ]);
      },
    );
  }
}

class _Titulos extends StatelessWidget {
  const _Titulos(this.tipo, {super.key, required this.onChange});
  final String tipo;
  final VoidCallback onChange;

  Future<void> _baixar(BuildContext context, Map<String, Object?> t) async {
    final contas = await opcoesTabela('contas_financeiras');
    if (!context.mounted) return;
    final cartao = t['ref_tipo'] == 'cartao';
    final valor = TextEditingController(text: fmtCampo(Base.d(t['aberto'])));
    final juros = TextEditingController();
    final desc = TextEditingController();
    int conta = (t['conta_prevista_id'] as int?) ?? contas.keys.first;
    String data = hojeIso();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(cartao ? 'Conciliar repasse de cartão' : (tipo == 'pagar' ? 'Registrar pagamento' : 'Registrar recebimento')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(t['descricao'] as String),
              LinhaValor('Em aberto', brl(Base.d(t['aberto']))),
              if (cartao && t['valor_bruto'] != null)
                LinhaValor('Bruto / taxa prevista', '${brl(Base.d(t['valor_bruto']))} / ${brl(Base.d(t['taxa_prevista']))}'),
              CampoNumero(cartao ? 'Valor efetivamente depositado' : 'Valor a baixar', valor, prefixo: 'R\$ '),
              if (!cartao) ...[
                CampoNumero('Juros/multa', juros, prefixo: 'R\$ '),
                CampoNumero('Desconto', desc, prefixo: 'R\$ '),
              ],
              CampoLista<int>('Conta', conta, contas, (v) => set(() => conta = v!)),
              CampoData('Data efetiva', data, (v) => set(() => data = v ?? hojeIso())),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirmar')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    await executar(context, () async {
      if (cartao) {
        await S.fin.conciliarCartao(tituloId: t['id'] as int, data: data, contaId: conta, valorDepositado: parseNum(valor.text));
      } else {
        await S.fin.baixarTitulo(
            tituloId: t['id'] as int,
            data: data,
            contaId: conta,
            principal: parseNum(valor.text),
            juros: parseNum(juros.text),
            desconto: parseNum(desc.text));
      }
    }, sucesso: 'Baixa registrada');
    onChange();
  }

  @override
  Widget build(BuildContext context) {
    return Carregar<List<Map<String, Object?>>>(
      futuro: () => S.fin.titulosAbertos(tipo: tipo),
      builder: (context, lista, rec) {
        if (lista.isEmpty) return const Vazio('Nada em aberto.');
        final hoje = hojeIso();
        final total = lista.fold(0.0, (s, t) => s + Base.d(t['aberto']));
        return ListView(padding: const EdgeInsets.only(bottom: 80), children: [
          Padding(padding: const EdgeInsets.all(12), child: LinhaValor('Total em aberto', brl(total), negrito: true)),
          for (final t in lista)
            Card(
              child: ListTile(
                title: Text(t['descricao'] as String),
                subtitle: Text([
                  'Venc. ${dataBr(t['vencimento'] as String)}',
                  if (t['nova_previsao'] != null) 'nova previsão ${dataBr(t['nova_previsao'] as String)}',
                  (t['cliente'] ?? t['fornecedor'] ?? t['categoria'] ?? '') as String,
                ].join(' • ')),
                leading: (t['vencimento'] as String).compareTo(hoje) < 0
                    ? const Icon(Icons.error_outline, color: Colors.red)
                    : const Icon(Icons.schedule),
                trailing: Text(brl(Base.d(t['aberto'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                onTap: () => _baixar(context, t),
                onLongPress: () async {
                  final op = await showModalBottomSheet<String>(
                    context: context,
                    builder: (c) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(title: const Text('Baixar'), onTap: () => Navigator.pop(c, 'baixar')),
                        ListTile(title: const Text('Nova data prevista'), onTap: () => Navigator.pop(c, 'remarcar')),
                        ListTile(title: const Text('Cancelar título'), onTap: () => Navigator.pop(c, 'cancelar')),
                      ]),
                    ),
                  );
                  if (!context.mounted) return;
                  if (op == 'baixar') await _baixar(context, t);
                  if (op == 'remarcar') {
                    final d = await showDatePicker(
                        context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
                    if (d != null) await S.fin.remarcarTitulo(t['id'] as int, isoData(d));
                    onChange();
                  }
                  if (op == 'cancelar') {
                    final m = await pedirTexto(context, 'Cancelar título');
                    if (m != null && context.mounted) await executar(context, () => S.fin.cancelarTitulo(t['id'] as int, m));
                    onChange();
                  }
                },
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Toque para baixar; toque longo para remarcar ou cancelar.', style: TextStyle(fontSize: 12)),
          ),
        ]);
      },
    );
  }
}

class _Fluxo extends StatefulWidget {
  const _Fluxo({super.key});
  @override
  State<_Fluxo> createState() => _FluxoState();
}

class _FluxoState extends State<_Fluxo> {
  String _ag = 'dia';
  String _ini = isoData(inicioMes(DateTime.now()));
  String _fim = isoData(fimMes(DateTime.now()));
  int? _conta;
  Map<int, String> _contas = {};

  @override
  void initState() {
    super.initState();
    opcoesTabela('contas_financeiras').then((c) => setState(() => _contas = c));
  }

  String _rotulo(String p) {
    if (_ag == 'mes') return '${p.substring(5, 7)}/${p.substring(0, 4)}';
    if (_ag == 'semana') return 'Semana de ${dataBr(p)}';
    return dataBr(p);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(children: [
          Expanded(child: CampoData('De', _ini, (v) => setState(() => _ini = v ?? _ini))),
          const SizedBox(width: 6),
          Expanded(child: CampoData('Até', _fim, (v) => setState(() => _fim = v ?? _fim))),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          Expanded(
            child: CampoLista<String>('Agrupar', _ag, const {'dia': 'Dia', 'semana': 'Semana', 'mes': 'Mês'}, (v) => setState(() => _ag = v!)),
          ),
          const SizedBox(width: 6),
          Expanded(child: CampoLista<int>('Conta', _conta ?? 0, {0: 'Todas', ..._contas}, (v) => setState(() => _conta = v == 0 ? null : v))),
        ]),
      ),
      Expanded(
        child: Carregar<List<Map<String, Object?>>>(
          key: ValueKey('$_ag$_ini$_fim$_conta'),
          futuro: () => S.fin.fluxoAgrupado(inicio: _ini, fim: _fim, agrupamento: _ag, contaId: _conta),
          builder: (context, grupos, rec) {
            if (grupos.isEmpty) return const Vazio('Sem movimentos no período.');
            return ListView(children: [
              for (final g in grupos)
                Card(
                  child: ExpansionTile(
                    title: Text(_rotulo(g['periodo'] as String)),
                    subtitle: Text('Inicial ${brl(Base.d(g['saldo_inicial']))} • +${brl(Base.d(g['entradas']))} • -${brl(Base.d(g['saidas']))}'),
                    trailing: Text(brl(Base.d(g['saldo_final'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                    children: [
                      for (final cat in (g['categorias'] as Map<String, List<Map<String, Object?>>>).entries)
                        ExpansionTile(
                          title: Text(cat.key),
                          trailing: Text(brl(cat.value.fold<double>(0.0, (s, m) => s + (m['tipo'] == 'entrada' ? 1 : -1) * Base.d(m['valor'])))),
                          children: [
                            for (final m in cat.value)
                              ListTile(
                                dense: true,
                                title: Text((m['descricao'] as String?) ?? ''),
                                subtitle: Text('${dataBr(m['data'] as String)} • ${m['conta']}'),
                                trailing: Text('${m['tipo'] == 'entrada' ? '+' : '-'}${brl(Base.d(m['valor']))}'),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}

class _Movimentos extends StatelessWidget {
  const _Movimentos({super.key, required this.onChange});
  final VoidCallback onChange;
  @override
  Widget build(BuildContext context) {
    final ini = isoData(DateTime.now().subtract(const Duration(days: 60)));
    final fim = isoData(DateTime.now().add(const Duration(days: 1)));
    return Carregar<List<Map<String, Object?>>>(
      futuro: () async => (await S.fin.movimentos(inicio: ini, fim: fim)).reversed.toList(),
      builder: (context, lista, rec) {
        if (lista.isEmpty) return const Vazio('Sem movimentos nos últimos 60 dias.');
        return ListView(padding: const EdgeInsets.only(bottom: 80), children: [
          for (final m in lista)
            ListTile(
              dense: true,
              title: Text((m['descricao'] as String?) ?? ''),
              subtitle: Text('${dataBr(m['data'] as String)} • ${m['conta']} • ${m['categoria'] ?? ''}'
                  '${Base.i(m['estornado']) == 1 ? ' • ESTORNADO' : ''}'),
              trailing: Text('${m['tipo'] == 'entrada' ? '+' : '-'}${brl(Base.d(m['valor']))}',
                  style: TextStyle(color: m['tipo'] == 'entrada' ? Colors.green.shade700 : Colors.red)),
              onLongPress: Base.i(m['estornado']) == 1 || m['estorno_de'] != null
                  ? null
                  : () async {
                      final motivo = await pedirTexto(context, 'Estornar movimento');
                      if (motivo == null || !context.mounted) return;
                      await executar(context, () => S.fin.estornarMovimento(movimentoId: m['id'] as int, motivo: motivo),
                          sucesso: 'Estorno registrado');
                      onChange();
                    },
            ),
          const Padding(padding: EdgeInsets.all(12), child: Text('Toque longo em um movimento para estorná-lo.', style: TextStyle(fontSize: 12))),
        ]);
      },
    );
  }
}

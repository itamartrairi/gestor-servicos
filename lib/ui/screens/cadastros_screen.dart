import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/cadastro_service.dart';
import '../widgets/comum.dart';
import '../widgets/seletores.dart';
import 'tabelas_preco_screen.dart';

class CadastrosScreen extends StatelessWidget {
  const CadastrosScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final itens = <(IconData, String, Widget)>[
      (Icons.spa_outlined, 'Serviços', const ItensScreen(tipos: ['servico'], titulo: 'Serviços')),
      (Icons.shopping_bag_outlined, 'Produtos para venda (com estoque)', const ItensScreen(tipos: ['acabado'], titulo: 'Produtos')),
      (Icons.storefront_outlined, 'Fornecedores', SimplesCrud.marcas()),
      (Icons.people_outline, 'Clientes', SimplesCrud.clientes()),
      (Icons.sell_outlined, 'Tabelas de preço', const TabelasPrecoScreen()),
      (Icons.category_outlined, 'Categorias de serviços e produtos', SimplesCrud.categorias()),
      (Icons.credit_card, 'Meios de pagamento', SimplesCrud.meios()),
      (Icons.label_outline, 'Categorias financeiras', SimplesCrud.categoriasFin()),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Cadastros')),
      body: ListView(children: [
        for (final i in itens)
          ListTile(leading: Icon(i.$1), title: Text(i.$2), trailing: const Icon(Icons.chevron_right), onTap: () => abrir(context, i.$3)),
      ]),
    );
  }
}

// ---------------- Itens ----------------

class ItensScreen extends StatefulWidget {
  const ItensScreen({super.key, required this.tipos, required this.titulo});
  final List<String> tipos;
  final String titulo;
  @override
  State<ItensScreen> createState() => _ItensScreenState();
}

class _ItensScreenState extends State<ItensScreen> {
  int _v = 0;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () async {
          await abrir(context, ItemFormScreen(tipoInicial: widget.tipos.first, tipos: widget.tipos));
          setState(() => _v++);
        },
      ),
      body: Carregar<List<Map<String, Object?>>>(
        key: ValueKey(_v),
        futuro: () => S.cad.itens(tipos: widget.tipos, apenasAtivos: false),
        builder: (context, l, rec) {
          if (l.isEmpty) return const Vazio('Nenhum cadastro. Toque em + para incluir.');
          return ListView(children: [
            for (final i in l)
              ListTile(
                title: Text(i['nome'] as String, style: TextStyle(decoration: Base.i(i['ativo']) == 0 ? TextDecoration.lineThrough : null)),
                subtitle: Text([
                  CadastroService.tiposItem[i['tipo']] ?? '',
                  if (i['categoria'] != null) i['categoria'] as String,
                  if (Base.ehInsumo(i['tipo'] as String)) '${i['unidade_compra'] ?? '-'} = ${numero(Base.d(i['fator_conversao']))} ${i['unidade_consumo']}',
                ].join(' • ')),
                trailing: BotoesEditarExcluir(
                  onEditar: () async {
                    await abrir(context, ItemFormScreen(itemId: i['id'] as int, tipoInicial: i['tipo'] as String, tipos: widget.tipos));
                    rec();
                  },
                  onExcluir: () async {
                    if (!await confirmarExclusao(context, '"${i['nome']}"')) return;
                    if (!context.mounted) return;
                    await executar(context, () => S.cad.excluirItem(i['id'] as int), sucesso: 'Excluído');
                    rec();
                  },
                ),
                onTap: () async {
                  await abrir(context, ItemFormScreen(itemId: i['id'] as int, tipoInicial: i['tipo'] as String, tipos: widget.tipos));
                  rec();
                },
              ),
          ]);
        },
      ),
    );
  }
}

class ItemFormScreen extends StatefulWidget {
  const ItemFormScreen({super.key, this.itemId, required this.tipoInicial, required this.tipos});
  final int? itemId;
  final String tipoInicial;
  final List<String> tipos;
  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  late String _tipo = widget.tipoInicial;
  final _nome = TextEditingController();
  final _codigo = TextEditingController();
  final _barras = TextEditingController();
  final _duracao = TextEditingController(text: '60');
  final _custoMat = TextEditingController();
  final _preco = TextEditingController();
  int? _categoria;
  Map<int, String> _categorias = {};
  int? _marca;
  Map<int, String> _marcas = {};
  double _custoMedio = 0;
  double _margem = 30;
  final _uCompra = TextEditingController();
  String _uConsumo = 'kg';

  final _fator = TextEditingController(text: '1');
  final _minimo = TextEditingController();
  String _uVenda = 'un';
  final _pctVar = TextEditingController();
  bool _ativo = true;
  List<Map<String, Object?>> _variacoes = [];
  bool _ok = false;

  bool get _insumo => Base.ehInsumo(_tipo);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final cats = await banco.query('categorias', orderBy: 'nome');
    _categorias = {for (final c in cats) c['id'] as int: c['nome'] as String};
    _marcas = await opcoesTabela('fornecedores', where: '1=1');
    _margem = await S.precos.margemPadrao();
    if (widget.itemId != null) {
      final i = (await banco.query('itens', where: 'id = ?', whereArgs: [widget.itemId])).first;
      _tipo = i['tipo'] as String;
      _nome.text = i['nome'] as String;
      _codigo.text = (i['codigo'] as String?) ?? '';
      _barras.text = (i['codigo_barras'] as String?) ?? '';
      _marca = i['fornecedor_id'] as int?;
      _custoMedio = Base.d(i['custo_medio']);
      _duracao.text = '${Base.i(i['duracao_min']) > 0 ? Base.i(i['duracao_min']) : 60}';
      _custoMat.text = fmtCampo(_custoMedio);
      _categoria = i['categoria_id'] as int?;
      _uCompra.text = (i['unidade_compra'] as String?) ?? '';
      _uConsumo = i['unidade_consumo'] as String;
      _fator.text = fmtCampo(Base.d(i['fator_conversao']));
      _minimo.text = fmtCampo(Base.d(i['estoque_minimo']));
      _uVenda = (i['unidade_venda'] as String?) ?? 'un';
      _pctVar.text = i['variavel_pct_cpv'] == null ? '' : fmtCampo(Base.d(i['variavel_pct_cpv']));

      _ativo = Base.i(i['ativo']) == 1;
      _variacoes = await S.cad.variacoes(widget.itemId!);
    }
    setState(() => _ok = true);
  }

  Future<void> _salvar() async {
    final servico = _tipo == 'servico';
    await executar(context, () async {
      final id = await S.cad.salvarItem({
        'tipo': _tipo,
        'nome': _nome.text.trim(),
        'codigo': _codigo.text.trim().isEmpty ? null : _codigo.text.trim(),
        'codigo_barras': _barras.text.trim().isEmpty ? null : _barras.text.trim(),
        'fornecedor_id': _marca,
        'categoria_id': _categoria,
        'unidade_compra': _insumo ? _uCompra.text : null,
        'unidade_consumo': _insumo ? _uConsumo : _uVenda,
        'fator_conversao': _insumo ? (parseNum(_fator.text) <= 0 ? 1 : parseNum(_fator.text)) : 1,
        'estoque_minimo': parseNum(_minimo.text),
        'unidade_venda': _insumo ? null : _uVenda,
        'variavel_pct_cpv': servico ? 100 : (_pctVar.text.isEmpty ? null : parseNum(_pctVar.text)),
        if (servico) 'duracao_min': (int.tryParse(_duracao.text) ?? 60) <= 0 ? 60 : int.parse(_duracao.text),
        if (servico) 'custo_medio': parseNum(_custoMat.text),
        'ativo': _ativo ? 1 : 0,
      }, id: widget.itemId);
      if (widget.itemId == null && _preco.text.trim().isNotEmpty) {
        final v = (await S.cad.variacoes(id)).first['id'] as int;
        await banco.update('variacoes', {'preco_venda': parseNum(_preco.text)}, where: 'id = ?', whereArgs: [v]);
      }
      if (mounted) Navigator.pop(context);
    }, sucesso: 'Salvo');
  }

  Future<void> _editarVariacao([Map<String, Object?>? v]) async {
    final nome = TextEditingController(text: (v?['nome'] as String?) ?? '');
    final codigo = TextEditingController(text: (v?['codigo'] as String?) ?? '');
    final tam = TextEditingController(text: (v?['tamanho'] as String?) ?? '');
    final sabor = TextEditingController(text: (v?['sabor'] as String?) ?? '');
    final acab = TextEditingController(text: (v?['acabamento'] as String?) ?? '');
    final preco = TextEditingController(text: fmtCampo(Base.d(v?['preco_venda'])));
    final min = TextEditingController(text: fmtCampo(Base.d(v?['estoque_minimo'])));
    String un = (v?['unidade_venda'] as String?) ?? _uVenda;
    bool ativo = v == null || Base.i(v['ativo']) == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(v == null ? 'Nova variação' : 'Editar variação'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CampoTexto('Nome (ex.: 2 L, Tamanho M, Azul)', nome),
              CampoTexto('Tamanho / volume / peso', tam),
              CampoTexto('Cor / sabor / modelo', sabor),
              CampoTexto('Observação', acab),
              CampoLista<String>('Unidade de venda', un, {for (final u in CadastroService.unidadesVenda) u: u}, (x) => set(() => un = x!)),
              CampoNumero('Preço de venda (varejo)', preco, prefixo: 'R\$ '),
              CampoNumero('Estoque mínimo', min),
              SwitchListTile(contentPadding: EdgeInsets.zero, value: ativo, onChanged: (x) => set(() => ativo = x), title: const Text('Ativa')),
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
    await executar(context, () async {
      await S.cad.salvarVariacao({
        'item_id': widget.itemId,
        'nome': nome.text.trim(),
        'codigo': codigo.text.trim().isEmpty ? null : codigo.text.trim(),
        'tamanho': tam.text,
        'sabor': sabor.text,
        'acabamento': acab.text,
        'unidade_venda': un,
        'preco_venda': parseNum(preco.text),
        'estoque_minimo': parseNum(min.text),
        'ativo': ativo ? 1 : 0,
      }, id: v?['id'] as int?);
    });
    _variacoes = await S.cad.variacoes(widget.itemId!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_ok) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemId == null ? 'Novo cadastro' : 'Editar cadastro'),
        actions: [
          if (widget.itemId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Excluir',
              onPressed: () async {
                if (!await confirmarExclusao(context, 'este cadastro')) return;
                if (!context.mounted) return;
                final ok = await executar(context, () => S.cad.excluirItem(widget.itemId!), sucesso: 'Excluído');
                if (ok && context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: FilledButton(onPressed: _salvar, child: const Text('Salvar')))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        CampoLista<String>('Tipo', _tipo, {for (final t in widget.tipos) t: CadastroService.tiposItem[t]!},
            widget.itemId == null ? (v) => setState(() => _tipo = v!) : (_) {}),
        CampoTexto(_tipo == 'servico' ? 'Nome do serviço (ex.: Manicure, Escova)' : 'Nome', _nome),
        if (widget.itemId == null && !_insumo) CampoNumero('Preço', _preco, prefixo: 'R\$ '),
        if (_tipo == 'servico') ...[
          Row(children: [
            Expanded(child: CampoNumero('Duração padrão', _duracao, sufixo: 'min', inteiro: true)),
            const SizedBox(width: 8),
            Expanded(child: CampoNumero('Custo de material', _custoMat, prefixo: 'R\$ ')),
          ]),
          const Text('Custo de material: esmaltes, descartáveis, linha, ingredientes… gastos em cada atendimento. Entra no custo da DRE.',
              style: TextStyle(fontSize: 12)),
        ],
        if (!_insumo && _tipo != 'servico') ...[
          CampoTexto('Código de barras (EAN)', _barras),
          CampoLista<int>('Fornecedor principal', _marca, _marcas, (v) => setState(() => _marca = v)),
        ],
        CampoLista<int>('Categoria', _categoria, _categorias, (v) => setState(() => _categoria = v)),
        if (_insumo) ...[
          CampoTexto('Unidade de compra', _uCompra, dica: 'ex.: saco 50 kg'),
          CampoLista<String>('Unidade de uso no campo', _uConsumo, {for (final u in CadastroService.unidadesConsumo) u: u},
              (v) => setState(() => _uConsumo = v!)),
          CampoNumero('Fator de conversão (1 unidade de compra = ? unidades de uso)', _fator),
          CampoNumero('Estoque mínimo', _minimo, sufixo: _uConsumo),
          const Text('Exemplo: saco de adubo de 50 kg usado em kg → fator 50.', style: TextStyle(fontSize: 12)),
        ] else ...[
          CampoLista<String>('Unidade de venda / estoque', _uVenda, {for (final u in CadastroService.unidadesVenda) u: u},
              (v) => setState(() => _uVenda = v!)),
          if (_custoMedio > 0) ...[
            LinhaValor(_tipo == 'servico' ? 'Custo de material' : 'Custo médio de compra', brl(_custoMedio)),
            LinhaValor('Preço sugerido p/ margem de ${pct(_margem)}', brl(_custoMedio / (1 - _margem / 100))),
          ],
          if (_tipo != 'servico') CampoNumero('Parcela variável do CPV (%) – para margem de contribuição', _pctVar, sufixo: '%'),
        ],
        SwitchListTile(contentPadding: EdgeInsets.zero, value: _ativo, onChanged: (v) => setState(() => _ativo = v), title: const Text('Ativo')),
        if (!_insumo && widget.itemId != null) ...[
          Secao(_tipo == 'servico' ? 'Opções e preços (ex.: curto, médio, longo)' : 'Variações, preços e estoque mínimo',
              acao: TextButton.icon(onPressed: () => _editarVariacao(), icon: const Icon(Icons.add), label: const Text('Variação'))),
          for (final v in _variacoes)
            ListTile(
              title: Text(v['nome'] as String, style: TextStyle(decoration: Base.i(v['ativo']) == 0 ? TextDecoration.lineThrough : null)),
              subtitle: Text('${(v['codigo'] as String?)?.isNotEmpty == true ? 'Cód. ${v['codigo']} • ' : ''}'
                  '${brl(Base.d(v['preco_venda']))} / ${v['unidade_venda']}'
                  '${Base.d(v['estoque_minimo']) > 0 ? ' • mínimo ${numero(Base.d(v['estoque_minimo']))}' : ''}'),
              trailing: BotoesEditarExcluir(
                onEditar: () => _editarVariacao(v),
                onExcluir: () async {
                  if (!await confirmarExclusao(context, 'a variação "${v['nome']}"')) return;
                  if (!mounted) return;
                  await executar(context, () => S.cad.excluirVariacao(v['id'] as int), sucesso: 'Excluída');
                  _variacoes = await S.cad.variacoes(widget.itemId!);
                  if (mounted) setState(() {});
                },
              ),
              onTap: () => _editarVariacao(v),
            ),
        ],
        if (!_insumo && widget.itemId == null)
          const Text('Depois de salvar, você pode abrir o cadastro para incluir opções com preços diferentes (ex.: cabelo curto, médio, longo).',
              style: TextStyle(fontSize: 12)),
      ]),
    );
  }
}

// ---------------- Cadastros simples ----------------

class CampoDef {
  const CampoDef(this.chave, this.rotulo, {this.tipo = 'texto', this.opcoes});
  final String chave, rotulo, tipo; // texto | numero | inteiro | data | opcao | bool
  final Map<Object, String>? opcoes;
}

class SimplesCrud extends StatefulWidget {
  const SimplesCrud({super.key, required this.tabela, required this.titulo, required this.campos, this.subtitulo, this.padrao = const {}});
  final String tabela, titulo;
  final List<CampoDef> campos;
  final String Function(Map<String, Object?>)? subtitulo;
  final Map<String, Object?> padrao;

  factory SimplesCrud.categorias() => SimplesCrud(
        tabela: 'categorias',
        titulo: 'Categorias',
        campos: const [CampoDef('nome', 'Nome')],
        subtitulo: (m) => '',
        padrao: const {'tipo': 'produto'},
      );

  factory SimplesCrud.clientes() => SimplesCrud(
        tabela: 'clientes',
        titulo: 'Clientes',
        campos: const [
          CampoDef('nome', 'Nome'),
          CampoDef('telefone', 'Telefone / WhatsApp'),
          CampoDef('documento', 'CPF'),
          CampoDef('endereco', 'Endereço'),
          CampoDef('limite_credito', 'Limite de crédito no fiado (0 = sem limite)', tipo: 'numero'),
          CampoDef('tabela_id', 'Tabela de preço do cliente', tipo: 'tabela_preco'),
          CampoDef('obs', 'Observações'),
        ],
        subtitulo: (m) => [
          if ((m['telefone'] as String?)?.isNotEmpty == true) m['telefone'] as String,
          if (Base.d(m['limite_credito']) > 0) 'limite ${brl(Base.d(m['limite_credito']))}',
        ].join(' • '),
      );

  factory SimplesCrud.marcas() => SimplesCrud(
        tabela: 'fornecedores',
        titulo: 'Fornecedores',
        campos: const [
          CampoDef('nome', 'Nome'),
          CampoDef('desconto_padrao_pct', 'Desconto médio sobre o preço de venda (%) – estimativa de custo', tipo: 'numero'),
          CampoDef('telefone', 'Telefone / WhatsApp do vendedor'),
          CampoDef('documento', 'CNPJ'),
          CampoDef('endereco', 'Endereço / site'),
          CampoDef('obs', 'Observações'),
        ],
        subtitulo: (m) => (m['telefone'] as String?) ?? '',
      );

  factory SimplesCrud.pessoas(String tabela, String titulo) => SimplesCrud(
        tabela: tabela,
        titulo: titulo,
        campos: const [
          CampoDef('nome', 'Nome'),
          CampoDef('telefone', 'Telefone'),
          CampoDef('documento', 'CPF/CNPJ'),
          CampoDef('endereco', 'Endereço'),
          CampoDef('obs', 'Observações'),
        ],
        subtitulo: (m) => (m['telefone'] as String?) ?? '',
      );

  factory SimplesCrud.contas() => SimplesCrud(
        tabela: 'contas_financeiras',
        titulo: 'Contas financeiras',
        campos: const [
          CampoDef('nome', 'Nome'),
          CampoDef('tipo', 'Tipo', tipo: 'opcao', opcoes: {'caixa': 'Caixa (dinheiro)', 'banco': 'Conta bancária', 'carteira': 'Carteira digital', 'outro': 'Outro'}),
          CampoDef('saldo_inicial', 'Saldo inicial', tipo: 'numero'),
          CampoDef('data_saldo_inicial', 'Data do saldo inicial', tipo: 'data'),
          CampoDef('ativo', 'Ativa', tipo: 'bool'),
        ],
        subtitulo: (m) => 'Saldo inicial ${brl(Base.d(m['saldo_inicial']))} em ${dataBr(m['data_saldo_inicial'] as String?)}',
        padrao: {'tipo': 'banco', 'data_saldo_inicial': hojeIso(), 'ativo': 1},
      );

  factory SimplesCrud.meios() => SimplesCrud(
        tabela: 'meios_pagamento',
        titulo: 'Meios de pagamento',
        campos: const [
          CampoDef('nome', 'Nome'),
          CampoDef('tipo', 'Tipo', tipo: 'opcao', opcoes: {'dinheiro': 'Dinheiro', 'pix': 'Pix', 'cartao': 'Cartão (gera repasse)', 'outro': 'Outro'}),
          CampoDef('taxa_pct', 'Taxa (%)', tipo: 'numero'),
          CampoDef('dias_repasse', 'Dias para repasse', tipo: 'inteiro'),
          CampoDef('conta_id', 'Conta de destino', tipo: 'conta'),
          CampoDef('ativo', 'Ativo', tipo: 'bool'),
        ],
        subtitulo: (m) => '${m['tipo']} • taxa ${numero(Base.d(m['taxa_pct']), casas: 2)}% • ${m['dias_repasse']} dia(s)',
        padrao: const {'tipo': 'pix', 'ativo': 1, 'conta_id': 1},
      );

  factory SimplesCrud.categoriasFin() => SimplesCrud(
        tabela: 'categorias_financeiras',
        titulo: 'Categorias financeiras',
        campos: const [
          CampoDef('nome', 'Nome'),
          CampoDef('tipo', 'Tipo', tipo: 'opcao', opcoes: {'entrada': 'Entrada', 'saida': 'Saída', 'ambos': 'Ambos'}),
          CampoDef('grupo_dre', 'Linha da DRE', tipo: 'opcao', opcoes: {
            'despesa_fixa': 'Despesa operacional fixa',
            'despesa_variavel': 'Despesa operacional variável',
            'imposto_venda': 'Imposto sobre vendas',
            'receita_financeira': 'Receita financeira / outras receitas',
            'despesa_financeira': 'Despesa financeira',
            'nao_dre': 'Não entra na DRE',
          }),
          CampoDef('ativo', 'Ativa', tipo: 'bool'),
        ],
        subtitulo: (m) => '${m['tipo']} • ${m['grupo_dre']}${m['codigo'] != null ? ' • padrão do sistema' : ''}',
        padrao: const {'tipo': 'saida', 'grupo_dre': 'despesa_fixa', 'ativo': 1},
      );

  @override
  State<SimplesCrud> createState() => _SimplesCrudState();
}

class _SimplesCrudState extends State<SimplesCrud> {
  int _v = 0;

  Future<void> _editar([Map<String, Object?>? reg]) async {
    final contas = await opcoesContas();
    final tabelasPreco = <Object, String>{
      for (final t in await banco.query('tabelas_preco', where: 'ativo = 1', orderBy: 'padrao DESC, nome'))
        t['id'] as int: t['nome'] as String
    };
    final valores = <String, Object?>{...widget.padrao, ...?reg};
    final ctrls = <String, TextEditingController>{
      for (final c in widget.campos)
        if (['texto', 'numero', 'inteiro'].contains(c.tipo))
          c.chave: TextEditingController(
              text: c.tipo == 'texto' ? (valores[c.chave] as String?) ?? '' : fmtCampo(valores[c.chave] as num?)),
    };
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(reg == null ? 'Novo' : 'Editar'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final c in widget.campos)
                switch (c.tipo) {
                  'numero' => CampoNumero(c.rotulo, ctrls[c.chave]!),
                  'inteiro' => CampoNumero(c.rotulo, ctrls[c.chave]!, inteiro: true),
                  'data' => CampoData(c.rotulo, valores[c.chave] as String?, (v) => set(() => valores[c.chave] = v)),
                  'opcao' => CampoLista<Object>(c.rotulo, valores[c.chave], c.opcoes!, (v) => set(() => valores[c.chave] = v)),
                  'conta' => CampoLista<Object>(c.rotulo, valores[c.chave], contas, (v) => set(() => valores[c.chave] = v)),
                  'tabela_preco' =>
                    CampoLista<Object>(c.rotulo, valores[c.chave], tabelasPreco, (v) => set(() => valores[c.chave] = v)),
                  'bool' => SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.rotulo),
                      value: Base.i(valores[c.chave]) == 1,
                      onChanged: (v) => set(() => valores[c.chave] = v ? 1 : 0)),
                  _ => CampoTexto(c.rotulo, ctrls[c.chave]!),
                },
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final dados = <String, Object?>{};
    for (final c in widget.campos) {
      switch (c.tipo) {
        case 'texto':
          dados[c.chave] = ctrls[c.chave]!.text.trim();
          break;
        case 'numero':
          dados[c.chave] = parseNum(ctrls[c.chave]!.text);
          break;
        case 'inteiro':
          dados[c.chave] = parseNum(ctrls[c.chave]!.text).round();
          break;
        default:
          dados[c.chave] = valores[c.chave];
      }
    }
    await executar(context, () => S.cad.salvarSimples(widget.tabela, dados, id: reg?['id'] as int?), sucesso: 'Salvo');
    setState(() => _v++);
  }

  Future<void> _excluir(Map<String, Object?> reg) async {
    if (!await confirmarExclusao(context, '"${reg['nome']}"')) return;
    if (!mounted) return;
    await executar(context, () => S.cad.excluirSimples(widget.tabela, reg['id'] as int), sucesso: 'Excluído');
    if (mounted) setState(() => _v++);
  }

  Future<Map<Object, String>> opcoesContas() async {
    final r = await banco.query('contas_financeiras', orderBy: 'nome');
    return {for (final x in r) x['id'] as int: x['nome'] as String};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      floatingActionButton: FloatingActionButton(onPressed: () => _editar(), child: const Icon(Icons.add)),
      body: Carregar<List<Map<String, Object?>>>(
        key: ValueKey(_v),
        futuro: () => S.cad.tabela(widget.tabela),
        builder: (context, l, rec) {
          if (l.isEmpty) return const Vazio('Nenhum registro.');
          return ListView(children: [
            for (final r in l)
              ListTile(
                title: Text(r['nome'] as String),
                subtitle: widget.subtitulo == null ? null : Text(widget.subtitulo!(r)),
                trailing: BotoesEditarExcluir(onEditar: () => _editar(r), onExcluir: () => _excluir(r)),
                onTap: () => _editar(r),
              ),
          ]);
        },
      ),
    );
  }
}

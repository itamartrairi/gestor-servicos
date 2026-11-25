import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/financeiro_service.dart';
import '../../services/pdf_service.dart';
import '../../services/relatorio_service.dart';
import '../widgets/comum.dart';
import '../widgets/logo.dart';
import '../widgets/seletores.dart';

/// Exatamente dois relatórios gerenciais em PDF.
class RelatoriosScreen extends StatelessWidget {
  const RelatoriosScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined, size: 36),
            title: const Text('PDF 1 — Fluxo de Caixa'),
            subtitle: const Text('Realizado, projetado ou ambos; por conta ou consolidado.'),
            onTap: () => abrir(context, const _FluxoCaixaFiltro()),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.stacked_bar_chart, size: 36),
            title: const Text('PDF 2 — Vendas e Custos'),
            subtitle: const Text('Receita, CPV, margens, produtos e compras por fornecedor.'),
            onTap: () => abrir(context, const _VendasCustosFiltro()),
          ),
        ),
      ]),
    );
  }
}

Future<CabecalhoPdf> _cabecalho(String titulo, String ini, String fim, List<String> filtros) async => CabecalhoPdf(
      negocio: await Base(banco).config('nome_negocio') ?? '',
      logoPath: await Logo.caminho(),
      titulo: titulo,
      periodo: '${dataBr(ini)} a ${dataBr(fim)}',
      filtros: filtros,
    );

class _FluxoCaixaFiltro extends StatefulWidget {
  const _FluxoCaixaFiltro();
  @override
  State<_FluxoCaixaFiltro> createState() => _FluxoCaixaFiltroState();
}

class _FluxoCaixaFiltroState extends State<_FluxoCaixaFiltro> {
  String _ini = isoData(inicioMes(DateTime.now()));
  String _fim = isoData(fimMes(DateTime.now()));
  int _conta = 0;
  String _tipo = 'ambos';
  Map<int, String> _contas = {};

  @override
  void initState() {
    super.initState();
    opcoesTabela('contas_financeiras').then((c) => setState(() => _contas = c));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fluxo de Caixa (PDF)')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        CampoData('Início do período', _ini, (v) => setState(() => _ini = v ?? _ini)),
        CampoData('Fim do período', _fim, (v) => setState(() => _fim = v ?? _fim)),
        CampoLista<int>('Conta financeira', _conta, {0: 'Todas as contas (consolidado)', ..._contas}, (v) => setState(() => _conta = v ?? 0)),
        CampoLista<String>('Tipo de fluxo', _tipo, const {'realizado': 'Realizado', 'projetado': 'Projetado', 'ambos': 'Ambos'},
            (v) => setState(() => _tipo = v!)),
        const SizedBox(height: 4),
        const Text('No projetado, a data de referência é o início do período e as parcelas em aberto vão até o fim do período.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Gerar PDF'),
          onPressed: () async {
            if (_fim.compareTo(_ini) < 0) {
              mostrarErro(context, 'O fim do período deve ser após o início');
              return;
            }
            final fin = S.fin;
            final contaId = _conta == 0 ? null : _conta;
            FluxoRealizado? r;
            FluxoProjetado? p;
            if (_tipo != 'projetado') r = await fin.fluxoRealizado(inicio: _ini, fim: _fim, contaId: contaId);
            if (_tipo != 'realizado') {
              final ref = isoData(parseIso(_ini).subtract(const Duration(days: 1)));
              p = await fin.fluxoProjetado(dataRef: ref, ate: _fim, contaId: contaId);
            }
            final cab = await _cabecalho('Fluxo de Caixa', _ini, _fim, [
              'Conta: ${_conta == 0 ? 'Todas' : _contas[_conta]}',
              'Tipo: ${const {'realizado': 'Realizado', 'projetado': 'Projetado', 'ambos': 'Realizado e projetado'}[_tipo]}',
            ]);
            final bytes = await PdfService.fluxoCaixa(cab: cab, realizado: r, projetado: p);
            if (context.mounted) {
              await abrir(context, VisualizarPdf(bytes: bytes, nome: 'fluxo_de_caixa_${_ini}_$_fim.pdf'));
            }
          },
        ),
      ]),
    );
  }
}

class _VendasCustosFiltro extends StatefulWidget {
  const _VendasCustosFiltro();
  @override
  State<_VendasCustosFiltro> createState() => _VendasCustosFiltroState();
}

class _VendasCustosFiltroState extends State<_VendasCustosFiltro> {
  String _ini = isoData(inicioMes(DateTime.now()));
  String _fim = isoData(fimMes(DateTime.now()));
  Map<String, Object?>? _produto;
  bool _soVariacao = false;
  int _categoria = 0;
  String _canal = '';
  Map<int, String> _categorias = {};
  List<String> _canais = [];

  @override
  void initState() {
    super.initState();
    () async {
      final c = await banco.query('categorias', where: "tipo = 'produto'", orderBy: 'nome');
      final canais = await S.relatorios.canais();
      setState(() {
        _categorias = {for (final x in c) x['id'] as int: x['nome'] as String};
        _canais = canais;
      });
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendas e Custos (PDF)')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        CampoData('Início do período', _ini, (v) => setState(() => _ini = v ?? _ini)),
        CampoData('Fim do período', _fim, (v) => setState(() => _fim = v ?? _fim)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(_produto == null ? 'Produto: todos' : 'Produto: ${_soVariacao ? nomeComVariacao(_produto!) : _produto!['nome']}'),
          trailing: _produto == null ? const Icon(Icons.search) : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _produto = null)),
          onTap: () async {
            final p = await escolherProduto(context);
            if (p != null) setState(() => _produto = p);
          },
        ),
        if (_produto != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _soVariacao,
            onChanged: (v) => setState(() => _soVariacao = v),
            title: const Text('Somente esta variação'),
          ),
        CampoLista<int>('Categoria', _categoria, {0: 'Todas', ..._categorias}, (v) => setState(() => _categoria = v ?? 0)),
        CampoLista<String>('Canal de venda', _canal, {'': 'Todos', for (final c in _canais) c: c}, (v) => setState(() => _canal = v ?? '')),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.picture_as_pdf),
          label: const Text('Gerar PDF'),
          onPressed: () async {
            final f = FiltroVendas(
              inicio: _ini,
              fim: _fim,
              itemId: _produto?['item_id'] as int?,
              variacaoId: _soVariacao ? (_produto?['variacao_id'] as int?) : null,
              categoriaId: _categoria == 0 ? null : _categoria,
              canal: _canal.isEmpty ? null : _canal,
            );
            final v = await S.relatorios.vendasCustos(f);
            final cab = await _cabecalho('Vendas e Custos', _ini, _fim, [
              'Produto: ${_produto == null ? 'Todos' : (_soVariacao ? nomeComVariacao(_produto!) : _produto!['nome'])}',
              'Categoria: ${_categoria == 0 ? 'Todas' : _categorias[_categoria]}',
              'Canal: ${_canal.isEmpty ? 'Todos' : _canal}',
            ]);
            final bytes = await PdfService.vendasCustos(cab: cab, v: v);
            if (context.mounted) {
              await abrir(context, VisualizarPdf(bytes: bytes, nome: 'vendas_e_custos_${_ini}_$_fim.pdf'));
            }
          },
        ),
      ]),
    );
  }
}

/// Visualização offline com salvar (pasta no Android / app Arquivos no iPhone),
/// imprimir e compartilhar pelo menu do aparelho.
class VisualizarPdf extends StatelessWidget {
  const VisualizarPdf({super.key, required this.bytes, required this.nome});
  final Uint8List bytes;
  final String nome;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Relatório'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: 'Salvar em…',
            onPressed: () async {
              await executar(context, () async {
                final caminho = await FilePicker.saveFile(
                  dialogTitle: 'Salvar PDF',
                  fileName: nome,
                  bytes: bytes,
                );
                if (caminho != null && context.mounted) mostrarOk(context, 'PDF salvo');
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Compartilhar',
            onPressed: () => Printing.sharePdf(bytes: bytes, filename: nome),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowSharing: true,
        allowPrinting: true,
        pdfFileName: nome,
      ),
    );
  }
}

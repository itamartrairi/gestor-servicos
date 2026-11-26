import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import 'base.dart';
import 'financeiro_service.dart';
import 'relatorio_service.dart';

class CabecalhoPdf {
  CabecalhoPdf({
    required this.negocio,
    this.logo,
    required this.titulo,
    required this.periodo,
    required this.filtros,
  });
  final String negocio;
  final Uint8List? logo;
  final String titulo;
  final String periodo;
  final List<String> filtros;
}

/// Gera os dois relatórios gerenciais em PDF (A4), totalmente offline.
class PdfService {
  static pw.Font? _reg;
  static pw.Font? _bold;

  static Future<pw.ThemeData> _tema() async {
    _reg ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    _bold ??= pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    return pw.ThemeData.withFont(base: _reg!, bold: _bold!);
  }

  static const _cinza = PdfColor.fromInt(0xFFEEEEEE);
  static const _destaque = PdfColor.fromInt(0xFFFFE0E0);
  static const _primaria = PdfColor.fromInt(0xFFB4457A);

  static pw.TextStyle get _s9 => const pw.TextStyle(fontSize: 8.5);
  static pw.TextStyle get _s9b => pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);

  static Future<pw.Document> _documento() async => pw.Document(theme: await _tema());

  static pw.PageTheme _pagina() => pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
      );

  static pw.Widget _header(pw.Context ctx, CabecalhoPdf c, pw.ImageProvider? logo, String emissao) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        if (logo != null)
          pw.Container(width: 46, height: 46, margin: const pw.EdgeInsets.only(right: 10), child: pw.Image(logo, fit: pw.BoxFit.contain)),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(c.negocio, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text(c.titulo, style: pw.TextStyle(fontSize: 11, color: _primaria, fontWeight: pw.FontWeight.bold)),
            pw.Text('Período: ${c.periodo}', style: _s9),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('Emitido em $emissao', style: _s9),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: _s9),
        ]),
      ]),
      if (c.filtros.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 3),
          child: pw.Text('Filtros: ${c.filtros.join(' | ')}', style: const pw.TextStyle(fontSize: 8)),
        ),
      pw.Divider(thickness: 0.6),
    ]);
  }

  static pw.Widget _footer(pw.Context ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Gestor de Serviços  •  Página ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
      );

  static pw.Widget _secao(String t) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: _primaria,
        child: pw.Text(t, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
      );

  /// Tabela com cabeçalho repetido em todas as páginas.
  static pw.Widget _tabela(List<String> cab, List<List<String>> linhas,
      {Map<int, pw.TableColumnWidth>? larguras, Set<int> direita = const {}, Set<int> destacar = const {}, Set<int> negrito = const {}}) {
    pw.Widget cel(String t, int col, {bool b = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          child: pw.Text(t, style: b ? _s9b : _s9, textAlign: direita.contains(col) ? pw.TextAlign.right : pw.TextAlign.left),
        );
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
      columnWidths: larguras,
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: _cinza),
          children: [for (var i = 0; i < cab.length; i++) cel(cab[i], i, b: true)],
        ),
        for (var r = 0; r < linhas.length; r++)
          pw.TableRow(
            decoration: destacar.contains(r) ? const pw.BoxDecoration(color: _destaque) : null,
            children: [for (var i = 0; i < linhas[r].length; i++) cel(linhas[r][i], i, b: negrito.contains(r))],
          ),
      ],
    );
  }

  static pw.Widget _resumo(List<(String, String)> itens) => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
        columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4)},
        children: [
          for (final i in itens)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(i.$1, style: _s9)),
              pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(i.$2, style: _s9b, textAlign: pw.TextAlign.right)),
            ]),
        ],
      );

  static Future<pw.ImageProvider?> _logo(Uint8List? bytes) async =>
      bytes == null ? null : pw.MemoryImage(bytes);

  // ===================== PDF 1 — FLUXO DE CAIXA =====================

  static Future<Uint8List> fluxoCaixa({
    required CabecalhoPdf cab,
    FluxoRealizado? realizado,
    FluxoProjetado? projetado,
  }) async {
    final doc = await _documento();
    final logo = await _logo(cab.logo);
    final emissao = dataHoraBr(DateTime.now().toIso8601String());
    doc.addPage(pw.MultiPage(
      pageTheme: _pagina(),
      header: (ctx) => _header(ctx, cab, logo, emissao),
      footer: _footer,
      build: (ctx) {
        final w = <pw.Widget>[];
        if (realizado != null) {
          w.add(_secao('FLUXO DE CAIXA REALIZADO'));
          w.add(_resumo([
            ('Saldo inicial', brl(realizado.saldoInicial)),
            ('(+) Total de entradas', brl(realizado.entradas)),
            ('(-) Total de saídas', brl(realizado.saidas)),
            ('Saldo final', brl(realizado.saldoFinal)),
          ]));
          w.add(pw.SizedBox(height: 6));
          w.add(pw.Text('Totais por categoria', style: _s9b));
          w.add(pw.SizedBox(height: 2));
          final cats = realizado.porCategoria.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
          w.add(_tabela(
            ['Categoria', 'Entradas', 'Saídas', 'Líquido'],
            [
              for (final c in cats)
                [c.key, brl(c.value['entradas']), brl(c.value['saidas']), brl((c.value['entradas'] ?? 0) - (c.value['saidas'] ?? 0))],
              ['Total', brl(realizado.entradas), brl(realizado.saidas), brl(realizado.entradas - realizado.saidas)],
            ],
            larguras: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.2), 2: pw.FlexColumnWidth(1.2), 3: pw.FlexColumnWidth(1.2)},
            direita: {1, 2, 3},
            negrito: {cats.length},
          ));
          w.add(pw.Text('Transferências entre contas aparecem como entrada e saída de mesmo valor: efeito líquido zero no consolidado.',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)));
          w.add(pw.SizedBox(height: 6));
          w.add(pw.Text('Movimentos', style: _s9b));
          w.add(pw.SizedBox(height: 2));
          w.add(_tabela(
            ['Data', 'Descrição', 'Categoria', 'Conta', 'Valor', 'Saldo acum.'],
            [
              for (final m in realizado.movimentos)
                [
                  dataBr(m['data'] as String),
                  (m['descricao'] as String?) ?? '',
                  (m['categoria'] as String?) ?? '',
                  (m['conta'] as String?) ?? '',
                  '${m['tipo'] == 'entrada' ? '' : '-'}${brl(Base.d(m['valor']))}',
                  brl(Base.d(m['saldo_acumulado'])),
                ],
            ],
            larguras: const {
              0: pw.FixedColumnWidth(48),
              1: pw.FlexColumnWidth(3.2),
              2: pw.FlexColumnWidth(2),
              3: pw.FlexColumnWidth(1.4),
              4: pw.FlexColumnWidth(1.3),
              5: pw.FlexColumnWidth(1.3),
            },
            direita: {4, 5},
          ));
        }
        if (projetado != null) {
          w.add(_secao('FLUXO DE CAIXA PROJETADO'));
          w.add(_resumo([
            ('Saldo na data de referência (${dataBr(projetado.dataRef)})', brl(projetado.saldoRef)),
            ('(+) Parcelas a receber em aberto', brl(projetado.aReceber)),
            ('     dos quais vencidos', brl(projetado.vencidosReceber)),
            ('(-) Parcelas a pagar em aberto', brl(projetado.aPagar)),
            ('     dos quais vencidos', brl(projetado.vencidosPagar)),
            ('Saldo projetado até ${dataBr(projetado.ate)}', brl(projetado.saldoProjetado)),
          ]));
          w.add(pw.SizedBox(height: 6));
          final destacar = <int>{};
          final linhas = <List<String>>[];
          for (var i = 0; i < projetado.itens.length; i++) {
            final t = projetado.itens[i];
            if (Base.i(t['vencido']) == 1) destacar.add(i);
            final nova = t['nova_previsao'] as String?;
            linhas.add([
              nova != null ? '${dataBr(t['vencimento'] as String)} → ${dataBr(nova)}' : dataBr(t['vencimento'] as String),
              t['tipo'] == 'receber' ? 'Receber' : 'Pagar',
              '${t['descricao']}${Base.i(t['vencido']) == 1 ? ' (VENCIDO)' : ''}',
              (t['cliente'] ?? t['fornecedor'] ?? '') as String,
              '${t['tipo'] == 'receber' ? '' : '-'}${brl(Base.d(t['aberto']))}',
              brl(Base.d(t['saldo_projetado'])),
            ]);
          }
          w.add(_tabela(
            ['Vencimento / previsão', 'Tipo', 'Descrição', 'Cliente/Fornecedor', 'Em aberto', 'Saldo proj.'],
            linhas,
            larguras: const {
              0: pw.FlexColumnWidth(1.8),
              1: pw.FixedColumnWidth(40),
              2: pw.FlexColumnWidth(3),
              3: pw.FlexColumnWidth(1.6),
              4: pw.FlexColumnWidth(1.2),
              5: pw.FlexColumnWidth(1.2),
            },
            direita: {4, 5},
            destacar: destacar,
          ));
          w.add(pw.Text('Linhas em destaque: títulos vencidos. "→" indica a data original e a nova previsão.',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)));
        }
        return w;
      },
    ));
    return doc.save();
  }

  // ===================== PDF 2 — VENDAS E CUSTOS =====================

  static Future<Uint8List> vendasCustos({required CabecalhoPdf cab, required VendasCustos v}) async {
    final doc = await _documento();
    final logo = await _logo(cab.logo);
    final emissao = dataHoraBr(DateTime.now().toIso8601String());
    String mg(double? m) => m == null ? '—' : pct(m);
    doc.addPage(pw.MultiPage(
      pageTheme: _pagina(),
      header: (ctx) => _header(ctx, cab, logo, emissao),
      footer: _footer,
      build: (ctx) => [
        _secao('RESUMO DE VENDAS'),
        _resumo([
          ('Vendas concluídas', '${v.vendas}'),
          ('Ticket médio (receita líquida ÷ vendas)', brl(v.ticketMedio)),
          ('Receita bruta', brl(v.receitaBruta)),
          ('(-) Descontos', brl(v.descontos)),
          ('(-) Devoluções e estornos', brl(v.devolucoes)),
          ('(-) Impostos sobre vendas', brl(v.impostos)),
          ('Receita líquida', brl(v.receitaLiquida)),
          ('(-) Custo dos produtos vendidos (CPV)', brl(v.cpv)),
          ('Lucro bruto', brl(v.lucroBruto)),
          ('Margem bruta', mg(v.margemBruta)),
          ('Despesas variáveis de venda (taxas, comissões, entregas)${v.despesasRateadas ? ' – rateadas' : ''}',
              brl(v.despesasVariaveisVenda)),
          ('Margem de contribuição',
              v.margemContribuicao == null ? 'Pendente*' : brl(v.margemContribuicao)),
        ]),
        if (v.margemContribuicao == null)
          pw.Text(
              '* Cálculo pendente: há produtos vendidos sem a parcela variável do CPV classificada no cadastro. '
              'Valores disponíveis: receita líquida ${brl(v.receitaLiquida)}, CPV ${brl(v.cpv)}, despesas variáveis ${brl(v.despesasVariaveisVenda)}.',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        pw.Text('Lucro bruto = receita líquida − CPV. Margem bruta = lucro bruto ÷ receita líquida × 100.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        _secao('DETALHAMENTO POR PRODUTO E VARIAÇÃO (itens vendidos)'),
        _tabela(
          ['Produto / variação', 'Un.', 'Qtd', 'Preço méd.', 'Rec. líquida', 'Custo un. méd.', 'CPV', 'Lucro bruto', 'Margem'],
          [
            for (final p in v.produtos)
              [
                p.nome,
                p.unidade,
                p.itemId == 0 ? '—' : numero(p.quantidade),
                p.itemId == 0 ? '—' : brl(p.precoMedio),
                brl(p.receitaLiquida),
                p.itemId == 0 ? '—' : brl(p.custoUnitarioMedio),
                brl(p.cpv),
                brl(p.lucroBruto),
                mg(p.margem),
              ],
          ],
          larguras: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FixedColumnWidth(34),
            2: pw.FixedColumnWidth(34),
            3: pw.FlexColumnWidth(1.1),
            4: pw.FlexColumnWidth(1.2),
            5: pw.FlexColumnWidth(1.1),
            6: pw.FlexColumnWidth(1.1),
            7: pw.FlexColumnWidth(1.1),
            8: pw.FixedColumnWidth(38),
          },
          direita: {2, 3, 4, 5, 6, 7, 8},
        ),
        if (v.devolucoesLista.isNotEmpty) ...[
          _secao('DEVOLUÇÕES E ESTORNOS'),
          _tabela(
            ['Data', 'Descrição', 'Valor'],
            [for (final d in v.devolucoesLista) [dataBr(d['data'] as String), d['descricao'] as String, brl(Base.d(d['valor']))]],
            larguras: const {0: pw.FixedColumnWidth(50), 1: pw.FlexColumnWidth(4), 2: pw.FlexColumnWidth(1.2)},
            direita: {2},
          ),
        ],
        _secao('COMPRAS DE MERCADORIAS NO PERÍODO (POR FORNECEDOR)'),
        pw.Text(
            'Compras vão para o estoque. O CPV acima considera apenas o custo dos lotes efetivamente vendidos.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
        pw.SizedBox(height: 3),
        _resumo([for (final e in v.custosProducao.entries) (e.key, brl(e.value))]),
        pw.SizedBox(height: 6),
        _tabela(
          ['Data', 'Compra', 'Fornecedor', 'Documento', 'Qtd itens', 'Total'],
          [
            for (final o in v.ordens)
              [
                dataBr(o['data'] as String?),
                '#${o['id']}',
                o['fornecedor'] as String,
                (o['ciclo'] as String?) ?? '-',
                numero(Base.d(o['qtd_itens'])),
                brl(Base.d(o['total'])),
              ],
          ],
          larguras: const {
            0: pw.FixedColumnWidth(50),
            1: pw.FixedColumnWidth(36),
            2: pw.FlexColumnWidth(3),
            3: pw.FlexColumnWidth(1.6),
            4: pw.FlexColumnWidth(1),
            5: pw.FlexColumnWidth(1.2),
          },
          direita: {4, 5},
        ),
      ],
    ));
    return doc.save();
  }
}

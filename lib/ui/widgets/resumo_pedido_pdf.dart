import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format.dart';
import '../../services/base.dart';
import 'comum.dart';
import 'logo.dart';
import 'seletores.dart';

/// Resumo do pedido para imprimir ou compartilhar com o cliente (não é um relatório gerencial).
Future<Uint8List> gerarResumoPedido(int pedidoId) async {
  final reg = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
  final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: reg, bold: bold));
  final p = (await banco.rawQuery(
          'SELECT p.*, c.nome cliente, c.telefone FROM pedidos p LEFT JOIN clientes c ON c.id = p.cliente_id WHERE p.id = ?', [pedidoId]))
      .first;
  final itens = await S.pedidos.itens(pedidoId);
  final t = await S.pedidos.totais(pedidoId);
  final negocio = await Base(banco).config('nome_negocio') ?? '';
  final logoBytes = await Logo.bytes();
  final logo = logoBytes == null ? null : pw.MemoryImage(logoBytes);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a5,
    margin: const pw.EdgeInsets.all(24),
    build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(children: [
        if (logo != null) pw.Container(width: 40, height: 40, margin: const pw.EdgeInsets.only(right: 8), child: pw.Image(logo)),
        pw.Expanded(child: pw.Text(negocio, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
      ]),
      pw.SizedBox(height: 8),
      pw.Text('Pedido #$pedidoId', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.Text('Cliente: ${p['cliente'] ?? '-'} ${p['telefone'] ?? ''}'),
      if (p['tipo'] != 'balcao') pw.Text('Entrega: ${dataBr(p['data_entrega'] as String?)} ${p['hora_entrega'] ?? ''}'),
      if (p['personalizacao'] != null) pw.Text('Personalização: ${p['personalizacao']}'),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: ['Produto', 'Qtd', 'Unit.', 'Total'],
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        data: [
          for (final i in itens)
            [
              nomeComVariacao(i),
              '${numero(Base.d(i['quantidade']))} ${i['unidade_venda'] ?? ''}',
              brl(Base.d(i['preco_unitario'])),
              brl(Base.d(i['quantidade']) * Base.d(i['preco_unitario'])),
            ],
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Text('Subtotal: ${brl(t['subtotal'])}'),
      if (t['desconto']! > 0) pw.Text('Desconto: ${brl(t['desconto'])}'),
      if (t['frete']! > 0) pw.Text('Frete: ${brl(t['frete'])}'),
      pw.Text('Total: ${brl(t['total'])}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      pw.Text('Pago: ${brl(t['pago']! - t['devolvido']!)}   Saldo: ${brl(t['saldo'])}'),
      pw.Spacer(),
      pw.Text('Emitido em ${dataHoraBr(DateTime.now().toIso8601String())}', style: const pw.TextStyle(fontSize: 8)),
    ]),
  ));
  return doc.save();
}

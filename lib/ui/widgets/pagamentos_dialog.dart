import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/pedido_service.dart';
import 'comum.dart';

/// Coleta um ou mais pagamentos (dinheiro, Pix, cartão…), inclusive mistos e parciais.
/// Devolve null se cancelado.
Future<List<PagamentoInfo>?> coletarPagamentos(BuildContext context,
    {required double valorSugerido, String titulo = 'Pagamento', bool permitirZero = true, bool exigirTotal = false}) async {
  final meios = await banco.query('meios_pagamento', where: 'ativo = 1', orderBy: 'id');
  if (!context.mounted) return null;
  final linhas = <(int, TextEditingController)>[
    (meios.first['id'] as int, TextEditingController(text: fmtCampo(valorSugerido))),
  ];
  return showDialog<List<PagamentoInfo>>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final soma = linhas.fold(0.0, (s, l) => s + parseNum(l.$2.text));
      final falta = r2(valorSugerido - soma);
      return AlertDialog(
        title: Text(titulo),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              LinhaValor('Valor', brl(valorSugerido), negrito: true),
              for (var i = 0; i < linhas.length; i++)
                Row(children: [
                  Expanded(
                    flex: 5,
                    child: CampoLista<int>('Meio', linhas[i].$1, {for (final m in meios) m['id'] as int: m['nome'] as String},
                        (v) => set(() => linhas[i] = (v ?? linhas[i].$1, linhas[i].$2))),
                  ),
                  const SizedBox(width: 6),
                  Expanded(flex: 4, child: CampoNumero('Valor', linhas[i].$2, prefixo: 'R\$ ', onChanged: (_) => set(() {}))),
                  if (linhas.length > 1)
                    IconButton(icon: const Icon(Icons.close), onPressed: () => set(() => linhas.removeAt(i))),
                ]),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Outro meio (pagamento misto)'),
                  onPressed: () => set(() => linhas.add((meios.first['id'] as int, TextEditingController(text: falta > 0 ? fmtCampo(falta) : '')))),
                ),
              ),
              LinhaValor(falta >= 0 ? 'Restante' : 'Excedente', brl(falta.abs()),
                  cor: falta.abs() < 0.005 ? Colors.green : Colors.orange.shade800),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (falta < -0.005) {
                mostrarErro(c, 'A soma dos pagamentos supera o valor');
                return;
              }
              if (exigirTotal && falta.abs() > 0.005) {
                mostrarErro(c, 'Informe pagamentos que somem o total');
                return;
              }
              if (!permitirZero && soma <= 0) {
                mostrarErro(c, 'Informe o valor');
                return;
              }
              Navigator.pop(c, [
                for (final l in linhas)
                  if (parseNum(l.$2.text) > 0) PagamentoInfo(meioId: l.$1, valor: parseNum(l.$2.text)),
              ]);
            },
            child: const Text('Confirmar'),
          ),
        ],
      );
    }),
  );
}

/// Pergunta como parcelar o valor que fica no fiado. Devolve
/// (parcelas, intervalo em dias, 1º vencimento) ou null se cancelado.
Future<(int, int, String)?> pedirParcelamento(BuildContext context, double valor) async {
  final parcelas = TextEditingController(text: '1');
  final intervalo = TextEditingController(text: '30');
  var venc = isoData(DateTime.now().add(const Duration(days: 30)));
  return showDialog<(int, int, String)>(
    context: context,
    builder: (c) => StatefulBuilder(builder: (c, set) {
      final n = int.tryParse(parcelas.text) ?? 1;
      return AlertDialog(
        title: const Text('Fiado / venda a prazo'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            LinhaValor('Valor a prazo', brl(valor), negrito: true),
            Row(children: [
              Expanded(child: CampoNumero('Parcelas', parcelas, inteiro: true, onChanged: (_) => set(() {}))),
              const SizedBox(width: 8),
              Expanded(child: CampoNumero('Intervalo', intervalo, inteiro: true, sufixo: 'dias')),
            ]),
            CampoData('1º vencimento', venc, (v) => set(() => venc = v ?? venc)),
            if (n > 1) Text('$n parcelas de cerca de ${brl(valor / n)}', style: const TextStyle(fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final np = int.tryParse(parcelas.text) ?? 0;
              final iv = int.tryParse(intervalo.text) ?? 0;
              if (np < 1 || np > 24) {
                mostrarErro(c, 'Informe de 1 a 24 parcelas');
                return;
              }
              if (iv < 1) {
                mostrarErro(c, 'Informe o intervalo em dias');
                return;
              }
              Navigator.pop(c, (np, iv, venc));
            },
            child: const Text('Confirmar'),
          ),
        ],
      );
    }),
  );
}

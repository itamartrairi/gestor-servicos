import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'comum.dart';

String nomeComVariacao(Map<String, Object?> m) {
  final v = m['variacao'] as String?;
  return v == null || v == 'Padrão' ? (m['nome'] as String? ?? '') : '${m['nome']} - $v';
}

/// Lista pesquisável em diálogo de tela cheia.
Future<Map<String, Object?>?> escolherDaLista(
  BuildContext context, {
  required String titulo,
  required List<Map<String, Object?>> itens,
  required String Function(Map<String, Object?>) rotulo,
  String Function(Map<String, Object?>)? subtitulo,
}) {
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (c) {
      var filtro = '';
      return StatefulBuilder(builder: (c, set) {
        final lista = itens.where((i) => rotulo(i).toLowerCase().contains(filtro.toLowerCase())).toList();
        return Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(title: Text(titulo)),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Pesquisar', border: OutlineInputBorder()),
                  onChanged: (v) => set(() => filtro = v),
                ),
              ),
              Expanded(
                child: lista.isEmpty
                    ? const Vazio('Nada encontrado. Cadastre em Mais > Cadastros.')
                    : ListView.builder(
                        itemCount: lista.length,
                        itemBuilder: (c, i) => ListTile(
                          title: Text(rotulo(lista[i])),
                          subtitle: subtitulo == null ? null : Text(subtitulo(lista[i])),
                          onTap: () => Navigator.pop(c, lista[i]),
                        ),
                      ),
              ),
            ]),
          ),
        );
      });
    },
  );
}

Future<Map<String, Object?>?> escolherProduto(BuildContext context,
    {List<String> tipos = const ['acabado']}) async {
  final itens = await S.cad.produtosVendaveis(tipos: tipos);
  if (!context.mounted) return null;
  return escolherDaLista(context,
      titulo: 'Escolher produto',
      itens: itens,
      rotulo: (m) => [
            if ((m['codigo'] as String?)?.isNotEmpty == true) '${m['codigo']}',
            nomeComVariacao(m),
          ].join(' • '),
      subtitulo: (m) => [
            '${brl(m['preco_venda'] as num?)} / ${m['unidade_venda']}',
            if (m['marca'] != null) '${m['marca']}',
            if ((m['codigo_barras'] as String?)?.isNotEmpty == true) 'EAN ${m['codigo_barras']}',
            'estoque ${numero(m['estoque'] as num?)}',
          ].join(' • '));
}

Future<Map<String, Object?>?> escolherCliente(BuildContext context) async {
  final itens = await S.cad.tabela('clientes');
  if (!context.mounted) return null;
  return escolherDaLista(context,
      titulo: 'Cliente', itens: itens, rotulo: (m) => m['nome'] as String, subtitulo: (m) => (m['telefone'] as String?) ?? '');
}

Future<Map<int, String>> opcoesTabela(String tabela, {String? where}) async {
  final r = await banco.query(tabela, where: where ?? 'ativo = 1', orderBy: 'nome');
  return {for (final x in r) x['id'] as int: x['nome'] as String};
}

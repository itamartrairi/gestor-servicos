import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

String _chave(String nome) => 'gestor_servicos_$nome';

Future<Uint8List?> ler(String nome) async {
  final v = web.window.localStorage.getItem(_chave(nome));
  return v == null ? null : base64Decode(v);
}

Future<void> gravar(String nome, Uint8List? bytes) async {
  if (bytes == null) {
    web.window.localStorage.removeItem(_chave(nome));
  } else {
    web.window.localStorage.setItem(_chave(nome), base64Encode(bytes));
  }
}

import 'dart:typed_data';

import 'armazenamento_io.dart' if (dart.library.js_interop) 'armazenamento_web.dart' as impl;

/// Guarda pequenos arquivos do app (logomarca): pasta do app no celular,
/// armazenamento do navegador na versão web.
class Armazenamento {
  static Future<Uint8List?> ler(String nome) => impl.ler(nome);
  static Future<void> gravar(String nome, Uint8List? bytes) => impl.gravar(nome, bytes);
}

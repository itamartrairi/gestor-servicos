import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Ponto único de acesso ao file_picker (a build para iOS 12 troca este
/// arquivo por tool/ios12/arquivos_legado.dart.txt, que usa a API antiga).
/// Devolve true se o arquivo foi salvo.
Future<bool> salvarArquivo({required String titulo, required String nome, required Uint8List bytes}) async =>
    (await FilePicker.saveFile(dialogTitle: titulo, fileName: nome, bytes: bytes)) != null || kIsWeb;

/// Abre o seletor e devolve o conteúdo do arquivo escolhido (ou null).
Future<Uint8List?> escolherArquivo() async {
  final arquivo = await FilePicker.pickFile();
  if (arquivo == null) return null;
  return Uint8List.fromList(await arquivo.readAsBytes());
}

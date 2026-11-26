import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Ponto único de acesso ao file_picker (a build para iOS 12 troca este
/// arquivo por tool/ios12/arquivos_legado.dart.txt, que usa a API antiga).
Future<String?> salvarArquivo({required String titulo, required String nome, required Uint8List bytes}) =>
    FilePicker.saveFile(dialogTitle: titulo, fileName: nome, bytes: bytes);

/// Abre o seletor e devolve o conteúdo do arquivo escolhido (ou null).
Future<Uint8List?> escolherArquivo() async {
  final arquivo = await FilePicker.pickFile();
  if (arquivo == null) return null;
  return Uint8List.fromList(await arquivo.readAsBytes());
}

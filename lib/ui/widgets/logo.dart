import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Logomarca guardada na pasta de documentos do app (incluída no backup).
class Logo {
  static Future<String> _destino() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'logo.png');
  }

  static Future<String?> caminho() async {
    final d = await _destino();
    return await File(d).exists() ? d : null;
  }

  static Future<String?> escolher(BuildContext context) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600);
    if (img == null) return null;
    final d = await _destino();
    await File(img.path).copy(d);
    PaintingBinding.instance.imageCache.clear();
    return d;
  }

  static Future<void> remover() async {
    final d = await _destino();
    if (await File(d).exists()) await File(d).delete();
    PaintingBinding.instance.imageCache.clear();
  }
}

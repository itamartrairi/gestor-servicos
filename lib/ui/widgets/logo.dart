import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/armazenamento.dart';

/// Logomarca do negócio (incluída no backup).
class Logo {
  static const arquivo = 'logo.png';

  static Future<Uint8List?> bytes() => Armazenamento.ler(arquivo);

  static Future<Uint8List?> escolher(BuildContext context) async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, maxHeight: 600);
    if (img == null) return null;
    final b = await img.readAsBytes();
    await Armazenamento.gravar(arquivo, b);
    PaintingBinding.instance.imageCache.clear();
    return b;
  }

  static Future<void> remover() async {
    await Armazenamento.gravar(arquivo, null);
    PaintingBinding.instance.imageCache.clear();
  }
}

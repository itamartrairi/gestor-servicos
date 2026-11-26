import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

Future<void> configurarBanco() async {
  // Sem worker: funciona igual no Safari (iPhone) e no Chrome (Android).
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
}

import 'fabrica_io.dart' if (dart.library.js_interop) 'fabrica_web.dart' as impl;

/// Na web, o SQLite roda no navegador (WebAssembly + IndexedDB).
Future<void> configurarBanco() => impl.configurarBanco();

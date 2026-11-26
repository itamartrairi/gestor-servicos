// Gera as capturas de tela usadas no tutorial (não faz parte dos testes
// normais). Rode: flutter test test_telas/telas_test.dart
// As imagens ficam em test_telas/telas/.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_servicos/data/db.dart';
import 'package:gestor_servicos/main.dart';
import 'package:gestor_servicos/services/base.dart';
import 'package:gestor_servicos/ui/screens/agenda_screen.dart';
import 'package:gestor_servicos/ui/screens/cadastros_screen.dart';
import 'package:gestor_servicos/ui/screens/dre_screen.dart';
import 'package:gestor_servicos/ui/screens/fiado_screen.dart';
import 'package:gestor_servicos/ui/screens/home_screen.dart';
import 'package:gestor_servicos/ui/screens/relatorios_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _CaminhosFalsos extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _CaminhosFalsos(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}

Future<void> _carregarFonte(String familia, List<String> arquivos) async {
  final f = FontLoader(familia);
  for (final a in arquivos) {
    final bytes = File(a).readAsBytesSync();
    f.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await f.load();
}

final _chave = GlobalKey();

Future<void> _assentar(WidgetTester t, {int max = 80}) async {
  for (var i = 0; i < max; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 60));
    if (i > 6 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await t.pump(const Duration(milliseconds: 600));
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _foto(WidgetTester t, String nome) async {
  await _assentar(t);
  final limite = _chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final img = await limite.toImage(pixelRatio: 3);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('test_telas/telas/$nome.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(png!.buffer.asUint8List());
  });
}

NavigatorState _nav(WidgetTester t) => Navigator.of(t.element(find.byType(HomeScreen, skipOffstage: false)));

Future<void> _abrir(WidgetTester t, Widget tela) async {
  _nav(t).push(MaterialPageRoute(builder: (_) => tela));
  await _assentar(t);
}

Future<void> _voltar(WidgetTester t) async {
  _nav(t).pop();
  await _assentar(t);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('telas');
    PathProviderPlatform.instance = _CaminhosFalsos(tmp.path);
    Intl.defaultLocale = 'pt_BR';
    await initializeDateFormatting('pt_BR');
    await _carregarFonte('Roboto', ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf']);
    final raiz = Platform.environment['FLUTTER_ROOT'] ?? '';
    await _carregarFonte('MaterialIcons', ['$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  void tamanhoCelular(WidgetTester t) {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  testWidgets('primeira abertura', (t) async {
    tamanhoCelular(t);
    await t.runAsync(() => AppDb.abrir(caminho: '${tmp.path}/vazio.db', factory: databaseFactoryFfi));
    await t.pumpWidget(RepaintBoundary(key: _chave, child: const GestorApp()));
    await _foto(t, '00_primeira_abertura');
    await t.runAsync(() => AppDb.instance.fechar());
  });

  testWidgets('telas do app', (t) async {
    tamanhoCelular(t);
    await t.runAsync(() async {
      final app = await AppDb.abrir(caminho: '${tmp.path}/demo.db', factory: databaseFactoryFfi);
      await Base(app.db).setConfig('nome_negocio', 'Studio Bela');
    });
    await t.pumpWidget(RepaintBoundary(key: _chave, child: const GestorApp()));
    await _assentar(t, max: 200);
    await _foto(t, '01_inicio');

    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -700));
    await _foto(t, '02_inicio_meio');
    await t.drag(find.byType(CustomScrollView).first, const Offset(0, -900));
    await _foto(t, '03_inicio_fim');

    await t.tap(find.text('Agenda').last);
    await _foto(t, '04_agenda');
    await t.tap(find.byType(CartaoAtendimento).at(2));
    await _foto(t, '05_agenda_acoes');
    await t.tap(find.text('Concluir e receber').first);
    await _foto(t, '06_concluir');
    await t.tap(find.text('Receber').first);
    await _foto(t, '07_pagamento');
    await t.tap(find.text('Cancelar').last);
    await _assentar(t);

    await t.tap(find.text('Agendar').first);
    await _foto(t, '08_novo_agendamento');
    await t.tap(find.text('Escolher serviço').first);
    await _foto(t, '09_escolher_servico');
    await t.tap(find.text('Manicure').last);
    await _assentar(t);
    await _foto(t, '10_agendamento_preenchido');
    _nav(t).pop();
    await _assentar(t);

    await t.tap(find.text('Vendas').last);
    await _foto(t, '11_vendas');
    await t.tap(find.text('Novo').first);
    await _foto(t, '12_tipo_venda');
    await t.tap(find.textContaining('Venda rápida').first);
    await _foto(t, '13_venda_rapida');
    _nav(t).pop();
    await _assentar(t);

    await t.tap(find.text('Financeiro').last);
    await _foto(t, '14_financeiro_contas');
    await t.tap(find.text('A pagar').first);
    await _foto(t, '15_financeiro_pagar');
    await t.tap(find.text('Fluxo de caixa').first);
    await _foto(t, '16_fluxo_caixa');

    await t.tap(find.text('Mais').last);
    await _foto(t, '17_mais');
    await _abrir(t, const CadastrosScreen());
    await _foto(t, '18_cadastros');
    await t.tap(find.text('Serviços').first);
    await _foto(t, '19_servicos');
    await t.tap(find.byType(FloatingActionButton).last);
    await _foto(t, '20_novo_servico');
    _nav(t).pop();
    await _assentar(t);
    _nav(t).pop();
    await _assentar(t);
    await t.tap(find.text('Clientes').first);
    await _foto(t, '21_clientes');
    _nav(t).pop();
    await _assentar(t);
    await _voltar(t);

    await _abrir(t, const DreScreen());
    await _foto(t, '22_dre');
    await _voltar(t);
    await _abrir(t, const FiadoScreen());
    await _foto(t, '23_fiado');
    await _voltar(t);
    await _abrir(t, const RelatoriosScreen());
    await _foto(t, '24_relatorios');
    await _voltar(t);
  });
}


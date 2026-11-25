import 'dart:io';

import 'package:flutter/material.dart';

import '../../main.dart';
import '../../services/base.dart';
import '../widgets/comum.dart';
import '../widgets/logo.dart';

/// Primeira abertura: nome do negócio e logomarca.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nome = TextEditingController();
  String? _logo;

  @override
  void initState() {
    super.initState();
    Logo.caminho().then((p) => setState(() => _logo = p));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          Icon(Icons.spa_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text('Bem-vinda ao Gestor de Serviços',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Seus dados ficam guardados somente neste celular e o app funciona sem internet.',
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          CampoTexto('Nome do seu negócio (ex.: Studio Bela)', _nome),
          const SizedBox(height: 12),
          Center(
            child: Column(children: [
              if (_logo != null)
                Image.file(File(_logo!), height: 96, key: ValueKey(DateTime.now().millisecondsSinceEpoch)),
              TextButton.icon(
                icon: const Icon(Icons.image_outlined),
                label: Text(_logo == null ? 'Adicionar logomarca (opcional)' : 'Trocar logomarca'),
                onPressed: () async {
                  final p = await Logo.escolher(context);
                  if (p != null) setState(() => _logo = p);
                },
              ),
            ]),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              if (_nome.text.trim().isEmpty) {
                mostrarErro(context, 'Informe o nome do negócio');
                return;
              }
              await Base(banco).setConfig('nome_negocio', _nome.text.trim());
              GestorApp.reiniciar.value++;
            },
            child: const Padding(padding: EdgeInsets.all(12), child: Text('Começar')),
          ),
        ]),
      ),
    );
  }
}

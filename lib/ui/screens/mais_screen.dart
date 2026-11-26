import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/comum.dart';
import 'cadastros_screen.dart';
import 'compras_screen.dart';
import 'config_screen.dart';
import 'dre_screen.dart';
import 'estoque_screen.dart';
import 'fiado_screen.dart';
import 'financeiro_screen.dart';
import 'relatorios_screen.dart';
import 'tabelas_preco_screen.dart';

class MaisScreen extends StatelessWidget {
  const MaisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final itens = <(IconData, String, String, Widget)>[
      (Icons.payments_outlined, 'Fiado / vendas a prazo', 'Clientes devedores, parcelas e recebimentos', const FiadoScreen()),
      (Icons.sell_outlined, 'Tabelas de preço', 'Varejo, atacado, promoção e margens', const TabelasPrecoScreen()),
      (Icons.inventory_2_outlined, 'Estoque', 'Produtos para venda e materiais', const EstoqueScreen()),
      (Icons.shopping_cart_outlined, 'Compras', 'Compras de produtos e materiais, contas a pagar', const ComprasScreen()),
      (Icons.account_balance_outlined, 'Financeiro', 'Contas, pagar/receber e fluxo de caixa', const FinanceiroScreen()),
      (Icons.analytics_outlined, 'DRE', 'Resultado gerencial por competência', const DreScreen()),
      (Icons.picture_as_pdf_outlined, 'Relatórios', 'Fluxo de Caixa e Vendas e Custos (PDF)', const RelatoriosScreen()),
      (Icons.folder_open_outlined, 'Cadastros', 'Serviços, produtos, clientes, fornecedores…', const CadastrosScreen()),
      (Icons.settings_outlined, 'Configurações', 'Negócio, logomarca, backup e restauração', const ConfigScreen()),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mais'),
      ),
      backgroundColor: const Color(0xFFFBF3F7),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        for (final i in itens)
          ListTile(
            leading: Icon(i.$1),
            title: Text(i.$2),
            subtitle: Text(i.$3),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => abrir(context, i.$4),
          ),
      ]),
    );
  }
}

class ContaLocal {
  static final sessao = ValueNotifier<String?>(null);

  static Future<File> _arquivo() async {
    final pasta = await getApplicationSupportDirectory();
    return File('${pasta.path}/gestor_conta_v1.json');
  }

  static Future<bool> existe() async => (await _arquivo()).exists();
  static bool _gravando = false;

  static Future<List<int>> _verificador(String senha, List<int> sal) async {
    final chave = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 600000, bits: 256)
        .deriveKey(secretKey: SecretKey(utf8.encode(senha)), nonce: sal);
    return chave.extractBytes();
  }

  static Future<String?> entrar(String email, String senha, bool cadastrar) async {
    final arquivo = await _arquivo();
    if (cadastrar) {
      if (_gravando) return 'Há um cadastro em andamento.';
      _gravando = true;
      try {
        if (await arquivo.exists()) return 'Já existe uma conta neste aparelho. Use Login.';
        final aleatorio = Random.secure();
        final sal = List<int>.generate(32, (_) => aleatorio.nextInt(256));
        final hash = await _verificador(senha, sal);
        await arquivo.parent.create(recursive: true);
        final temporario = File('${arquivo.path}.tmp');
        await temporario.writeAsString(
          jsonEncode({'email': email, 'sal': base64Encode(sal), 'hash': base64Encode(hash)}),
          flush: true,
        );
        await temporario.rename(arquivo.path);
      } finally {
        _gravando = false;
      }
    } else {
      if (!await arquivo.exists()) return 'Cadastre uma conta primeiro.';
      final dados = jsonDecode(await arquivo.readAsString()) as Map<String, dynamic>;
      final hash = base64Decode(dados['hash'] as String);
      final atual = await _verificador(senha, base64Decode(dados['sal'] as String));
      if (hash.length != atual.length) return 'E-mail ou senha incorretos.';
      var diferenca = 0;
      for (var i = 0; i < hash.length; i++) {
        diferenca |= hash[i] ^ atual[i];
      }
      if (diferenca != 0 || dados['email'] != email) return 'E-mail ou senha incorretos.';
    }
    sessao.value = email;
    return null;
  }
}

class FormularioConta extends StatefulWidget {
  const FormularioConta(this.cadastrar, {super.key});
  final bool cadastrar;

  @override
  State<FormularioConta> createState() => _FormularioContaState();
}

class _FormularioContaState extends State<FormularioConta> {
  final _formulario = GlobalKey<FormState>();
  String _email = '';
  String _senha = '';
  String? _erro;
  bool _ocupado = false;

  Future<void> _confirmar() async {
    if (_ocupado || !_formulario.currentState!.validate()) return;
    setState(() {
      _ocupado = true;
      _erro = null;
    });
    String? erro;
    try {
      erro = await ContaLocal.entrar(_email.trim().toLowerCase(), _senha, widget.cadastrar);
    } on Exception {
      erro = 'Não foi possível acessar a conta local.';
    }
    if (!mounted) return;
    if (erro == null) {
      return;
    }
    setState(() {
      _ocupado = false;
      _erro = erro;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_ocupado,
    child: AlertDialog(
      title: Text(widget.cadastrar ? 'Cadastro de conta' : 'Login'),
      scrollable: true,
      content: Form(
        key: _formulario,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              enabled: !_ocupado,
              decoration: const InputDecoration(labelText: 'E-mail'),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onChanged: (valor) => _email = valor,
              validator: (valor) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(valor?.trim() ?? '')
                  ? null
                  : 'Informe um e-mail válido.',
            ),
            TextFormField(
              enabled: !_ocupado,
              decoration: const InputDecoration(labelText: 'Senha'),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (valor) => _senha = valor,
              validator: (valor) => (valor?.length ?? 0) < 8 ? 'Use pelo menos 8 caracteres.' : null,
            ),
            if (widget.cadastrar)
              TextFormField(
                enabled: !_ocupado,
                decoration: const InputDecoration(labelText: 'Confirmar senha'),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                validator: (valor) => valor == _senha ? null : 'As senhas precisam ser iguais.',
              ),
            if (_erro case final mensagem?)
              Text(mensagem, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _ocupado ? null : _confirmar,
          child: Text(_ocupado ? 'Aguarde…' : (widget.cadastrar ? 'Cadastrar' : 'Entrar')),
        ),
      ],
    ),
  );
}

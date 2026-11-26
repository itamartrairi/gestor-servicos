import 'dart:io';
import 'dart:typed_data';

import '../../core/arquivos.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../main.dart';
import '../../services/backup_service.dart';
import '../../services/base.dart';
import '../../services/demo_service.dart';
import '../widgets/comum.dart';
import '../widgets/logo.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});
  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  final _nome = TextEditingController();
  final _imposto = TextEditingController();
  final _alerta = TextEditingController();
  final _margem = TextEditingController();
  String? _logo;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final b = Base(banco);
    _nome.text = await b.config('nome_negocio') ?? '';
    _imposto.text = (await b.config('pct_imposto_vendas') ?? '0').replaceAll('.', ',');
    _alerta.text = await b.config('alerta_validade_dias') ?? '3';
    _margem.text = (await b.config('margem_padrao_pct') ?? '30').replaceAll('.', ',');
    _logo = await Logo.caminho();
    setState(() => _ok = true);
  }

  Future<void> _salvar() async {
    final b = Base(banco);
    await b.setConfig('nome_negocio', _nome.text.trim());
    await b.setConfig('pct_imposto_vendas', parseNum(_imposto.text).toString());
    await b.setConfig('alerta_validade_dias', '${parseNum(_alerta.text).round()}');
    await b.setConfig('margem_padrao_pct', parseNum(_margem.text).toString());
    if (mounted) mostrarOk(context, 'Configurações salvas');
  }

  Future<String?> _senha(String titulo, {bool confirmarSenha = false}) async {
    final s1 = TextEditingController();
    final s2 = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(titulo),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: s1, obscureText: true, decoration: const InputDecoration(labelText: 'Senha do backup')),
          if (confirmarSenha) TextField(controller: s2, obscureText: true, decoration: const InputDecoration(labelText: 'Repita a senha')),
          if (confirmarSenha)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Guarde esta senha: sem ela não é possível restaurar o backup.', style: TextStyle(fontSize: 12)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (confirmarSenha && s1.text != s2.text) {
                mostrarErro(c, 'As senhas não conferem');
                return;
              }
              Navigator.pop(c, s1.text);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _backup() async {
    final senha = await _senha('Fazer backup', confirmarSenha: true);
    if (senha == null || !mounted) return;
    await executar(context, () async {
      final bytes = await BackupService.gerar(app: AppDb.instance, senha: senha);
      final nome = 'backup_gestor_servicos_${hojeIso()}.gsvbak';
      final caminho = await salvarArquivo(titulo: 'Salvar backup', nome: nome, bytes: bytes);
      if (caminho == null) throw RegraException('Backup não salvo (operação cancelada).');
      await Base.auditar(banco, 'backup', detalhes: nome);
    }, sucesso: 'Backup salvo');
  }

  Future<void> _restaurar() async {
    final Uint8List? bytes = await escolherArquivo();
    if (bytes == null || !mounted) return;
    final senha = await _senha('Restaurar backup');
    if (senha == null || !mounted) return;
    Map<String, List<int>> arquivos;
    try {
      arquivos = await BackupService.abrir(bytes, senha);
    } catch (e) {
      if (mounted) mostrarErro(context, e);
      return;
    }
    final temDados = (await banco.rawQuery('SELECT COUNT(*) c FROM itens')).first['c'] as int > 0 ||
        (await banco.rawQuery('SELECT COUNT(*) c FROM pedidos')).first['c'] as int > 0;
    if (!mounted) return;
    if (temDados &&
        !await confirmar(context, 'Substituir dados?',
            'A restauração substituirá TODA a base atual deste aparelho pelos dados do backup. Deseja continuar?', ok: 'Restaurar')) {
      return;
    }
    try {
      await BackupService.restaurar(atual: AppDb.instance, arquivos: arquivos);
      PaintingBinding.instance.imageCache.clear();
      if (mounted) mostrarOk(context, 'Backup restaurado com sucesso');
      GestorApp.reiniciar.value++;
    } catch (e) {
      if (mounted) mostrarErro(context, 'Falha na restauração. A base anterior foi mantida. ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ok) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Secao('Negócio'),
        CampoTexto('Nome do negócio', _nome),
        Row(children: [
          if (_logo != null) Image.file(File(_logo!), height: 56, key: ValueKey(DateTime.now())),
          TextButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: Text(_logo == null ? 'Adicionar logomarca' : 'Trocar logomarca'),
            onPressed: () async {
              final p = await Logo.escolher(context);
              if (p != null) setState(() => _logo = p);
            },
          ),
          if (_logo != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await Logo.remover();
                setState(() => _logo = null);
              },
            ),
        ]),
        const Secao('Regras'),
        CampoNumero('Imposto sobre vendas (% sobre a receita, ex.: MEI/Simples)', _imposto, sufixo: '%'),
        CampoNumero('Alertar validade com quantos dias de antecedência', _alerta, inteiro: true, sufixo: 'dias'),
        CampoNumero('Margem desejada para o preço sugerido', _margem, sufixo: '%'),
        FilledButton(onPressed: _salvar, child: const Text('Salvar configurações')),
        const Secao('Backup e restauração'),
        const Text('O backup inclui todos os dados e a logomarca, protegido por senha. Salve-o onde preferir (Drive, Arquivos, pendrive).'),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _backup, icon: const Icon(Icons.backup_outlined), label: const Text('Fazer backup')),
        OutlinedButton.icon(onPressed: _restaurar, icon: const Icon(Icons.restore), label: const Text('Restaurar backup')),
        const Secao('Dados demonstrativos'),
        OutlinedButton.icon(
          icon: const Icon(Icons.science_outlined),
          label: const Text('Carregar dados de exemplo'),
          onPressed: () async {
            final temItens = ((await banco.rawQuery('SELECT COUNT(*) c FROM itens')).first['c'] as int) > 0;
            if (!context.mounted) return;
            if (temItens) {
              mostrarErro(context, 'Os dados de exemplo só podem ser carregados numa base vazia.');
              return;
            }
            if (!await confirmar(context, 'Dados de exemplo', 'Incluir serviços, clientes, agenda, vendas e despesas de demonstração?')) return;
            if (!context.mounted) return;
            await executar(context, () => DemoService(banco).carregar(), sucesso: 'Dados de exemplo carregados');
          },
        ),
        const SizedBox(height: 24),
        Text('Versão do banco: ${AppDb.versaoEsquema}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}

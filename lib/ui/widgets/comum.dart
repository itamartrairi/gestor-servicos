import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:sqflite/sqflite.dart';

import '../../core/format.dart';
import '../../data/db.dart';
import '../../services/cadastro_service.dart';
import '../../services/compra_service.dart';
import '../../services/dre_service.dart';
import '../../services/estoque_service.dart';
import '../../services/fiado_service.dart';
import '../../services/financeiro_service.dart';
import '../../services/pedido_service.dart';
import '../../services/preco_service.dart';
import '../../services/relatorio_service.dart';
import '../../services/agenda_service.dart';

/// Atalho para o banco atual (muda após restauração de backup).
Database get banco => AppDb.instance.db;

/// Serviços sempre ligados ao banco atual.
class S {
  static CadastroService get cad => CadastroService(banco);
  static CompraService get compras => CompraService(banco);
  static DreService get dre => DreService(banco);
  static EstoqueService get estoque => EstoqueService(banco);
  static FinanceiroService get fin => FinanceiroService(banco);
  static PedidoService get pedidos => PedidoService(banco);
  static FiadoService get fiado => FiadoService(banco);
  static PrecoService get precos => PrecoService(banco);
  static RelatorioService get relatorios => RelatorioService(banco);
  static AgendaService get agenda => AgendaService(banco);
  static double max0(double v) => v < 0 ? 0 : v;
}

void mostrarErro(BuildContext context, Object e) {
  final msg = e is RegraException ? e.mensagem : (e is String ? e : 'Erro: $e');
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700, duration: const Duration(seconds: 5)),
  );
}

void mostrarOk(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Executa uma ação mostrando erro amigável. Devolve true se deu certo.
Future<bool> executar(BuildContext context, Future<void> Function() acao, {String? sucesso}) async {
  try {
    await acao();
    if (sucesso != null && context.mounted) mostrarOk(context, sucesso);
    return true;
  } catch (e) {
    if (context.mounted) mostrarErro(context, e);
    return false;
  }
}

Future<bool> confirmar(BuildContext context, String titulo, String mensagem, {String ok = 'Confirmar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(mensagem),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Voltar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
      ],
    ),
  );
  return r == true;
}

Future<String?> pedirTexto(BuildContext context, String titulo, {String rotulo = 'Motivo', String inicial = ''}) async {
  final ctrl = TextEditingController(text: inicial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: TextField(controller: ctrl, autofocus: true, decoration: InputDecoration(labelText: rotulo)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('OK')),
      ],
    ),
  );
  return r;
}

class CampoTexto extends StatelessWidget {
  const CampoTexto(this.rotulo, this.ctrl, {super.key, this.linhas = 1, this.dica, this.onChanged});
  final String rotulo;
  final TextEditingController ctrl;
  final int linhas;
  final String? dica;
  final ValueChanged<String>? onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: TextField(
          controller: ctrl,
          maxLines: linhas,
          onChanged: onChanged,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: rotulo, hintText: dica, border: const OutlineInputBorder(), isDense: true),
        ),
      );
}

/// Campo numérico com teclado numérico (aceita vírgula).
class CampoNumero extends StatelessWidget {
  const CampoNumero(this.rotulo, this.ctrl, {super.key, this.sufixo, this.prefixo, this.onChanged, this.inteiro = false});
  final String rotulo;
  final TextEditingController ctrl;
  final String? sufixo;
  final String? prefixo;
  final ValueChanged<String>? onChanged;
  final bool inteiro;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: TextField(
          controller: ctrl,
          onChanged: onChanged,
          keyboardType: TextInputType.numberWithOptions(decimal: !inteiro),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(inteiro ? r'[0-9]' : r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: rotulo,
            suffixText: sufixo,
            prefixText: prefixo,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
}

String fmtCampo(num? v) {
  if (v == null || v == 0) return '';
  var s = v.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  return s.replaceAll('.', ',');
}

/// Seletor de data (DD/MM/AAAA), valor em ISO.
class CampoData extends StatelessWidget {
  const CampoData(this.rotulo, this.valor, this.onChanged, {super.key, this.permiteVazio = false});
  final String rotulo;
  final String? valor;
  final ValueChanged<String?> onChanged;
  final bool permiteVazio;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: InkWell(
          onTap: () async {
            final ini = valor != null && valor!.isNotEmpty ? DateTime.parse(valor!) : DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: ini,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              locale: const Locale('pt', 'BR'),
            );
            if (d != null) onChanged(isoData(d));
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: rotulo,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: permiteVazio && valor != null
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () => onChanged(null))
                  : const Icon(Icons.calendar_today, size: 18),
            ),
            child: Text(valor == null || valor!.isEmpty ? '—' : dataBr(valor)),
          ),
        ),
      );
}

class CampoLista<T> extends StatelessWidget {
  const CampoLista(this.rotulo, this.valor, this.opcoes, this.onChanged, {super.key});
  final String rotulo;
  final T? valor;
  final Map<T, String> opcoes;
  final ValueChanged<T?> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: DropdownButtonFormField<T>(
          value: opcoes.containsKey(valor) ? valor : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: rotulo, border: const OutlineInputBorder(), isDense: true),
          items: [for (final e in opcoes.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: onChanged,
        ),
      );
}

class Secao extends StatelessWidget {
  const Secao(this.titulo, {super.key, this.acao});
  final String titulo;
  final Widget? acao;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
        child: Row(children: [
          Expanded(
            child: Text(titulo,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
          ),
          if (acao != null) acao!,
        ]),
      );
}

class LinhaValor extends StatelessWidget {
  const LinhaValor(this.rotulo, this.valor, {super.key, this.negrito = false, this.cor});
  final String rotulo;
  final String valor;
  final bool negrito;
  final Color? cor;
  @override
  Widget build(BuildContext context) {
    final st = TextStyle(fontWeight: negrito ? FontWeight.bold : FontWeight.normal, color: cor);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(rotulo, style: st)), Text(valor, style: st)]),
    );
  }
}

/// FutureBuilder com recarga simples.
class Carregar<T> extends StatefulWidget {
  const Carregar({super.key, required this.futuro, required this.builder});
  final Future<T> Function() futuro;
  final Widget Function(BuildContext, T, VoidCallback recarregar) builder;
  @override
  State<Carregar<T>> createState() => _CarregarState<T>();
}

class _CarregarState<T> extends State<Carregar<T>> {
  late Future<T> _f;
  @override
  void initState() {
    super.initState();
    _f = widget.futuro();
  }

  @override
  void didUpdateWidget(covariant Carregar<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _f = widget.futuro();
  }

  void _recarregar() => setState(() => _f = widget.futuro());

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _f,
        builder: (c, s) {
          if (s.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Erro: ${s.error}')));
          }
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          return widget.builder(c, s.data as T, _recarregar);
        },
      );
}

class Vazio extends StatelessWidget {
  const Vazio(this.texto, {super.key});
  final String texto;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(texto, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
        ),
      );
}

class Etiqueta extends StatelessWidget {
  const Etiqueta(this.texto, {super.key, this.cor});
  final String texto;
  final Color? cor;
  @override
  Widget build(BuildContext context) {
    final c = cor ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
      child: Text(texto, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

Future<T?> abrir<T>(BuildContext context, Widget tela) =>
    Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => tela));

/// Pergunta antes de excluir. [oQue] ex.: 'o pedido #12'.
Future<bool> confirmarExclusao(BuildContext context, String oQue, {String? detalhe}) =>
    confirmar(context, 'Excluir', 'Excluir $oQue?${detalhe != null ? '\n\n$detalhe' : ''}\n\nEsta ação não pode ser desfeita.',
        ok: 'Excluir');

/// Menu com as ações Editar e Excluir (usado ao tocar e segurar um item de lista).
Future<String?> menuEditarExcluir(BuildContext context, {bool podeEditar = true, bool podeExcluir = true}) =>
    showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (podeEditar)
            ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Editar'), onTap: () => Navigator.pop(c, 'editar')),
          if (podeExcluir)
            ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Excluir', style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(c, 'excluir')),
        ]),
      ),
    );

/// Botões Editar e Excluir lado a lado, para o final de um item de lista.
class BotoesEditarExcluir extends StatelessWidget {
  const BotoesEditarExcluir({super.key, this.onEditar, this.onExcluir});
  final VoidCallback? onEditar;
  final VoidCallback? onExcluir;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (onEditar != null) IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar', onPressed: onEditar),
        if (onExcluir != null)
          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), tooltip: 'Excluir', onPressed: onExcluir),
      ]);
}

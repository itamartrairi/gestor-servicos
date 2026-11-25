import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../../services/dre_service.dart';
import '../widgets/comum.dart';

/// DRE gerencial por competência, com comparação ao mês anterior.
class DreScreen extends StatefulWidget {
  const DreScreen({super.key});
  @override
  State<DreScreen> createState() => _DreScreenState();
}

class _DreScreenState extends State<DreScreen> {
  DateTime _mes = inicioMes(DateTime.now());

  DateTime get _anterior => DateTime(_mes.year, _mes.month - 1, 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DRE gerencial')),
      body: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _mes = _anterior)),
          Text(nomeMes(_mes), style: Theme.of(context).textTheme.titleMedium),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _mes = DateTime(_mes.year, _mes.month + 1, 1))),
        ]),
        Expanded(
          child: Carregar<(Dre, Dre)>(
            key: ValueKey(_mes),
            futuro: () async => (
              await S.dre.calcular(isoData(_mes), isoData(fimMes(_mes))),
              await S.dre.calcular(isoData(_anterior), isoData(fimMes(_anterior))),
            ),
            builder: (context, d, rec) {
              final atual = d.$1.linhas();
              final ant = d.$2.linhas();
              return ListView(padding: const EdgeInsets.all(8), children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    const Expanded(child: Text('Linha', style: TextStyle(fontWeight: FontWeight.bold))),
                    SizedBox(width: 92, child: Text(mesAno(_mes), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
                    SizedBox(width: 92, child: Text(mesAno(_anterior), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.bold))),
                  ]),
                ),
                const Divider(),
                for (var i = 0; i < atual.length; i++)
                  InkWell(
                    onTap: atual[i].$3.isEmpty
                        ? null
                        : () => abrir(context, _Lancamentos(titulo: atual[i].$1, inicio: isoData(_mes), fim: isoData(fimMes(_mes)), grupos: atual[i].$3)),
                    child: Container(
                      color: atual[i].$4 ? Theme.of(context).colorScheme.primary.withOpacity(0.06) : null,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                      child: Row(children: [
                        Expanded(
                          child: Text(atual[i].$1, style: TextStyle(fontWeight: atual[i].$4 ? FontWeight.bold : FontWeight.normal)),
                        ),
                        SizedBox(
                          width: 92,
                          child: Text(brl(atual[i].$2),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontWeight: atual[i].$4 ? FontWeight.bold : FontWeight.normal,
                                  color: atual[i].$2 < 0 && atual[i].$4 ? Colors.red : null)),
                        ),
                        SizedBox(width: 92, child: Text(brl(ant[i].$2), textAlign: TextAlign.right, style: TextStyle(color: Colors.grey.shade700))),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text(
                    'Regime de competência: receita reconhecida na entrega; CPV pelo custo dos lotes vendidos; '
                    'compras de insumos vão para o estoque (não são despesa). Toque numa linha para ver os lançamentos.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _Lancamentos extends StatelessWidget {
  const _Lancamentos({required this.titulo, required this.inicio, required this.fim, required this.grupos});
  final String titulo, inicio, fim;
  final List<String> grupos;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: Carregar<List<Map<String, Object?>>>(
        futuro: () => S.dre.lancamentos(inicio, fim, grupos),
        builder: (context, l, rec) {
          if (l.isEmpty) return const Vazio('Sem lançamentos.');
          final total = l.fold(0.0, (s, x) => s + Base.d(x['valor']));
          return ListView(children: [
            for (final x in l)
              ListTile(
                dense: true,
                title: Text(x['descricao'] as String),
                subtitle: Text(dataBr(x['data'] as String)),
                trailing: Text(brl(Base.d(x['valor']))),
              ),
            Padding(padding: const EdgeInsets.all(16), child: LinhaValor('Total', brl(total), negrito: true)),
          ]);
        },
      ),
    );
  }
}

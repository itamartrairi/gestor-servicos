import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../services/base.dart';
import '../widgets/comum.dart';
import 'agenda_screen.dart';
import 'dre_screen.dart';
import 'financeiro_screen.dart';
import 'pedido_form_screen.dart';

const corPrimaria = Color(0xFFB4457A);
const corEscura = Color(0xFF8E2F5E);
const corFundo = Color(0xFFFBF3F7);
const corLilas = Color(0xFF8E6BBF);
const corVerde = Color(0xFF2E8B6A);
const corCoral = Color(0xFFE0645C);

/// Tela inicial: painel com os números do dia e do mês, fluxo de caixa dos
/// últimos meses, próximos atendimentos e atalhos.
class InicioScreen extends StatefulWidget {
  const InicioScreen({super.key, required this.irPara});
  final ValueChanged<int> irPara;
  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  int _v = 0;

  Future<Map<String, Object?>> _dados() async {
    final hoje = DateTime.now();
    final ini = isoData(inicioMes(hoje));
    final fim = isoData(fimMes(hoje));
    final dre = await S.dre.calcular(ini, fim);
    final meses = <({String rotulo, double entradas, double saidas})>[];
    for (var k = 5; k >= 0; k--) {
      final m = DateTime(hoje.year, hoje.month - k, 1);
      final f = await S.fin.fluxoRealizado(inicio: isoData(inicioMes(m)), fim: isoData(fimMes(m)));
      meses.add((rotulo: nomeMes(m).substring(0, 3), entradas: f.entradas, saidas: f.saidas));
    }
    final top = await banco.rawQuery('''
      SELECT i.nome, i.tipo, SUM(l.valor) total, SUM(COALESCE(l.quantidade,0)) qtd
      FROM lancamentos_resultado l JOIN itens i ON i.id = l.item_id
      WHERE l.grupo = 'receita_bruta' AND l.data BETWEEN ? AND ?
      GROUP BY l.item_id ORDER BY total DESC LIMIT 5''', [ini, fim]);
    final despesas = r2(dre.cpv + dre.despesasOperacionais + dre.deducoes + S.max0(-dre.resultadoFinanceiro));
    return {
      'negocio': await Base(banco).config('nome_negocio'),
      'mes': nomeMes(hoje),
      'diaResumo': await S.agenda.resumoDia(hojeIso()),
      'faturamento': dre.receitaBruta,
      'despesas': despesas,
      'resultado': dre.resultadoLiquido,
      'margem': dre.receitaLiquida > 0 ? dre.resultadoLiquido / dre.receitaLiquida * 100 : null,
      'caixa': await S.fin.saldo(),
      'receber': await S.fin.totalAberto('receber'),
      'pagar': await S.fin.totalAberto('pagar'),
      'meses': meses,
      'proximos': await S.agenda.proximos(limite: 5),
      'top': top,
    };
  }

  String _saudacao() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Bom dia' : (h < 18 ? 'Boa tarde' : 'Boa noite');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: corFundo,
      body: Carregar<Map<String, Object?>>(
        key: ValueKey(_v),
        futuro: _dados,
        builder: (context, d, rec) {
          final dia = d['diaResumo'] as ({int agendados, int concluidos, double previsto});
          final meses = d['meses'] as List<({String rotulo, double entradas, double saidas})>;
          final proximos = d['proximos'] as List<Map<String, Object?>>;
          final top = d['top'] as List<Map<String, Object?>>;
          final resultado = d['resultado'] as double;
          final margem = d['margem'] as double?;
          return RefreshIndicator(
            onRefresh: () async => setState(() => _v++),
            child: CustomScrollView(slivers: [
              SliverToBoxAdapter(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [corEscura, corPrimaria], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                  ),
                  padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_saudacao()}!', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    Text(((d['negocio'] as String?) ?? '').isEmpty ? 'Meu negócio' : d['negocio'] as String,
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Row(children: [
                      _Pilula(Icons.event_note, '${dia.agendados}', 'a atender hoje'),
                      const SizedBox(width: 8),
                      _Pilula(Icons.check_circle_outline, '${dia.concluidos}', 'concluídos'),
                      const SizedBox(width: 8),
                      _Pilula(Icons.payments_outlined, brl(dia.previsto), 'previsto hoje'),
                    ]),
                  ]),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                sliver: SliverList.list(children: [
                  Row(children: [
                    _Atalho(Icons.add_alarm, 'Agendar', corPrimaria, () async {
                      await abrir(context, const AgendamentoFormScreen());
                      setState(() => _v++);
                    }),
                    _Atalho(Icons.point_of_sale, 'Nova venda', corLilas, () async {
                      await abrir(context, const PedidoFormScreen(tipo: 'balcao'));
                      setState(() => _v++);
                    }),
                    _Atalho(Icons.receipt_long_outlined, 'Despesa', corCoral, () async {
                      await abrir(context, const FinanceiroScreen());
                      setState(() => _v++);
                    }),
                    _Atalho(Icons.analytics_outlined, 'DRE', corVerde, () => abrir(context, const DreScreen())),
                  ]),
                  const SizedBox(height: 14),
                  _Titulo('Resultado de ${d['mes']}'),
                  Row(children: [
                    Expanded(child: _Kpi('Faturamento', brl(d['faturamento'] as double), Icons.trending_up, corVerde)),
                    const SizedBox(width: 10),
                    Expanded(child: _Kpi('Custos e despesas', brl(d['despesas'] as double), Icons.trending_down, corCoral)),
                  ]),
                  const SizedBox(height: 10),
                  _Bloco(
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: (resultado < 0 ? corCoral : corVerde).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(resultado < 0 ? Icons.sentiment_dissatisfied : Icons.savings_outlined,
                            color: resultado < 0 ? corCoral : corVerde),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Lucro do mês (DRE)', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          Text(brl(resultado),
                              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: resultado < 0 ? corCoral : corVerde)),
                        ]),
                      ),
                      if (margem != null)
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          const Text('Margem', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          Text(pct(margem), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                    ]),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _Kpi('Em caixa', brl(d['caixa'] as double), Icons.account_balance_wallet_outlined, corPrimaria)),
                    const SizedBox(width: 10),
                    Expanded(child: _Kpi('A receber', brl(d['receber'] as double), Icons.call_received, corLilas)),
                    const SizedBox(width: 10),
                    Expanded(child: _Kpi('A pagar', brl(d['pagar'] as double), Icons.call_made, corCoral)),
                  ]),
                  const SizedBox(height: 14),
                  _Titulo('Fluxo de caixa • últimos 6 meses',
                      acao: TextButton(onPressed: () => abrir(context, const FinanceiroScreen()), child: const Text('Detalhes'))),
                  _Bloco(child: _GraficoFluxo(meses)),
                  const SizedBox(height: 14),
                  _Titulo('Próximos atendimentos', acao: TextButton(onPressed: () => widget.irPara(1), child: const Text('Ver agenda'))),
                  if (proximos.isEmpty)
                    const _Bloco(child: Text('Nenhum atendimento marcado. Toque em Agendar.', style: TextStyle(color: Colors.black54))),
                  for (final a in proximos)
                    CartaoAtendimento(
                      a: a,
                      mostrarData: true,
                      onTap: () async {
                        await acoesAtendimento(context, a);
                        setState(() => _v++);
                      },
                    ),
                  if (top.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _Titulo('Mais vendidos em ${d['mes']}'),
                    _Bloco(
                      child: Column(children: [
                        for (final t in top)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(children: [
                              Icon(t['tipo'] == 'servico' ? Icons.spa_outlined : Icons.shopping_bag_outlined, size: 18, color: corPrimaria),
                              const SizedBox(width: 8),
                              Expanded(child: Text('${t['nome']}', overflow: TextOverflow.ellipsis)),
                              Text('${numero(Base.d(t['qtd']))}×  ', style: const TextStyle(color: Colors.black54)),
                              Text(brl(Base.d(t['total'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                            ]),
                          ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Pilula extends StatelessWidget {
  const _Pilula(this.icone, this.valor, this.rotulo);
  final IconData icone;
  final String valor, rotulo;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icone, color: Colors.white, size: 18),
            const SizedBox(height: 4),
            FittedBox(child: Text(valor, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            Text(rotulo, style: const TextStyle(color: Colors.white70, fontSize: 11), overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}

class _Atalho extends StatelessWidget {
  const _Atalho(this.icone, this.rotulo, this.cor, this.onTap);
  final IconData icone;
  final String rotulo;
  final Color cor;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(color: cor.withOpacity(0.13), borderRadius: BorderRadius.circular(16)),
                child: Icon(icone, color: cor),
              ),
              const SizedBox(height: 6),
              Text(rotulo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto, {this.acao});
  final String texto;
  final Widget? acao;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
        child: Row(children: [
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: corEscura))),
          if (acao != null) acao!,
        ]),
      );
}

class _Bloco extends StatelessWidget {
  const _Bloco({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: corEscura.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: child,
      );
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.titulo, this.valor, this.icone, this.cor);
  final String titulo, valor;
  final IconData icone;
  final Color cor;
  @override
  Widget build(BuildContext context) => _Bloco(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icone, size: 16, color: cor),
            const SizedBox(width: 4),
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 12, color: Colors.black54), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          FittedBox(child: Text(valor, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
        ]),
      );
}

/// Barras de entradas x saídas por mês (sem bibliotecas externas).
class _GraficoFluxo extends StatelessWidget {
  const _GraficoFluxo(this.meses);
  final List<({String rotulo, double entradas, double saidas})> meses;
  @override
  Widget build(BuildContext context) {
    final maior = meses.fold<double>(1, (m, x) => [m, x.entradas, x.saidas].reduce((a, b) => a > b ? a : b));
    return Column(children: [
      SizedBox(
        height: 140,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final m in meses)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  _Barra(m.entradas / maior, corVerde),
                  const SizedBox(width: 3),
                  _Barra(m.saidas / maior, corCoral),
                ]),
                const SizedBox(height: 4),
                Text(m.rotulo, style: const TextStyle(fontSize: 11, color: Colors.black54)),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _Legenda(corVerde, 'Entradas'),
        SizedBox(width: 16),
        _Legenda(corCoral, 'Saídas'),
      ]),
      const SizedBox(height: 4),
      Text('Saldo do mês atual: ${brl(meses.last.entradas - meses.last.saidas)}',
          style: TextStyle(fontSize: 12, color: (meses.last.entradas - meses.last.saidas) < 0 ? corCoral : corVerde)),
    ]);
  }
}

class _Barra extends StatelessWidget {
  const _Barra(this.fracao, this.cor);
  final double fracao;
  final Color cor;
  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 4 + 104 * (fracao.isNaN ? 0 : fracao.clamp(0, 1)),
        decoration: BoxDecoration(color: cor, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
      );
}

class _Legenda extends StatelessWidget {
  const _Legenda(this.cor, this.texto);
  final Color cor;
  final String texto;
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 4),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ]);
}

import 'package:flutter/material.dart';

import 'agenda_screen.dart';
import 'financeiro_screen.dart';
import 'inicio_screen.dart';
import 'mais_screen.dart';
import 'pedidos_screen.dart';

/// Navegação inferior: Início (painel), Agenda, Vendas, Financeiro e Mais.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _aba = 0;
  int _versao = 0;

  void _selecionarAba(int indice) => setState(() {
        _aba = indice;
        _versao++;
      });

  @override
  Widget build(BuildContext context) {
    final telas = [
      InicioScreen(key: ValueKey('inicio$_versao'), irPara: _selecionarAba),
      AgendaScreen(key: ValueKey('agenda$_versao')),
      PedidosScreen(key: ValueKey('vendas$_versao')),
      FinanceiroScreen(key: ValueKey('fin$_versao')),
      const MaisScreen(),
    ];
    return Scaffold(
      body: telas[_aba],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _aba,
        onDestinationSelected: _selecionarAba,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Agenda'),
          NavigationDestination(icon: Icon(Icons.shopping_bag_outlined), selectedIcon: Icon(Icons.shopping_bag), label: 'Vendas'),
          NavigationDestination(
              icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet), label: 'Financeiro'),
          NavigationDestination(icon: Icon(Icons.menu), label: 'Mais'),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../widgets/comum.dart';
import '../widgets/rodape.dart';
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
        const RodapeIG(),
      ]),
    );
  }
}

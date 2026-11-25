import 'package:sqflite/sqflite.dart';

import '../core/format.dart';
import 'agenda_service.dart';
import 'cadastro_service.dart';
import 'compra_service.dart';
import 'financeiro_service.dart';
import 'pedido_service.dart';

/// Dados demonstrativos de um negócio de serviços (carregados na primeira
/// configuração ou em Configurações > Carregar dados de exemplo).
class DemoService {
  DemoService(this.db);
  final Database db;

  Future<int> _categoria(String nome) async =>
      (await db.query('categorias', where: 'nome = ?', whereArgs: [nome])).first['id'] as int;

  Future<int> _catFin(String codigo) async =>
      (await db.query('categorias_financeiras', where: 'codigo = ?', whereArgs: [codigo])).first['id'] as int;

  Future<void> carregar() async {
    final cad = CadastroService(db);
    final hoje = DateTime.now();
    final h = isoData(hoje);
    final fin = FinanceiroService(db);

    final catSocios = await _catFin('SOCIOS');
    await db.transaction((txn) async {
      await fin.criarMovimento(txn,
          data: h, contaId: 1, tipo: 'entrada', valor: 200, categoriaId: catSocios, descricao: 'Saldo inicial (exemplo)');
      await fin.criarMovimento(txn,
          data: h, contaId: 2, tipo: 'entrada', valor: 1000, categoriaId: catSocios, descricao: 'Saldo inicial (exemplo)');
    });

    Future<(int, int)> servico(String nome, String categoria, double preco, int duracao, double material) async {
      final id = await cad.salvarItem({
        'tipo': 'servico',
        'nome': nome,
        'categoria_id': await _categoria(categoria),
        'unidade_consumo': 'atendimento',
        'unidade_venda': 'atendimento',
        'variavel_pct_cpv': 100,
        'duracao_min': duracao,
        'custo_medio': material,
      });
      final v = (await cad.variacoes(id)).first['id'] as int;
      await db.update('variacoes', {'preco_venda': preco, 'unidade_venda': 'atendimento'}, where: 'id = ?', whereArgs: [v]);
      return (id, v);
    }

    final (corte, vCorte) = await servico('Corte feminino', 'Cabelo', 70, 60, 3);
    final (escova, vEscova) = await servico('Escova', 'Cabelo', 50, 45, 4);
    final (manicure, vManicure) = await servico('Manicure', 'Unhas', 30, 45, 4);
    final (pedicure, vPedicure) = await servico('Pedicure', 'Unhas', 35, 50, 4);
    final (sobrancelha, vSobrancelha) = await servico('Design de sobrancelha', 'Sobrancelhas e cílios', 40, 30, 2);
    final (barra, vBarra) = await servico('Ajuste de barra', 'Costura e ajustes', 25, 30, 1);
    await servico('Decoração de mesa de festa', 'Decoração e festas', 350, 240, 90);
    // Opções de preço no corte.
    await db.update('variacoes', {'nome': 'Cabelo curto'}, where: 'id = ?', whereArgs: [vCorte]);
    await cad.salvarVariacao({'item_id': corte, 'nome': 'Cabelo longo', 'unidade_venda': 'atendimento', 'preco_venda': 90});

    // Produto com estoque (doces para venda).
    final bolo = await cad.salvarItem({
      'tipo': 'acabado',
      'nome': 'Bolo no pote',
      'categoria_id': await _categoria('Comidas e doces'),
      'unidade_consumo': 'un',
      'unidade_venda': 'un',
      'variavel_pct_cpv': 100,
    });
    final vBolo = (await cad.variacoes(bolo)).first['id'] as int;
    await db.update('variacoes', {'preco_venda': 12, 'estoque_minimo': 5}, where: 'id = ?', whereArgs: [vBolo]);
    final forn = await cad.salvarSimples('fornecedores', {'nome': 'Doceria parceira (exemplo)', 'telefone': '(85) 3000-0001'});
    final compras = CompraService(db);
    final c = await compras.salvar(
      fornecedorId: forn,
      data: h,
      condicao: 'avista',
      contaId: 2,
      itens: [ItemCompra(itemId: bolo, variacaoId: vBolo, quantidade: 12, custoTotal: 60, validade: isoData(hoje.add(const Duration(days: 5))))],
    );
    await compras.confirmar(c);

    // Clientes.
    Future<int> cliente(String nome, String tel, {double limite = 0}) =>
        db.insert('clientes', {'nome': nome, 'telefone': tel, 'limite_credito': limite, 'criado_em': agoraIso()});
    final ana = await cliente('Ana Beatriz', '(85) 99999-2001', limite: 300);
    final carla = await cliente('Carla Souza', '(85) 99999-2002');
    final juliana = await cliente('Juliana Lima', '(85) 99999-2003', limite: 200);
    final marcia = await cliente('Márcia Alves', '(85) 99999-2004');

    // Agenda: atendimentos de hoje e dos próximos dias.
    final agenda = AgendaService(db);
    final amanha = isoData(hoje.add(const Duration(days: 1)));
    final a1 = await agenda.salvar(
        clienteId: ana, itemId: manicure, variacaoId: vManicure, data: h, hora: '09:00', duracao: 45, valor: 30, profissional: 'Bia');
    final a2 = await agenda.salvar(
        clienteId: carla, itemId: escova, variacaoId: vEscova, data: h, hora: '10:00', duracao: 45, valor: 50, profissional: 'Lu');
    await agenda.salvar(
        clienteId: juliana, itemId: sobrancelha, variacaoId: vSobrancelha, data: h, hora: '15:00', duracao: 30, valor: 40);
    await agenda.salvar(
        clienteId: marcia, itemId: pedicure, variacaoId: vPedicure, data: h, hora: '16:30', duracao: 50, valor: 35, profissional: 'Bia');
    await agenda.salvar(clienteId: ana, itemId: corte, variacaoId: vCorte, data: amanha, hora: '14:00', duracao: 60, valor: 70);
    await agenda.salvar(clienteId: carla, itemId: barra, variacaoId: vBarra, data: amanha, hora: '11:00', duracao: 30, valor: 25);

    // Dois atendimentos já concluídos: um no Pix e outro no fiado.
    await agenda.concluir(id: a1, pagamentos: [PagamentoInfo(meioId: 2, valor: 30)]);
    await agenda.concluir(id: a2, pagamentos: const [], vencimentoSaldo: isoData(hoje.add(const Duration(days: 7))));

    // Venda rápida de doces.
    final ped = PedidoService(db);
    await ped.vendaBalcao(
      data: h,
      itens: [ItemPedido(itemId: bolo, variacaoId: vBolo, quantidade: 3, precoUnitario: 12, unidadeVenda: 'un')],
      pagamentos: [PagamentoInfo(meioId: 1, valor: 36)],
    );

    // Encomenda de decoração com sinal.
    final decoracao = (await db.query('itens', where: "nome LIKE 'Decoração%'")).first['id'] as int;
    final vDec = (await cad.variacoes(decoracao)).first['id'] as int;
    final enc = await ped.salvar(
      tipo: 'encomenda',
      clienteId: marcia,
      canal: 'Instagram',
      dataPedido: h,
      dataEntrega: isoData(hoje.add(const Duration(days: 10))),
      horaEntrega: '16:00',
      personalizacao: 'Tema jardim, tons de rosa',
      itens: [ItemPedido(itemId: decoracao, variacaoId: vDec, quantidade: 1, precoUnitario: 350, unidadeVenda: 'atendimento')],
    );
    await ped.confirmar(enc);
    await ped.registrarPagamento(pedidoId: enc, meioId: 2, valor: 150, data: h);

    // Despesas do mês.
    await fin.lancarContaAvulsa(
      tipo: 'pagar',
      descricao: 'Aluguel do espaço',
      categoriaId: await _catFin('ALUGUEL'),
      valor: 800,
      competencia: h,
      primeiroVencimento: isoData(hoje.add(const Duration(days: 8))),
      contaPrevistaId: 2,
    );
    await fin.lancarContaAvulsa(
      tipo: 'pagar',
      descricao: 'Energia e internet',
      categoriaId: await _catFin('UTILIDADES'),
      valor: 220,
      competencia: h,
      primeiroVencimento: isoData(hoje.add(const Duration(days: 12))),
      contaPrevistaId: 2,
    );
  }
}

// Testes do cenário de validação (negócio de serviços) sobre o banco
// SQLite real, usando sqflite_common_ffi. Rode com: flutter test
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestor_servicos/core/format.dart';
import 'package:gestor_servicos/data/db.dart';
import 'package:gestor_servicos/services/backup_service.dart';
import 'package:gestor_servicos/services/base.dart';
import 'package:gestor_servicos/services/cadastro_service.dart';
import 'package:gestor_servicos/services/compra_service.dart';
import 'package:gestor_servicos/services/demo_service.dart';
import 'package:gestor_servicos/services/dre_service.dart';
import 'package:gestor_servicos/services/estoque_service.dart';
import 'package:gestor_servicos/services/fiado_service.dart';
import 'package:gestor_servicos/services/financeiro_service.dart';
import 'package:gestor_servicos/services/pdf_service.dart';
import 'package:gestor_servicos/services/pedido_service.dart';
import 'package:gestor_servicos/services/preco_service.dart';
import 'package:gestor_servicos/services/relatorio_service.dart';
import 'package:gestor_servicos/services/agenda_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late AppDb app;
  late Database db;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('gsv');
    app = await AppDb.abrir(caminho: '${tmp.path}/teste.db', factory: databaseFactoryFfi);
    db = app.db;
  });

  tearDown(() async {
    await app.fechar();
    await tmp.delete(recursive: true);
  });

  test('dados de exemplo incluem serviços, agenda, vendas e fiado', () async {
    await DemoService(db).carregar();
    final itens = await db.query('itens');
    expect(itens.where((i) => i['tipo'] == 'servico'), hasLength(7));
    expect(itens.where((i) => i['tipo'] == 'acabado'), hasLength(1));
    final agenda = await db.query('agendamentos');
    expect(agenda, hasLength(6));
    expect(agenda.where((a) => a['status'] == 'concluido'), hasLength(2));
    expect(await FiadoService(db).devedores(), hasLength(1)); // Carla
    final ini = isoData(inicioMes(DateTime.now()));
    final fim = isoData(fimMes(DateTime.now()));
    final dre = await DreService(db).calcular(ini, fim);
    expect(dre.receitaBruta, 116.0); // 30 + 50 + 36
    expect(dre.cpv, 23.0); // material 4 + 4 + bolos 3 × 5
  });

  test('preço sugerido e bloqueio de percentuais >= 100%', () {
    final p = PrecoService.precoSugerido(custoUnitario: 60, pctTaxas: 5, pctImpostos: 5, pctFixas: 10, pctMargem: 20);
    expect(p.preco, 100.0); // 60 / (1 - 0,40)
    final e = PrecoService.precoSugerido(custoUnitario: 30, pctTaxas: 50, pctImpostos: 50, pctFixas: 0, pctMargem: 0);
    expect(e.preco, isNull);
    expect(e.erro, isNotNull);
    expect(PrecoService.custoComDesconto(100, 30), 70.0);
  });

  test('cenário completo: compra, tabela de preço, reserva automática, entrega no fiado e relatórios', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    final daqui30 = isoData(DateTime.now().add(const Duration(days: 30)));

    // Saldo inicial na conta bancária para pagar a marca depois.
    await db.update('contas_financeiras', {'saldo_inicial': 300, 'data_saldo_inicial': '2000-01-01'}, where: 'id = 2');

    final marca = await cad.salvarSimples('fornecedores', {'nome': 'Marca X', 'desconto_padrao_pct': 30});
    final perfume = await cad.salvarItem(
        {'tipo': 'acabado', 'nome': 'Perfume', 'codigo': '1001', 'fornecedor_id': marca, 'unidade_venda': 'un', 'variavel_pct_cpv': 100});
    final vPerfume = (await cad.variacoes(perfume)).first['id'] as int;
    await db.update('variacoes', {'preco_venda': 100}, where: 'id = ?', whereArgs: [vPerfume]);

    // 1. Compra de 2 perfumes a prazo (catálogo R\$ 100 − 30% = R\$ 70 cada).
    final compras = CompraService(db);
    final cid = await compras.salvar(
      fornecedorId: marca, data: hoje, condicao: 'prazo', parcelas: 1, primeiroVencimento: daqui30, contaId: 2,
      itens: [ItemCompra(itemId: perfume, variacaoId: vPerfume, quantidade: 2, custoTotal: 140)],
    );
    await compras.confirmar(cid);
    await expectLater(compras.confirmar(cid), throwsA(isA<RegraException>())); // duplicada bloqueada
    final est = EstoqueService(db);
    expect((await est.saldo(perfume, vPerfume)).fisico, 2);
    final lote1 = (await db.query('lotes', where: 'item_id = ?', whereArgs: [perfume])).single;
    expect(Base.d(lote1['custo_unitario']), 70.0);
    expect(Base.d((await Base.item(db, perfume))['custo_medio']), 70.0);
    final fin = FinanceiroService(db);
    final aPagar = await fin.titulosAbertos(tipo: 'pagar');
    expect(aPagar.length, 1);
    expect(Base.d(aPagar.first['aberto']), 140);
    expect(await fin.saldo(), 300); // compra a prazo não sai do caixa

    // 2. Tabelas de preço: ajuste sobre o catálogo e preço manual.
    final precos = PrecoService(db);
    final atacado = (await db.query('tabelas_preco', where: "nome LIKE 'Atacado%'")).first['id'] as int;
    expect(await precos.precoPara(vPerfume, atacado), 85.0); // −15%
    await precos.definirPreco(atacado, vPerfume, 90);
    expect(await precos.precoPara(vPerfume, atacado), 90.0);
    await precos.definirPreco(atacado, vPerfume, null);
    expect(await precos.precoPara(vPerfume, atacado), 85.0);
    expect(await precos.precoPara(vPerfume, await precos.tabelaPadrao()), 100.0);

    // 3. Pedido de cliente maior que o estoque.
    final cliente = await db.insert('clientes', {'nome': 'Cliente', 'criado_em': agoraIso()});
    final ped = PedidoService(db);
    final pid = await ped.salvar(
      tipo: 'encomenda', clienteId: cliente, canal: 'WhatsApp', dataPedido: hoje, dataEntrega: hoje,
      itens: [ItemPedido(itemId: perfume, variacaoId: vPerfume, quantidade: 3, precoUnitario: 100, unidadeVenda: 'un')],
    );
    await ped.confirmar(pid);
    expect((await est.saldo(perfume, vPerfume)).reservado, 2);
    expect((await db.query('pedidos', where: 'id = ?', whereArgs: [pid])).first['status'], 'confirmado');

    // 4. Compra do que falta (1 unidade).
    final compraMarca = await compras.salvar(
      fornecedorId: marca, data: hoje, condicao: 'prazo', parcelas: 1, primeiroVencimento: daqui30, contaId: 2,
      itens: [ItemCompra(itemId: perfume, variacaoId: vPerfume, quantidade: 1, custoTotal: 70)],
    );

    // 5. Mercadoria chegou: entrada e reserva automática; pedido fica pronto.
    await compras.confirmar(compraMarca);
    expect((await est.saldo(perfume, vPerfume)).fisico, 3);
    expect((await est.saldo(perfume, vPerfume)).reservado, 3);
    expect((await db.query('pedidos', where: 'id = ?', whereArgs: [pid])).first['status'], 'pronto');

    // 6. Sinal e entrega no fiado em 2 parcelas.
    await ped.registrarPagamento(pedidoId: pid, meioId: 1, valor: 50, data: hoje); // dinheiro → conta 1
    expect(await fin.saldoConta(1), 50);
    await ped.entregar(pedidoId: pid, data: hoje, parcelas: 2, intervaloDias: 30, vencimentoSaldo: daqui30);
    await expectLater(ped.entregar(pedidoId: pid, data: hoje), throwsA(isA<RegraException>()));
    expect((await est.saldo(perfume, vPerfume)).fisico, 0);
    expect((await est.saldo(perfume, vPerfume)).reservado, 0);
    final parcelas = await db.query('titulos',
        where: "tipo = 'receber' AND ref_tipo = 'pedido' AND ref_id = ?", whereArgs: [pid], orderBy: 'vencimento');
    expect(parcelas, hasLength(2));
    expect(parcelas.map((t) => Base.d(t['valor'])).toList(), [125.0, 125.0]);
    expect(parcelas.first['vencimento'], daqui30);
    final fiado = FiadoService(db);
    expect(await fiado.saldoDevedor(cliente), 250);
    final ini = isoData(inicioMes(DateTime.now()));
    final fim = isoData(fimMes(DateTime.now()));
    final dre = await DreService(db).calcular(ini, fim);
    expect(dre.receitaBruta, 300);
    expect(dre.cpv, 210);
    expect(dre.lucroBruto, 90);

    // 7. Recebimento do fiado quita a parcela mais antiga primeiro.
    await fiado.receberDoCliente(clienteId: cliente, valor: 150, meioId: 1, data: hoje);
    expect(await fiado.saldoDevedor(cliente), 100);
    final apos = await db.query('titulos',
        where: "tipo = 'receber' AND ref_tipo = 'pedido' AND ref_id = ?", whereArgs: [pid], orderBy: 'vencimento');
    expect(apos.first['status'], 'quitado');
    expect(apos.last['status'], 'parcial');
    expect(await fin.saldoConta(1), 200);
    await expectLater(fiado.receberDoCliente(clienteId: cliente, valor: 500, meioId: 1, data: hoje), throwsA(isA<RegraException>()));

    // 8. Pagamento da marca (primeira compra).
    final titulo = aPagar.first;
    await fin.baixarTitulo(tituloId: titulo['id'] as int, data: hoje, contaId: 2, principal: 140);
    final movPag = await db.query('movimentos_financeiros', where: 'titulo_id = ?', whereArgs: [titulo['id']]);
    expect(movPag.single['conta_id'], 2);
    expect(movPag.single['tipo'], 'saida');
    expect(await fin.saldoConta(2), 160);

    // Transferência: efeito zero no consolidado.
    final antes = await fin.saldo();
    await fin.transferir(origemId: 1, destinoId: 2, valor: 10, data: hoje);
    expect(await fin.saldo(), antes);

    // 9. Relatórios: totais batem com o financeiro e com a DRE.
    final fr = await fin.fluxoRealizado(inicio: ini, fim: fim);
    expect(fr.saldoFinal, await fin.saldo(ateData: fim));
    expect(r2(fr.saldoInicial + fr.entradas - fr.saidas), fr.saldoFinal);
    final vc = await RelatorioService(db).vendasCustos(FiltroVendas(inicio: ini, fim: fim));
    expect(vc.receitaLiquida, dre.receitaLiquida);
    expect(vc.cpv, dre.cpv);
    expect(vc.lucroBruto, dre.lucroBruto);
    expect(vc.vendas, 1);
    expect(vc.custosProducao['Total comprado'], 210.0);
    expect(vc.ordens, hasLength(2));
    final fp = await fin.fluxoProjetado(dataRef: hoje, ate: isoData(DateTime.now().add(const Duration(days: 90))));
    expect(fp.aReceber, 100);

    // PDFs são gerados (bytes válidos) sem internet.
    final cab = CabecalhoPdf(negocio: 'Teste', titulo: 'T', periodo: 'x', filtros: const []);
    final pdf1 = await PdfService.fluxoCaixa(cab: cab, realizado: fr, projetado: fp);
    final pdf2 = await PdfService.vendasCustos(cab: cab, v: vc);
    expect(String.fromCharCodes(pdf1.sublist(0, 4)), '%PDF');
    expect(String.fromCharCodes(pdf2.sublist(0, 4)), '%PDF');

    // 10. Backup protegido por senha: senha errada é recusada; a certa preserva os dados.
    final bytes = await BackupService.gerar(app: app, senha: 'segredo');
    await expectLater(BackupService.abrir(bytes, 'errada'), throwsA(isA<RegraException>()));
    final arquivos = await BackupService.abrir(bytes, 'segredo');
    final outro = File('${tmp.path}/restaurado.db');
    await outro.writeAsBytes(arquivos['banco.db']!);
    final app2 = await AppDb.abrir(caminho: outro.path, factory: databaseFactoryFfi);
    expect(await FinanceiroService(app2.db).saldo(), await FinanceiroService(db).saldo());
    expect(await FiadoService(app2.db).saldoDevedor(cliente), 100);
    await app2.fechar();
    AppDb.definirInstancia(app);
  });

  test('fiado: exige cliente, respeita o limite de crédito e aceita entrada + parcelas', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    final batom = await cad.salvarItem({'tipo': 'acabado', 'nome': 'Batom', 'unidade_venda': 'un'});
    final v = (await cad.variacoes(batom)).first['id'] as int;
    await db.transaction((txn) async {
      await EstoqueService(db).entradaProduzido(txn,
          itemId: batom, variacaoId: v, quantidade: 10, custoUnitario: 20, codigoLote: 'B', fabricacao: hoje);
    });
    final ped = PedidoService(db);
    ItemPedido item(double q) => ItemPedido(itemId: batom, variacaoId: v, quantidade: q, precoUnitario: 40);

    // Sem cliente não há fiado (e a venda não fica gravada).
    await expectLater(ped.vendaBalcao(data: hoje, itens: [item(1)], pagamentos: const []), throwsA(isA<RegraException>()));
    expect(await db.query('pedidos'), isEmpty);

    // Limite de R\$ 100: venda de R\$ 120 a prazo é bloqueada, salvo liberação.
    final cli = await db.insert('clientes', {'nome': 'Maria', 'limite_credito': 100, 'criado_em': agoraIso()});
    await expectLater(
      ped.vendaBalcao(clienteId: cli, data: hoje, itens: [item(3)], pagamentos: const []),
      throwsA(isA<RegraException>().having((e) => e.mensagem, 'mensagem', startsWith('Limite de crédito'))),
    );
    // Entrada de R\$ 40 + R\$ 80 em 2x cabe no limite.
    await ped.vendaBalcao(
        clienteId: cli,
        data: hoje,
        itens: [item(3)],
        pagamentos: [PagamentoInfo(meioId: 1, valor: 40)],
        parcelas: 2,
        intervaloDias: 30);
    final fiado = FiadoService(db);
    expect(await fiado.saldoDevedor(cli), 80);
    expect((await fiado.parcelasAbertas(clienteId: cli)).map((t) => Base.d(t['aberto'])).toList(), [40.0, 40.0]);
    expect(await FinanceiroService(db).saldoConta(1), 40);
    // Nova compra de R\$ 40 no fiado estoura o limite (80 + 40 > 100), mas pode ser liberada.
    await expectLater(ped.vendaBalcao(clienteId: cli, data: hoje, itens: [item(1)], pagamentos: const []),
        throwsA(isA<RegraException>()));
    await ped.vendaBalcao(clienteId: cli, data: hoje, itens: [item(1)], pagamentos: const [], ignorarLimite: true);
    expect(await fiado.saldoDevedor(cli), 120);
    expect((await EstoqueService(db).saldo(batom, v)).fisico, 6);
  });

  test('cancelamento libera reserva e devolve sinal; lote vencido é bloqueado', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    final doce = await cad.salvarItem({'tipo': 'acabado', 'nome': 'Hidratante', 'unidade_venda': 'un'});
    final v = (await cad.variacoes(doce)).first['id'] as int;
    final est = EstoqueService(db);
    await db.transaction((txn) async {
      await est.entradaProduzido(txn,
          itemId: doce, variacaoId: v, quantidade: 2, custoUnitario: 40, codigoLote: 'A', fabricacao: hoje,
          validade: isoData(DateTime.now().add(const Duration(days: 2))));
      await est.entradaProduzido(txn,
          itemId: doce, variacaoId: v, quantidade: 5, custoUnitario: 40, codigoLote: 'VENC', fabricacao: '2020-01-01',
          validade: '2020-01-05');
    });
    final s = await est.saldo(doce, v);
    expect(s.fisico, 7);
    expect(s.vencido, 5);
    expect(s.disponivel, 2);

    final ped = PedidoService(db);
    final pid = await ped.salvar(
        tipo: 'encomenda', dataPedido: hoje, itens: [ItemPedido(itemId: doce, variacaoId: v, quantidade: 2, precoUnitario: 120)]);
    await ped.confirmar(pid);
    expect((await est.saldo(doce, v)).disponivel, 0);
    await ped.registrarPagamento(pedidoId: pid, meioId: 1, valor: 100, data: hoje);
    await ped.cancelar(pedidoId: pid, motivo: 'Comprador desistiu', valorDevolvido: 100, contaDevolucaoId: 1);
    expect((await est.saldo(doce, v)).disponivel, 2);
    expect(await FinanceiroService(db).saldoConta(1), 0);

    // Venda de 3 unidades com só 2 válidas: a venda não trava (lote vencido continua bloqueado).
    final pv = await ped.vendaBalcao(
        data: hoje,
        itens: [ItemPedido(itemId: doce, variacaoId: v, quantidade: 3, precoUnitario: 120)],
        pagamentos: [PagamentoInfo(meioId: 1, valor: 360)]);
    expect((await est.saldo(doce, v)).fisico, 5);
    expect(await FinanceiroService(db).saldoConta(1), 360);
    // Excluir a venda desfaz tudo: estoque e caixa voltam.
    await ped.excluir(pv);
    expect((await est.saldo(doce, v)).fisico, 7);
    expect(await FinanceiroService(db).saldoConta(1), 0);
    expect(await db.query('pedidos', where: 'id = ?', whereArgs: [pv]), isEmpty);
  });

  test('cartão: taxa registrada uma vez e conciliação do depósito', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    final bolo = await cad.salvarItem({'tipo': 'acabado', 'nome': 'Perfume', 'unidade_venda': 'un'});
    final v = (await cad.variacoes(bolo)).first['id'] as int;
    await db.transaction((txn) async {
      await EstoqueService(db).entradaProduzido(txn,
          itemId: bolo, variacaoId: v, quantidade: 1, custoUnitario: 30, codigoLote: 'T', fabricacao: hoje);
    });
    // Cartão de crédito: 3,5%, 30 dias, conta 2.
    await PedidoService(db).vendaBalcao(
        data: hoje,
        itens: [ItemPedido(itemId: bolo, variacaoId: v, quantidade: 1, precoUnitario: 100)],
        pagamentos: [PagamentoInfo(meioId: 4, valor: 100)]);
    final fin = FinanceiroService(db);
    final rec = await fin.titulosAbertos(tipo: 'receber');
    expect(rec.single['ref_tipo'], 'cartao');
    expect(Base.d(rec.single['aberto']), 96.5);
    await fin.conciliarCartao(tituloId: rec.single['id'] as int, data: hoje, contaId: 2, valorDepositado: 96.0);
    expect(await fin.saldoConta(2), 96.0);
    final ini = isoData(inicioMes(DateTime.now()));
    final fim = isoData(fimMes(DateTime.now()));
    final dre = await DreService(db).calcular(ini, fim);
    expect(dre.despesasVariaveis, 4.0); // 3,50 previsto + 0,50 de ajuste
    expect(dre.receitaBruta, 100);
    expect(dre.cpv, 30);
  });

  test('excluir: pedido, compra, tabela de preço e cadastros com regras de segurança', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    await db.update('contas_financeiras', {'saldo_inicial': 500, 'data_saldo_inicial': '2000-01-01'}, where: 'id = 2');
    final marca = await cad.salvarSimples('fornecedores', {'nome': 'Marca', 'desconto_padrao_pct': 30});
    final prod = await cad.salvarItem({'tipo': 'acabado', 'nome': 'Creme', 'fornecedor_id': marca, 'unidade_venda': 'un'});
    final v = (await cad.variacoes(prod)).first['id'] as int;
    final compras = CompraService(db);
    final est = EstoqueService(db);
    final fin = FinanceiroService(db);

    // Compra à vista intacta: excluir estorna estoque e pagamento.
    final c1 = await compras.salvar(fornecedorId: marca, data: hoje, condicao: 'avista', contaId: 2,
        itens: [ItemCompra(itemId: prod, variacaoId: v, quantidade: 2, custoTotal: 60)]);
    await compras.confirmar(c1);
    expect(await fin.saldoConta(2), 440);
    await compras.excluir(c1);
    expect((await est.saldo(prod, v)).fisico, 0);
    expect(await fin.saldoConta(2), 500);

    // Compra com itens reservados para um pedido também pode ser excluída.
    final cli = await db.insert('clientes', {'nome': 'Cli', 'criado_em': agoraIso()});
    final ped = PedidoService(db);
    final p1 = await ped.salvar(tipo: 'encomenda', clienteId: cli, dataPedido: hoje,
        itens: [ItemPedido(itemId: prod, variacaoId: v, quantidade: 1, precoUnitario: 50)]);
    await ped.confirmar(p1);
    final c2 = await compras.salvar(fornecedorId: marca, data: hoje, condicao: 'prazo', parcelas: 1, contaId: 2,
        itens: [ItemCompra(itemId: prod, variacaoId: v, quantidade: 1, custoTotal: 30)]);
    await compras.confirmar(c2); // reserva automática para o pedido
    await compras.excluir(c2);
    expect((await est.saldo(prod, v)).fisico, 0);
    expect(await fin.titulosAbertos(tipo: 'pagar'), isEmpty);
    await ped.excluir(p1);
    expect((await est.saldo(prod, v)).reservado, 0);

    // Pedido com sinal também é excluído, e o sinal sai do caixa.
    final caixaAntes = await fin.saldoConta(1);
    final p2 = await ped.salvar(tipo: 'encomenda', clienteId: cli, dataPedido: hoje,
        itens: [ItemPedido(itemId: prod, variacaoId: v, quantidade: 1, precoUnitario: 50)]);
    await ped.registrarPagamento(pedidoId: p2, meioId: 1, valor: 10, data: hoje);
    expect(await fin.saldoConta(1), caixaAntes + 10);
    await ped.excluir(p2);
    expect(await fin.saldoConta(1), caixaAntes);

    // Tabelas de preço: a padrão não sai; outra sem uso sai e libera os clientes.
    final precos = PrecoService(db);
    await expectLater(precos.excluirTabela((await precos.tabelaPadrao())!), throwsA(isA<RegraException>()));
    final promo = (await db.query('tabelas_preco', where: "nome = 'Promoção'")).first['id'] as int;
    await db.update('clientes', {'tabela_id': promo}, where: 'id = ?', whereArgs: [cli]);
    await precos.definirPreco(promo, v, 40);
    await precos.excluirTabela(promo);
    expect((await db.query('clientes', where: 'id = ?', whereArgs: [cli])).first['tabela_id'], isNull);

    // Cadastros: clientes e fornecedores saem mesmo com histórico (o histórico fica sem o nome).
    await cad.excluirSimples('fornecedores', marca);
    await cad.excluirSimples('clientes', cli);
    expect(await db.query('clientes', where: 'id = ?', whereArgs: [cli]), isEmpty);

    final novo = await cad.salvarItem({'tipo': 'acabado', 'nome': 'Sem uso', 'unidade_venda': 'un'});
    final v1 = (await cad.variacoes(novo)).first['id'] as int;
    final v2 = await cad.salvarVariacao({'item_id': novo, 'nome': 'Outra', 'unidade_venda': 'un', 'preco_venda': 10});
    await precos.definirPreco((await precos.tabelaPadrao())!, v2, 9);
    await cad.excluirVariacao(v2);
    await expectLater(cad.excluirVariacao(v1), throwsA(isA<RegraException>())); // única variação
    await cad.excluirItem(novo);
    expect(await db.query('itens', where: 'id = ?', whereArgs: [novo]), isEmpty);
  });

  test('serviços não usam estoque; custo de material entra no CPV', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    final unha = await cad.salvarItem(
        {'tipo': 'servico', 'nome': 'Manicure', 'unidade_venda': 'atendimento', 'custo_medio': 4.5, 'duracao_min': 45});
    final v = (await cad.variacoes(unha)).first['id'] as int;
    final ped = PedidoService(db);
    final cli = await db.insert('clientes', {'nome': 'Cli', 'criado_em': agoraIso()});
    final pid = await ped.salvar(tipo: 'encomenda', clienteId: cli, dataPedido: hoje,
        itens: [ItemPedido(itemId: unha, variacaoId: v, quantidade: 2, precoUnitario: 30)]);
    await ped.confirmar(pid);
    expect((await db.query('pedidos', where: 'id = ?', whereArgs: [pid])).first['status'], 'pronto'); // sem estoque a esperar
    await ped.entregar(pedidoId: pid, data: hoje, pagamentos: [PagamentoInfo(meioId: 1, valor: 60)]);
    expect(await db.query('lotes'), isEmpty);
    final ini = isoData(inicioMes(DateTime.now()));
    final fim = isoData(fimMes(DateTime.now()));
    final dre = await DreService(db).calcular(ini, fim);
    expect(dre.receitaBruta, 60);
    expect(dre.cpv, 9.0);
  });

  test('agenda: conflito de horário, concluir com pagamento/fiado, falta, cancelar e excluir', () async {
    final cad = CadastroService(db);
    final hoje = hojeIso();
    final escova = await cad.salvarItem({'tipo': 'servico', 'nome': 'Escova', 'unidade_venda': 'atendimento', 'custo_medio': 3});
    final v = (await cad.variacoes(escova)).first['id'] as int;
    final ana = await db.insert('clientes', {'nome': 'Ana', 'criado_em': agoraIso()});
    final ag = AgendaService(db);
    final a1 = await ag.salvar(clienteId: ana, itemId: escova, variacaoId: v, data: hoje, hora: '10:00', duracao: 60, valor: 50, profissional: 'Lu');
    expect(await ag.conflitos(data: hoje, hora: '10:30', duracao: 30, profissional: 'Lu'), hasLength(1));
    expect(await ag.conflitos(data: hoje, hora: '10:30', duracao: 30, profissional: 'Bia'), isEmpty);
    expect(await ag.conflitos(data: hoje, hora: '11:00', duracao: 30, profissional: 'Lu'), isEmpty);
    expect(AgendaService.horaFim('10:00', 90), '11:30');
    await expectLater(ag.salvar(itemId: escova, data: hoje, hora: '9h'), throwsA(isA<RegraException>()));

    // Concluir: R\$ 20 no Pix, R\$ 30 no fiado.
    final pid = await ag.concluir(id: a1, pagamentos: [PagamentoInfo(meioId: 2, valor: 20)]);
    expect((await ag.obter(a1))['status'], 'concluido');
    expect((await db.query('pedidos', where: 'id = ?', whereArgs: [pid])).first['status'], 'entregue');
    expect(await FiadoService(db).saldoDevedor(ana), 30);
    await expectLater(ag.concluir(id: a1, pagamentos: const []), throwsA(isA<RegraException>()));
    final r = await ag.resumoDia(hoje);
    expect(r.concluidos, 1);

    // Desfazer a conclusão apaga a venda (Pix e fiado) e volta para agendado.
    await ag.alterarStatus(a1, 'agendado');
    expect((await ag.obter(a1))['status'], 'agendado');
    expect((await ag.obter(a1))['pedido_id'], isNull);
    expect(await FiadoService(db).saldoDevedor(ana), 0);
    expect(await db.query('pedidos', where: 'id = ?', whereArgs: [pid]), isEmpty);

    // Fiado sem cliente não é aceito (e o atendimento continua agendado).
    final a2 = await ag.salvar(itemId: escova, variacaoId: v, data: hoje, hora: '14:00', valor: 50);
    await expectLater(ag.concluir(id: a2, pagamentos: const []), throwsA(isA<RegraException>()));
    expect((await ag.obter(a2))['status'], 'agendado');

    await ag.alterarStatus(a2, 'faltou');
    expect((await ag.obter(a2))['status'], 'faltou');
    await ag.alterarStatus(a2, 'agendado');
    await ag.alterarStatus(a2, 'cancelado');
    await ag.excluir(a2);
    expect(await db.query('agendamentos', where: 'id = ?', whereArgs: [a2]), isEmpty);
    expect(await cad.excluirItem(escova), CadastroService.msgDesativado); // usado na agenda: desativa
  });
}

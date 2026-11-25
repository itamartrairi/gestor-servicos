# Gestor de Serviços

Aplicativo para **Android e iPhone** (Flutter) para quem vive de serviços e vendas sob encomenda: **salão e cabeleireira, manicure e pedicure, designer de sobrancelhas e cílios, estética, decoração de festas, costura e ajustes, comidas e doces**.

- **Sem login e sem código de ativação**: abriu, usou.
- 100% **offline**: dados em SQLite no próprio celular, com backup protegido por senha.
- Visual em tons de rosa e lilás, pensado para negócios femininos; Português do Brasil, R$ e datas DD/MM/AAAA.

## Telas

| Aba | O que tem |
|---|---|
| **Início (painel)** | Atendimentos de hoje, previsto do dia, faturamento, custos e despesas, lucro e margem do mês (DRE), saldo em caixa, a receber e a pagar, gráfico de **fluxo de caixa dos últimos 6 meses**, próximos atendimentos e mais vendidos. Atalhos: Agendar, Nova venda, Despesa e DRE. |
| **Agenda** | Semana com marcação dos dias ocupados, atendimentos do dia com horário de início e fim, profissional e valor. Aviso de **conflito de horário**. Ações: concluir e receber (Pix, dinheiro, cartão, misto ou **fiado parcelado**), remarcar, cliente faltou, cancelar, excluir. |
| **Vendas** | Venda rápida de serviço ou produto e encomendas com sinal (bolos, costura, decoração), entrega, estornos, PDF do pedido. |
| **Financeiro** | Contas, a receber, a pagar, **fluxo de caixa** e movimentos; despesas fixas e variáveis, parcelas, transferências, cartão com repasse. |
| **Mais** | DRE, relatórios em PDF (Fluxo de Caixa e Vendas e Custos), fiado, estoque, compras, tabelas de preço, cadastros e configurações. |

## Regras principais

- **Serviços** têm preço, duração padrão e **custo de material** por atendimento (esmalte, descartáveis, linha…); não usam estoque, e o custo de material entra no CPV da DRE.
- **Produtos** (doces, cosméticos para revenda) têm estoque com lotes, validade e custo de compra.
- Concluir um atendimento gera a venda automaticamente; o que não for pago na hora fica no **fiado** da cliente, com limite de crédito opcional.
- DRE por competência: receita na conclusão/entrega, CPV, despesas variáveis e fixas, resultado e margem.

## Gerar o app

```bash
git clone https://github.com/itamartrairi/gestor-servicos.git
cd gestor-servicos
bash tool/preparar_plataformas.sh   # cria android/ e ios/, ícone e permissões
flutter test
flutter build apk --release         # Android
flutter build ipa --release         # iPhone (Mac + conta Apple Developer)
```

A cada envio para `main`, o GitHub Actions roda os testes, gera o APK (artefato `gestor-servicos-apk`) e compila o iOS sem assinatura.

## Dados de exemplo

Na primeira abertura são carregados serviços (corte, escova, manicure, pedicure, sobrancelha, ajuste de barra, decoração), um produto (bolo no pote), clientes, atendimentos de hoje e amanhã, uma encomenda com sinal e despesas do mês. Para começar do zero, exclua-os ou faça uma restauração vazia.

Fontes dos PDFs: Noto Sans (SIL Open Font License).

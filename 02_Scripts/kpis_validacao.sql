# Validação dos SQLs e do dashboard

## Como foi feito

1. **Teste de execução:** os 8 scripts (`01` a `08`) foram rodados **do zero e em ordem** num PostgreSQL 16 com dados sintéticos no formato do Olist. Todos executaram sem erro, inclusive a substituição de views (`CREATE OR REPLACE`).
2. **Auditoria da lógica:** cada query foi comparada com a regra de negócio e com o visual correspondente do dashboard.

> **Limite do teste:** os dados sintéticos validam sintaxe e lógica, **não os seus números reais**. Quem confirma os valores é você: rode `sql/08_kpis_validacao.sql` no seu banco e compare com os cartões.

## O que está correto

- Q1, Q2, Q4, Q5 (Vendas): filtram pedidos entregues, e o ticket médio soma os pagamentos por pedido antes da média.
- Q7, Q8, Q9, Q10 (Clientes): usam `customer_unique_id`.
- Q11, Q12, Q13 (Logística): usam só pedidos entregues com data de entrega; o ranking de vendedores evita contar o mesmo pedido duas vezes.
- Q15 (Satisfação): atraso x nota, só pedidos entregues.
- Views de tratamento da Etapa 3: cada uma corrige exatamente a inconsistência encontrada.

## Correções necessárias (3)

### 1. Satisfação considerava avaliações de pedidos não entregues
A regra do projeto é "só pedidos entregues", mas a `vw_avaliacoes` e a Q14 incluíam todas as avaliações (~98,7 mil contra ~95,8 mil em pedidos entregues, de acordo com a Q15). Isso afeta os 3 cartões de nota e o gráfico de distribuição. Há uma segunda consequência: a frase **"nota 1 é maior que as notas 2 e 3 somadas"** vencia por apenas 0,1 ponto percentual (11,52% contra 11,41%) e **pode deixar de ser verdadeira** com a base correta.

**O que fazer**
1. Rode o `07_modelagem_bi.sql` atualizado (a view `vw_avaliacoes` agora filtra pedidos entregues).
2. No Power BI: **Atualizar**.
3. Rode o `08_kpis_validacao.sql`. Compare "Pedidos com nota 1 (%)" com "Notas 2 e 3 somadas (%)". Se a nota 1 **não** for maior, tire a frase "(mais que notas 2 e 3 somadas)" do cartão.
4. Confira os 3 cartões e o gráfico de distribuição com o `08`. A nota média da base de entregues deve ficar perto de 4,15, e o arredondamento pode mudar o cartão de 4,1 para 4,2.

### 2. Top 10 categorias com pior avaliação contava itens, não avaliações
Na Q16 e na `vw_categoria_avaliacao`, um pedido com 3 itens da mesma categoria pesava 3 vezes na média, e a coluna `qtd_avaliacoes` na verdade contava itens. Agora cada par (categoria, pedido) conta uma vez.

**O que fazer:** o mesmo `07` atualizado já traz a correção. Depois de **Atualizar** no Power BI, confira o gráfico: as notas podem mudar na segunda casa decimal e categorias vizinhas podem trocar de posição. Se alguma frase do dashboard citar a posição de uma categoria, confira.

### 3. Q6 contava pedidos, e o dashboard conta pessoas
A Q6 contava linhas de `clientes` (uma por pedido); o gráfico do dashboard usa pessoas únicas (`vw_clientes_metricas`). Os valores divergiam (ex.: SP 40.501 na Q6 contra um número um pouco menor no gráfico).

**O que fazer:** o `04_queries_clientes.sql` atualizado já conta pessoas únicas, na mesma base do Power BI. Para manter a base única, as Q7 e Q9 também passaram a exigir pagamento válido; o total de clientes é o mesmo do cartão. Se o seu cartão de recompra mostra um texto fixo como "(2.801 de 93.358)", troque pelo total que aparece no cartão "Clientes únicos" (a diferença é de 1 cliente, cujo único pagamento era inválido).

## Conferência dos KPIs (SQL × cartões)

Rode `sql/08_kpis_validacao.sql`.

| Página | Cartão | Como o Power BI calcula | Valor esperado |
|---|---|---|---|
| Vendas | Receita total | soma de `vw_pagamentos[payment_value]` | R$ 15,42 Mi |
| Vendas | Pedidos entregues | contagem de `vw_pedidos_analise[order_id]` | 96.470 |
| Vendas | Ticket médio | média de `vw_pedido_valor[valor_pedido]` | ≈ R$ 160 |
| Clientes | Clientes únicos | contagem de `vw_clientes_metricas` | ≈ 93,4 mil |
| Clientes | Taxa de recompra | média de `recorrente_flag` | 3% |
| Clientes | Receita média por cliente | média de `receita_total` | R$ 165,20 |
| Logística | Tempo médio de entrega | média de `dias_entrega` | 12 dias |
| Logística | Taxa de atraso | média de `atrasado` | 8,11% (7.826 de 96.470) |
| Logística | Estado mais lento | maior média de `dias_entrega` por estado | RR, 29 dias |
| Satisfação | Nota média / % nota 5 / % nota 1 | médias sobre `vw_avaliacoes` | **conferir após a correção 1** |

Se algum cartão divergir do `08`, o problema está no Power BI (agregação errada, filtro de página ativo ou campo de outra tabela), não na view.

## Melhorias opcionais (não bloqueiam a publicação)

- **Dias inteiros:** `EXTRACT(DAY FROM ...)` descarta as horas, e a média de entrega fica ~0,5 dia abaixo da real. Está documentado no README; trocar para `EXTRACT(EPOCH FROM ...) / 86400` mudaria vários números do dashboard.
- **Estado do cliente:** `MAX(customer_state)` escolhe um estado arbitrário quando a pessoa tem pedidos em estados diferentes. Usar o estado do pedido mais recente seria mais defensável.
- **Views auxiliares:** `vw_receita_mensal` e `vw_intervalo_compras` só apoiam análises em SQL. Se não estiverem carregadas no seu modelo do Power BI, tudo bem.
- **DAX:** parte das views poderia virar medida DAX. A escolha por SQL foi deliberada (mais controle, lógica auditável) e está explicada no README.

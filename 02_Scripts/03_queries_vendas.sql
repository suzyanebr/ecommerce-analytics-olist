/*
  Regras de negócio: apenas pedidos "delivered" contam; receita = SUM(payment_value).
  Janela de análise: jan/2017 a ago/2018 (exclui fase piloto 2016 e meses
  finais com dado incompleto por censura de entrega — ver nota na Pergunta 1).
*/

-- ==========================================================
-- PERGUNTA 1: Evolução mensal da receita
-- ==========================================================
-- Exclui set-dez/2016 (fase piloto, volume irrelevante) e set-out/2018
-- (pedidos ainda não entregues no momento da coleta do dataset).
-- Nota para o dashboard: ago/2018 é o último mês da janela e pode estar
-- levemente subestimado por atraso de entrega.
SELECT
    DATE_TRUNC('month', p.order_purchase_timestamp)::DATE AS mes,
    SUM(pg.payment_value) AS receita
FROM pedidos p
JOIN vw_pagamentos pg ON pg.order_id = p.order_id
WHERE p.order_status = 'delivered'
  AND p.order_purchase_timestamp >= '2017-01-01'
  AND p.order_purchase_timestamp < '2018-09-01'
GROUP BY mes
ORDER BY mes;


-- ==========================================================
-- PERGUNTA 2: Receita e ticket médio por categoria
-- ==========================================================
SELECT
    vp.product_category,
    SUM(ip.price) AS receita_total,
    ROUND(AVG(ip.price), 2) AS ticket_medio,
    COUNT(*) AS qtd_itens_vendidos
FROM itens_pedido ip
JOIN vw_produtos vp ON vp.product_id = ip.product_id
JOIN pedidos p ON p.order_id = ip.order_id
WHERE p.order_status = 'delivered'
GROUP BY vp.product_category
ORDER BY receita_total DESC;


-- ==========================================================
-- PERGUNTA 3: Produtos que mais geram receita (Top 10)
-- ==========================================================
-- Obs: o Olist não tem nome de produto, só product_id (hash). Truncamos
-- pra 8 caracteres pra ficar legível no gráfico; documentar no README.
SELECT
    LEFT(ip.product_id, 8) AS produto_id_curto,
    vp.product_category,
    SUM(ip.price) AS receita_total,
    COUNT(*) AS qtd_vendida
FROM itens_pedido ip
JOIN vw_produtos vp ON vp.product_id = ip.product_id
JOIN pedidos p ON p.order_id = ip.order_id
WHERE p.order_status = 'delivered'
GROUP BY ip.product_id, vp.product_category
ORDER BY receita_total DESC
LIMIT 10;


-- ==========================================================
-- PERGUNTA 4: Ticket médio por estado do cliente
-- ==========================================================
-- Alguns pedidos têm pagamento dividido em mais de uma forma (linha extra
-- em pagamentos). A CTE soma o valor por pedido primeiro; só depois
-- calculamos a média por estado -- senão pedidos divididos puxariam a
-- média pra baixo de forma artificial.
WITH pedido_valor AS (
    SELECT
        p.order_id,
        p.customer_id,
        SUM(pg.payment_value) AS valor_pedido
    FROM pedidos p
    JOIN vw_pagamentos pg ON pg.order_id = p.order_id
    WHERE p.order_status = 'delivered'
    GROUP BY p.order_id, p.customer_id
)
SELECT
    c.customer_state,
    ROUND(AVG(pv.valor_pedido), 2) AS ticket_medio,
    COUNT(*) AS qtd_pedidos
FROM pedido_valor pv
JOIN clientes c ON c.customer_id = pv.customer_id
GROUP BY c.customer_state
ORDER BY ticket_medio DESC;


-- ==========================================================
-- PERGUNTA 5: Contribuição de cada forma de pagamento na receita
-- ==========================================================
SELECT
    pg.payment_type,
    SUM(pg.payment_value) AS receita_total,
    COUNT(DISTINCT pg.order_id) AS qtd_pedidos,
    ROUND(AVG(pg.payment_value), 2) AS valor_medio_por_linha
FROM vw_pagamentos pg
JOIN pedidos p ON p.order_id = pg.order_id
WHERE p.order_status = 'delivered'
GROUP BY pg.payment_type
ORDER BY receita_total DESC;
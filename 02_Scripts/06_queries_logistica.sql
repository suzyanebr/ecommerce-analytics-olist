/*
  Regras de negócio: apenas pedidos "delivered" contam.
  Pedido atrasado: order_delivered_customer_date > order_estimated_delivery_date.
  Usar vw_pedidos_logistica (exclui os 8 "delivered" sem data de entrega).
*/

-- ==========================================================
-- PERGUNTA 11: Tempo médio de entrega por estado do cliente
-- ==========================================================
SELECT
    c.customer_state,
    -- CORRIGIDO: EPOCH/86400 em vez de EXTRACT(DAY ...) (que descartava as horas)
    ROUND(AVG(EXTRACT(EPOCH FROM (pl.order_delivered_customer_date
                                  - pl.order_purchase_timestamp)) / 86400)::NUMERIC, 1) AS media_dias_entrega,
    COUNT(*) AS qtd_pedidos
FROM vw_pedidos_logistica pl
JOIN clientes c ON c.customer_id = pl.customer_id
WHERE pl.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY media_dias_entrega DESC;


-- ==========================================================
-- PERGUNTA 12: Taxa de pedidos atrasados
-- ==========================================================
SELECT
    COUNT(*) FILTER (WHERE order_delivered_customer_date > order_estimated_delivery_date)
        AS pedidos_atrasados,
    COUNT(*) AS total_pedidos,
    ROUND(100.0 * COUNT(*) FILTER (WHERE order_delivered_customer_date > order_estimated_delivery_date)
        / COUNT(*), 2) AS taxa_atraso_percentual
FROM vw_pedidos_logistica
WHERE order_status = 'delivered';


-- ==========================================================
-- PERGUNTA 13: Vendedores com maior taxa de atraso (mín. 20 pedidos)
-- ==========================================================
-- DISTINCT evita contar o mesmo pedido 2x quando o vendedor tem mais de
-- um item no mesmo pedido. O filtro de 20+ pedidos evita destacar
-- vendedor pequeno com 1-2 vendas e 100% de atraso (não é confiável).
WITH pedidos_vendedor AS (
    SELECT DISTINCT
        pl.order_id,
        ip.seller_id,
        pl.order_delivered_customer_date > pl.order_estimated_delivery_date AS atrasado
    FROM vw_pedidos_logistica pl
    JOIN itens_pedido ip ON ip.order_id = pl.order_id
    WHERE pl.order_status = 'delivered'
)
SELECT
    v.seller_id,
    v.seller_state,
    COUNT(*) AS qtd_pedidos,
    COUNT(*) FILTER (WHERE pv.atrasado) AS qtd_atrasados,
    ROUND(100.0 * COUNT(*) FILTER (WHERE pv.atrasado) / COUNT(*), 2) AS taxa_atraso
FROM pedidos_vendedor pv
JOIN vendedores v ON v.seller_id = pv.seller_id
GROUP BY v.seller_id, v.seller_state
HAVING COUNT(*) >= 20
ORDER BY taxa_atraso DESC
LIMIT 10;


-- ==========================================================
-- PERGUNTA 13b (NOVA): Estado com maior TAXA de atraso
-- ==========================================================
-- Para o KPI "Estado com pior índice de atraso". Antes o dashboard mostrava
-- RR / 29 dias, que é o maior TEMPO de entrega, não a maior TAXA de atraso.
-- Mínimo de 100 pedidos evita destacar estado com poucas vendas.
SELECT
    c.customer_state,
    COUNT(*) AS qtd_pedidos,
    ROUND(100.0 * COUNT(*) FILTER (WHERE pl.order_delivered_customer_date > pl.order_estimated_delivery_date)
        / COUNT(*), 2) AS taxa_atraso_percentual
FROM vw_pedidos_logistica pl
JOIN clientes c ON c.customer_id = pl.customer_id
WHERE pl.order_status = 'delivered'
GROUP BY c.customer_state
HAVING COUNT(*) >= 100
ORDER BY taxa_atraso_percentual DESC
LIMIT 10;
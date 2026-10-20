-- ==========================================================
-- PERGUNTA 9: Frequência de compra por cliente
-- ==========================================================
WITH pedidos_por_cliente AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT p.order_id) AS qtd_pedidos
    FROM pedidos p
    JOIN clientes c ON c.customer_id = p.customer_id
    WHERE p.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    CASE
        WHEN qtd_pedidos = 1 THEN '1 pedido'
        WHEN qtd_pedidos = 2 THEN '2 pedidos'
        WHEN qtd_pedidos = 3 THEN '3 pedidos'
        ELSE '4 ou mais'
    END AS faixa_frequencia,
    COUNT(*) AS qtd_clientes
FROM pedidos_por_cliente
GROUP BY faixa_frequencia
ORDER BY MIN(qtd_pedidos);

-- ==========================================================
-- PERGUNTA 10: Tempo médio entre compras (em dias)
-- ==========================================================
-- LAG() traz a data do pedido ANTERIOR do mesmo cliente, alinhada na
-- mesma linha do pedido atual -- daí dá pra calcular a diferença direto.
WITH pedidos_cliente_data AS (
    SELECT
        c.customer_unique_id,
        p.order_purchase_timestamp,
        LAG(p.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY p.order_purchase_timestamp
        ) AS pedido_anterior
    FROM pedidos p
    JOIN clientes c ON c.customer_id = p.customer_id
    WHERE p.order_status = 'delivered'
)
SELECT
    ROUND(AVG(EXTRACT(DAY FROM (order_purchase_timestamp - pedido_anterior))), 1)
        AS media_dias_entre_compras
FROM pedidos_cliente_data
WHERE pedido_anterior IS NOT NULL;
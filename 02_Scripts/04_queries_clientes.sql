/*
  Regras de negócio: apenas pedidos "delivered" contam.
  ATENÇÃO: customer_id é único por pedido (mesmo cliente gera vários);
  customer_unique_id identifica a pessoa de fato -- usado nas Perguntas 7 e 8.
*/

-- ==========================================================
-- PERGUNTA 6: Distribuição geográfica dos clientes
-- ==========================================================
-- CORRIGIDO: antes era COUNT(*) sobre pedidos (contava PEDIDOS, não clientes).
-- Agora conta pessoas únicas (customer_unique_id), mesma fonte do dashboard.
-- Requer a view vw_clientes_metricas (criada no script 08).
SELECT
    customer_state,
    COUNT(*) AS qtd_clientes
FROM vw_clientes_metricas
GROUP BY customer_state
ORDER BY qtd_clientes DESC;


-- ==========================================================
-- PERGUNTA 7: Taxa de recompra (recorrentes vs. únicos)
-- ==========================================================
-- customer_id é único POR PEDIDO; customer_unique_id identifica a pessoa.
-- Usar customer_id aqui daria 0% de recompra sempre -- errado.
-- CORRIGIDO: lê da vw_clientes_metricas (mesma base do dashboard: 93.357 clientes).
-- Antes dava 93.358 porque não exigia pagamento válido.
SELECT
    tipo_cliente,
    COUNT(*) AS qtd_clientes,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentual
FROM vw_clientes_metricas
GROUP BY tipo_cliente;


-- ==========================================================
-- PERGUNTA 8: Receita média por cliente (LTV aproximado)
-- ==========================================================
-- CORRIGIDO: lê da vw_clientes_metricas (mesma fonte das Perguntas 6, 7 e 9).
SELECT
    ROUND(AVG(receita_total), 2) AS ltv_medio,
    COUNT(*) AS qtd_clientes_unicos
FROM vw_clientes_metricas;
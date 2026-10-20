/*
  Regras de negócio: apenas pedidos "delivered" contam.
  Usar vw_avaliacoes (review mais recente por pedido, sem duplicidade).
*/

-- ==========================================================
-- PERGUNTA 14: Distribuição das avaliações (notas 1 a 5)
-- ==========================================================
SELECT
    review_score,
    COUNT(*) AS qtd_avaliacoes,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM vw_avaliacoes), 2) AS percentual
FROM vw_avaliacoes
GROUP BY review_score
ORDER BY review_score;


-- ==========================================================
-- PERGUNTA 15: Atraso na entrega x nota de avaliação
-- ==========================================================
SELECT
    CASE
        WHEN pl.order_delivered_customer_date > pl.order_estimated_delivery_date
            THEN 'atrasado'
        ELSE 'no prazo'
    END AS situacao_entrega,
    ROUND(AVG(av.review_score), 2) AS nota_media,
    COUNT(*) AS qtd_pedidos
FROM vw_pedidos_logistica pl
JOIN vw_avaliacoes av ON av.order_id = pl.order_id
WHERE pl.order_status = 'delivered'
GROUP BY situacao_entrega;


-- ==========================================================
-- PERGUNTA 16: Categorias com pior avaliação média (Top 10 piores)
-- ==========================================================
-- Nota: review é por PEDIDO, não por produto. Pedido com vários itens
-- de categorias diferentes conta a mesma nota pra cada categoria -- é
-- uma aproximação inerente ao dataset (Olist não avalia item a item).
SELECT
    vp.product_category,
    ROUND(AVG(av.review_score), 2) AS nota_media,
    COUNT(*) AS qtd_avaliacoes
FROM itens_pedido ip
JOIN vw_produtos vp ON vp.product_id = ip.product_id
JOIN pedidos p ON p.order_id = ip.order_id
JOIN vw_avaliacoes av ON av.order_id = ip.order_id
WHERE p.order_status = 'delivered'
GROUP BY vp.product_category
HAVING COUNT(*) >= 20
ORDER BY nota_media ASC
LIMIT 10;
/*
Achados principais:
- 610 produtos sem categoria
- 8 pedidos "delivered" sem data de entrega
- 547 reviews duplicadas
- 9 pagamentos com valor <= 0

Tratamento realizado via VIEWs (seção 6), sem alterar dados brutos.
*/
-- ==========================================================
-- 1. VALORES NULOS
-- ==========================================================

SELECT
    COUNT(*) FILTER (WHERE customer_id IS NULL)    AS clientes_sem_id,
    COUNT(*) FILTER (WHERE customer_city IS NULL)  AS clientes_sem_cidade,
    COUNT(*) FILTER (WHERE customer_state IS NULL) AS clientes_sem_estado
FROM clientes;
-- 0 | 0 | 0 -> OK

SELECT
    COUNT(*) FILTER (WHERE order_delivered_customer_date IS NULL) AS sem_data_entrega,
    COUNT(*) FILTER (WHERE order_status = 'delivered') AS status_entregue,
    COUNT(*) FILTER (WHERE order_status = 'delivered'
                      AND order_delivered_customer_date IS NULL) AS entregue_sem_data
FROM pedidos;
-- 2965 sem data (esperado) | 96478 entregues | 8 entregue sem data -> tratar (6.1)

SELECT
    COUNT(*) FILTER (WHERE price IS NULL) AS sem_preco,
    COUNT(*) FILTER (WHERE freight_value IS NULL) AS sem_frete,
    COUNT(*) FILTER (WHERE product_id IS NULL) AS sem_produto
FROM itens_pedido;
-- 0 | 0 | 0 -> OK

SELECT
    COUNT(*) FILTER (WHERE payment_value IS NULL) AS sem_valor_pagamento,
    COUNT(*) FILTER (WHERE payment_type IS NULL) AS sem_tipo_pagamento
FROM pagamentos;
-- 0 | 0 -> OK

SELECT
    COUNT(*) FILTER (WHERE review_score IS NULL) AS sem_nota,
    COUNT(*) FILTER (WHERE review_comment_message IS NULL) AS sem_comentario
FROM avaliacoes;
-- 0 sem nota -> OK | 58247 sem comentário (esperado, campo opcional)

SELECT COUNT(*) FILTER (WHERE product_category IS NULL) AS sem_categoria
FROM produtos;
-- 610 -> tratar (6.2)


-- ==========================================================
-- 2. DUPLICIDADE
-- ==========================================================

SELECT customer_id, COUNT(*)
FROM clientes
GROUP BY customer_id
HAVING COUNT(*) > 1;
-- 0 linhas -> OK

SELECT order_id, COUNT(*)
FROM pedidos
GROUP BY order_id
HAVING COUNT(*) > 1;
-- 0 linhas -> OK

SELECT order_id, COUNT(*)
FROM avaliacoes
GROUP BY order_id
HAVING COUNT(*) > 1;
-- 547 pedidos com 2 reviews -> tratar (6.3)


-- ==========================================================
-- 3. CONSISTÊNCIA DE DATAS
-- ==========================================================

SELECT order_id, order_purchase_timestamp, order_delivered_customer_date
FROM pedidos
WHERE order_delivered_customer_date < order_purchase_timestamp;
-- 0 linhas -> OK

SELECT order_id, order_purchase_timestamp, order_approved_at
FROM pedidos
WHERE order_approved_at < order_purchase_timestamp;
-- 0 linhas -> OK

SELECT order_id, order_purchase_timestamp
FROM pedidos
WHERE order_purchase_timestamp < '2016-01-01'
   OR order_purchase_timestamp > '2018-12-31';
-- 0 linhas -> OK


-- ==========================================================
-- 4. VALORES IMPOSSÍVEIS
-- ==========================================================

SELECT
    COUNT(*) FILTER (WHERE price <= 0) AS preco_invalido,
    COUNT(*) FILTER (WHERE freight_value < 0) AS frete_invalido
FROM itens_pedido;
-- 0 | 0 -> OK

SELECT COUNT(*) FILTER (WHERE payment_value <= 0) AS pagamento_invalido
FROM pagamentos;
-- 9 -> tratar (6.4)

SELECT COUNT(*) FILTER (WHERE review_score NOT BETWEEN 1 AND 5) AS nota_invalida
FROM avaliacoes;
-- 0 -> OK


-- ==========================================================
-- 5. TEXTO MAL FORMATADO
-- ==========================================================

SELECT DISTINCT customer_state, LENGTH(customer_state) AS tamanho
FROM clientes
WHERE LENGTH(customer_state) <> 2;
-- 0 linhas -> OK

SELECT COUNT(*) FILTER (WHERE TRIM(customer_city) = '') AS cidade_em_branco
FROM clientes;
-- 0 -> OK


-- ==========================================================
-- 6. TRATAMENTO (views sobre os dados brutos, sem alterá-los)
-- ==========================================================

-- 6.1 Remove pedidos "delivered" sem data de entrega
CREATE OR REPLACE VIEW vw_pedidos_logistica AS
SELECT *
FROM pedidos
WHERE NOT (order_status = 'delivered' AND order_delivered_customer_date IS NULL);

-- 6.2 Categoria nula -> 'nao_informado'
CREATE OR REPLACE VIEW vw_produtos AS
SELECT
    product_id,
    COALESCE(product_category, 'nao_informado') AS product_category,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM produtos;

-- 6.3 Mantém apenas a review mais recente por pedido
CREATE OR REPLACE VIEW vw_avaliacoes AS
SELECT *
FROM (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC) AS rn
    FROM avaliacoes
) AS sub
WHERE rn = 1;

-- 6.4 Remove pagamentos com valor <= 0
CREATE OR REPLACE VIEW vw_pagamentos AS
SELECT *
FROM pagamentos
WHERE payment_value > 0;


-- ==========================================================
-- 7. VERIFICAÇÃO DO TRATAMENTO (confirma que as views corrigiram o problema)
-- ==========================================================

-- 7.1 vw_pedidos_logistica: não deve sobrar nenhum "delivered" sem data
SELECT COUNT(*) FILTER (WHERE order_status = 'delivered'
                          AND order_delivered_customer_date IS NULL) AS ainda_com_problema
FROM vw_pedidos_logistica;
-- Esperado: 0

-- 7.1b Conferir que a view tem exatamente 8 linhas a menos que a tabela original
SELECT
    (SELECT COUNT(*) FROM pedidos) AS total_pedidos,
    (SELECT COUNT(*) FROM vw_pedidos_logistica) AS total_view,
    (SELECT COUNT(*) FROM pedidos) - (SELECT COUNT(*) FROM vw_pedidos_logistica) AS diferenca;
-- Esperado: diferenca = 8

-- 7.2 vw_produtos: não deve sobrar nenhuma categoria nula
SELECT COUNT(*) FILTER (WHERE product_category IS NULL) AS ainda_nulo
FROM vw_produtos;
-- Esperado: 0

-- 7.2b Conferir que os 610 foram marcados como 'nao_informado'
SELECT COUNT(*) FILTER (WHERE product_category = 'nao_informado') AS marcados_nao_informado
FROM vw_produtos;
-- Esperado: 610

-- 7.3 vw_avaliacoes: não deve sobrar nenhum pedido com 2 reviews
SELECT order_id, COUNT(*)
FROM vw_avaliacoes
GROUP BY order_id
HAVING COUNT(*) > 1;
-- Esperado: 0 linhas

-- 7.3b Conferir que a view tem 547 linhas a menos que a tabela original
SELECT
    (SELECT COUNT(*) FROM avaliacoes) AS total_avaliacoes,
    (SELECT COUNT(*) FROM vw_avaliacoes) AS total_view,
    (SELECT COUNT(*) FROM avaliacoes) - (SELECT COUNT(*) FROM vw_avaliacoes) AS diferenca;
-- Esperado: diferenca = 547

-- 7.4 vw_pagamentos: não deve sobrar nenhum valor <= 0
SELECT COUNT(*) FILTER (WHERE payment_value <= 0) AS ainda_invalido
FROM vw_pagamentos;
-- Esperado: 0

-- 7.4b Conferir que a view tem 9 linhas a menos que a tabela original
SELECT
    (SELECT COUNT(*) FROM pagamentos) AS total_pagamentos,
    (SELECT COUNT(*) FROM vw_pagamentos) AS total_view,
    (SELECT COUNT(*) FROM pagamentos) - (SELECT COUNT(*) FROM vw_pagamentos) AS diferenca;
-- Esperado: diferenca = 9





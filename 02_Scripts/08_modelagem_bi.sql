/*
  ETAPA 5: Modelagem analítica
  Views consolidadas, prontas para importar no Power BI (Etapa 6).
  Reúnem padrões repetidos nas 16 perguntas de negócio, evitando
  recriar essa lógica em DAX.
*/

-- 1. Tabela-fato principal (só delivered, com data de entrega válida)
CREATE OR REPLACE VIEW vw_pedidos_analise AS
SELECT
    *,
    order_purchase_timestamp::DATE AS order_purchase_date, -- para relacionar com vw_calendario
    EXTRACT(DAY FROM (order_delivered_customer_date - order_purchase_timestamp)) AS dias_entrega,
    CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
         THEN 1 ELSE 0 END AS atrasado,
    CASE WHEN order_delivered_customer_date > order_estimated_delivery_date
         THEN 'Atrasado' ELSE 'No prazo' END AS atrasado_texto,
    -- NOVO (sempre no FIM da lista): dias com fração. dias_entrega descarta as horas.
    -- No Power BI, use dias_entrega_exato no KPI e no gráfico de prazo por estado.
    ROUND((EXTRACT(EPOCH FROM (order_delivered_customer_date - order_purchase_timestamp)) / 86400)::NUMERIC, 2)
        AS dias_entrega_exato
FROM pedidos
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;


-- 2. Dimensão de calendário (nomes de mês fixos em PT, não depende do locale do servidor)
CREATE OR REPLACE VIEW vw_calendario AS
SELECT
    d::DATE AS data,
    EXTRACT(YEAR FROM d) AS ano,
    EXTRACT(MONTH FROM d) AS mes_numero,
    CASE EXTRACT(MONTH FROM d)
        WHEN 1 THEN 'Janeiro' WHEN 2 THEN 'Fevereiro' WHEN 3 THEN 'Março'
        WHEN 4 THEN 'Abril' WHEN 5 THEN 'Maio' WHEN 6 THEN 'Junho'
        WHEN 7 THEN 'Julho' WHEN 8 THEN 'Agosto' WHEN 9 THEN 'Setembro'
        WHEN 10 THEN 'Outubro' WHEN 11 THEN 'Novembro' WHEN 12 THEN 'Dezembro'
    END AS mes_nome,
    TO_CHAR(d, 'YYYY-MM') AS ano_mes,
    EXTRACT(QUARTER FROM d) AS trimestre,
    (EXTRACT(YEAR FROM d) * 100 + EXTRACT(MONTH FROM d))::INT AS ano_mes_num,
    DATE_TRUNC('month', d)::DATE AS mes_data,
    CASE WHEN d::DATE >= DATE '2017-01-01' AND d::DATE < DATE '2018-09-01'
         THEN 'Sim' ELSE 'Não' END AS janela_analise -- jan/2017 a ago/2018, período confiável (ver Pergunta 1)
FROM generate_series('2016-01-01'::DATE, '2018-12-31'::DATE, '1 day'::interval) AS d;


-- 3. Métricas consolidadas por cliente único (recompra, LTV, frequência)
-- Substitui as CTEs das Perguntas 7, 8 e 9 por uma tabela pronta pro Power BI.
CREATE OR REPLACE VIEW vw_clientes_metricas AS
SELECT
    c.customer_unique_id,
    MAX(c.customer_state) AS customer_state, -- simplificação: quase todo cliente só tem 1 estado mesmo
    COUNT(DISTINCT p.order_id) AS qtd_pedidos,
    SUM(pg.payment_value) AS receita_total,
    CASE WHEN COUNT(DISTINCT p.order_id) >= 2 THEN 'Recorrente' ELSE 'Único' END AS tipo_cliente,
    CASE
        WHEN COUNT(DISTINCT p.order_id) = 1 THEN '1 pedido'
        WHEN COUNT(DISTINCT p.order_id) = 2 THEN '2 pedidos'
        WHEN COUNT(DISTINCT p.order_id) = 3 THEN '3 pedidos'
        ELSE '4 ou mais'
    END AS faixa_frequencia,
    CASE WHEN COUNT(DISTINCT p.order_id) >= 2 THEN 1 ELSE 0 END AS recorrente_flag
FROM pedidos p
JOIN clientes c ON c.customer_id = p.customer_id
JOIN vw_pagamentos pg ON pg.order_id = p.order_id
WHERE p.order_status = 'delivered'
GROUP BY c.customer_unique_id;


-- 5. Valor total pago por pedido (resolve a distorção de pagamento dividido
-- em mais de uma forma -- mesma lógica da Pergunta 4)
CREATE OR REPLACE VIEW vw_pedido_valor AS
SELECT
    p.order_id,
    p.customer_id,
    SUM(pg.payment_value) AS valor_pedido
FROM vw_pedidos_analise p
JOIN vw_pagamentos pg ON pg.order_id = p.order_id
GROUP BY p.order_id, p.customer_id;


-- 4. Dias desde a última compra, pedido a pedido (base da Pergunta 10)
CREATE OR REPLACE VIEW vw_intervalo_compras AS
SELECT
    c.customer_unique_id,
    p.order_purchase_timestamp,
    EXTRACT(DAY FROM (
        p.order_purchase_timestamp - LAG(p.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY p.order_purchase_timestamp
        )
    )) AS dias_desde_ultima_compra,
    -- NOVO (no FIM): dias com fração
    EXTRACT(EPOCH FROM (
        p.order_purchase_timestamp - LAG(p.order_purchase_timestamp) OVER (
            PARTITION BY c.customer_unique_id
            ORDER BY p.order_purchase_timestamp
        )
    )) / 86400 AS dias_exatos_desde_ultima_compra
FROM pedidos p
JOIN clientes c ON c.customer_id = p.customer_id
WHERE p.order_status = 'delivered';


-- 6. Taxa de atraso por vendedor (mín. 20 pedidos), sem duplicar contagem
-- quando o vendedor tem mais de um item no mesmo pedido
CREATE OR REPLACE VIEW vw_vendedor_atraso AS
SELECT
    seller_id,
    seller_state,
    qtd_pedidos,
    qtd_atrasados,
    taxa_atraso,
    -- Olist não tem nome de vendedor, só hash. Anonimiza com rótulo legível,
    -- mantendo o estado (parte do insight: a maioria dos piores é de SP).
    'Vendedor ' || ROW_NUMBER() OVER (ORDER BY taxa_atraso DESC, qtd_pedidos DESC, seller_id) || ' (' || seller_state || ')' AS vendedor_label
FROM (
    SELECT
        v.seller_id,
        v.seller_state,
        COUNT(*) AS qtd_pedidos,
        COUNT(*) FILTER (WHERE pv.atrasado) AS qtd_atrasados,
        ROUND(1.0 * COUNT(*) FILTER (WHERE pv.atrasado) / COUNT(*), 4) AS taxa_atraso -- fração (ex.: 0,375); o Power BI formata como %
    FROM (
        SELECT DISTINCT
            pl.order_id,
            ip.seller_id,
            pl.order_delivered_customer_date > pl.order_estimated_delivery_date AS atrasado
        FROM vw_pedidos_analise pl
        JOIN itens_pedido ip ON ip.order_id = pl.order_id
    ) pv
    JOIN vendedores v ON v.seller_id = pv.seller_id
    GROUP BY v.seller_id, v.seller_state
    HAVING COUNT(*) >= 20
) sub;


-- 7. Nota média por categoria, já com o mínimo de 20 avaliações embutido
-- (evita depender do filtro de contagem no Power BI)
CREATE OR REPLACE VIEW vw_categoria_avaliacao AS
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
HAVING COUNT(*) >= 20;


-- 8. Receita mensal já filtrada (jan/2017-ago/2018) e ordenável por data
-- (evita depender do filtro de intervalo de datas no Power BI)
CREATE OR REPLACE VIEW vw_receita_mensal AS
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


-- 9. Atualiza vw_avaliacoes (criada na Etapa 3): acrescenta flags de nota 5
-- e nota 1, para os KPIs de satisfação sem precisar de DAX
-- CORRIGIDO: agora só considera pedidos ENTREGUES (JOIN com vw_pedidos_analise).
-- Antes pegava reviews de qualquer pedido (cancelado, em trânsito...), o que
-- inflava a nota média e as contagens da página Satisfação.
CREATE OR REPLACE VIEW vw_avaliacoes AS
SELECT
    *,
    CASE WHEN review_score = 5 THEN 1 ELSE 0 END AS nota_5_flag,
    CASE WHEN review_score = 1 THEN 1 ELSE 0 END AS nota_1_flag
FROM (
    SELECT
        a.*,
        ROW_NUMBER() OVER (
            PARTITION BY a.order_id
            ORDER BY a.review_answer_timestamp DESC, a.review_id
        ) AS rn
    FROM avaliacoes a
    JOIN vw_pedidos_analise pa ON pa.order_id = a.order_id
) AS sub
WHERE rn = 1;


-- 10. Nota média por situação de entrega, já pronta (evita depender do
-- relacionamento entre vw_pedidos_analise e vw_avaliacoes nesse gráfico)
CREATE OR REPLACE VIEW vw_atraso_satisfacao AS
SELECT
    CASE WHEN pl.order_delivered_customer_date > pl.order_estimated_delivery_date
         THEN 'Atrasado' ELSE 'No prazo' END AS situacao_entrega,
    ROUND(AVG(av.review_score), 2) AS nota_media,
    COUNT(*) AS qtd_pedidos
FROM vw_pedidos_analise pl
JOIN vw_avaliacoes av ON av.order_id = pl.order_id
GROUP BY situacao_entrega;


-- 11. CORREÇÃO: atualiza vw_pagamentos (criada na Etapa 3) para já filtrar
-- só pedidos entregues. A versão original só validava payment_value > 0,
-- sem checar o status do pedido -- por isso "Receita Total" e "Forma de
-- Pagamento" no Power BI estavam somando pagamento de pedido não entregue.
CREATE OR REPLACE VIEW vw_pagamentos AS
SELECT
    pg.*,
    CASE pg.payment_type
        WHEN 'credit_card' THEN 'Cartão de Crédito'
        WHEN 'boleto' THEN 'Boleto'
        WHEN 'voucher' THEN 'Voucher'
        WHEN 'debit_card' THEN 'Cartão de Débito'
        ELSE pg.payment_type
    END AS payment_type_pt
FROM pagamentos pg
JOIN pedidos p ON p.order_id = pg.order_id
WHERE pg.payment_value > 0
  AND p.order_status = 'delivered';


-- Catálogo completo pronto para importar no Power BI (Etapa 6):
-- vw_pedidos_analise, vw_calendario, vw_clientes_metricas, vw_intervalo_compras,
-- vw_pedido_valor, vw_produtos, vw_pagamentos, vw_avaliacoes, itens_pedido,
-- vendedores, clientes
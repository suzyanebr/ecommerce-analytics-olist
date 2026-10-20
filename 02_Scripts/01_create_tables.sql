CREATE TABLE clientes (
    customer_id VARCHAR PRIMARY KEY,
    customer_unique_id VARCHAR,
    customer_zip VARCHAR,
    customer_city VARCHAR,
    customer_state VARCHAR
);

CREATE TABLE vendedores (
    seller_id VARCHAR PRIMARY KEY,
    seller_zip VARCHAR,
    seller_city VARCHAR,
    seller_state VARCHAR
);

CREATE TABLE produtos (
    product_id VARCHAR PRIMARY KEY,
    product_category VARCHAR,
    product_name_length NUMERIC,
    product_description_length NUMERIC,
    product_photos_qty NUMERIC,
    product_weight_g NUMERIC,
    product_length_cm NUMERIC,
    product_height_cm NUMERIC,
    product_width_cm NUMERIC
);

CREATE TABLE pedidos (
    order_id VARCHAR PRIMARY KEY,
    customer_id VARCHAR REFERENCES clientes(customer_id),
    order_status VARCHAR,
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

CREATE TABLE itens_pedido (
    order_id VARCHAR REFERENCES pedidos(order_id),
    order_item_id INTEGER,
    product_id VARCHAR REFERENCES produtos(product_id),
    seller_id VARCHAR REFERENCES vendedores(seller_id),
    shipping_limit_date TIMESTAMP,
    price NUMERIC,
    freight_value NUMERIC
);

CREATE TABLE pagamentos (
    order_id VARCHAR REFERENCES pedidos(order_id),
    payment_sequential INTEGER,
    payment_type VARCHAR,
    payment_installments INTEGER,
    payment_value NUMERIC
);

CREATE TABLE avaliacoes (
    review_id VARCHAR,
    order_id VARCHAR REFERENCES pedidos(order_id),
    review_score INTEGER,
    review_comment_title VARCHAR,
    review_comment_message VARCHAR,
    review_creation_date TIMESTAMP,
    review_answer_timestamp TIMESTAMP
);
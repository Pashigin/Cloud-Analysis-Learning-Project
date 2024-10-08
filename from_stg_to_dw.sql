-- create schema
-- create dim tables (shipping, customer, product, geo)
-- fix data quality problem
-- create sales_fact table
-- match number of rows between staging and dw (business layer);CREATE SCHEMA dw;
--SHIPPING;
--creating a table
DROP TABLE IF EXISTS dw.shipping_dim;
CREATE TABLE dw.shipping_dim (
    ship_id serial NOT NULL,
    shipping_mode varchar(14) NOT NULL,
    CONSTRAINT PK_shipping_dim PRIMARY KEY (ship_id)
);
--deleting rows
TRUNCATE TABLE dw.shipping_dim;
--generating ship_id and inserting ship_mode from orders
INSERT INTO
    dw.shipping_dim
SELECT
    100 + ROW_NUMBER() OVER(),
    ship_mode
FROM
    (
        SELECT
            DISTINCT ship_mode
        FROM
            stg.orders
    ) a;
--checking
SELECT
    *
FROM
    dw.shipping_dim sd;
--CUSTOMER;DROP TABLE IF EXISTS dw.customer_dim ;;CREATE TABLE dw.customer_dim
(
    cust_id serial NOT NULL,
    customer_id varchar(8) NOT NULL,
    --id can't be NULL
    customer_name varchar(22) NOT NULL,
    CONSTRAINT PK_customer_dim PRIMARY KEY (cust_id)
);
--deleting rows
TRUNCATE TABLE dw.customer_dim;
--inserting
INSERT INTO
    dw.customer_dim
SELECT
    100 + ROW_NUMBER() OVER(),
    customer_id,
    customer_name
FROM
    (
        SELECT
            DISTINCT customer_id,
            customer_name
        FROM
            stg.orders
    ) a;
--checking
SELECT
    *
FROM
    dw.customer_dim cd;
--GEOGRAPHY;DROP TABLE IF EXISTS dw.geo_dim ;;CREATE TABLE dw.geo_dim
(
    geo_id serial NOT NULL,
    country varchar(13) NOT NULL,
    city varchar(17) NOT NULL,
    state varchar(20) NOT NULL,
    postal_code varchar(20) NULL,
    --can't be integer, we lost first 0
    CONSTRAINT PK_geo_dim PRIMARY KEY (geo_id)
);
--deleting rows
TRUNCATE TABLE dw.geo_dim;
--generating geo_id and inserting rows from orders
INSERT INTO
    dw.geo_dim
SELECT
    100 + ROW_NUMBER() OVER(),
    country,
    city,
    state,
    postal_code
FROM
    (
        SELECT
            DISTINCT country,
            city,
            state,
            postal_code
        FROM
            stg.orders
    ) a;
--data quality check
SELECT
    DISTINCT country,
    city,
    state,
    postal_code
FROM
    dw.geo_dim
WHERE
    country IS NULL
    OR city IS NULL
    OR postal_code IS NULL;
-- City Burlington, Vermont doesn't have postal code
UPDATE
    dw.geo_dim
SET
    postal_code = '05401'
WHERE
    city = 'Burlington'
    AND postal_code IS NULL;
--also update source file
UPDATE
    stg.orders
SET
    postal_code = '05401'
WHERE
    city = 'Burlington'
    AND postal_code IS NULL;
SELECT
    *
FROM
    dw.geo_dim
WHERE
    city = 'Burlington';
--PRODUCT;
--creating a table
DROP TABLE IF EXISTS dw.product_dim;
CREATE TABLE dw.product_dim (
    prod_id serial NOT NULL,
    --we created surrogated key
    product_id varchar(50) NOT NULL,
    --exist in ORDERS table
    product_name varchar(127) NOT NULL,
    category varchar(15) NOT NULL,
    sub_category varchar(11) NOT NULL,
    segment varchar(11) NOT NULL,
    CONSTRAINT PK_product_dim PRIMARY KEY (prod_id)
);
--deleting rows
TRUNCATE TABLE dw.product_dim;
--
INSERT INTO
    dw.product_dim
SELECT
    100 + ROW_NUMBER() OVER () AS prod_id,
    product_id,
    product_name,
    category,
    subcategory,
    segment
FROM
    (
        SELECT
            DISTINCT product_id,
            product_name,
            category,
            subcategory,
            segment
        FROM
            stg.orders
    ) a;
--checking
SELECT
    *
FROM
    dw.product_dim cd;
--CALENDAR use function instead 
-- examplehttps://tapoueh.org/blog/2017/06/postgresql-and-the-calendar/;
--creating a table
DROP TABLE IF EXISTS dw.calendar_dim;
CREATE TABLE dw.calendar_dim (
    dateid serial NOT NULL,
    YEAR int NOT NULL,
    quarter int NOT NULL,
    MONTH int NOT NULL,
    week int NOT NULL,
    date date NOT NULL,
    week_day varchar(20) NOT NULL,
    leap varchar(20) NOT NULL,
    CONSTRAINT PK_calendar_dim PRIMARY KEY (dateid)
);
--deleting rows
TRUNCATE TABLE dw.calendar_dim;
--
INSERT INTO
    dw.calendar_dim (
        date_id,
        year,
        quarter,
        MONTH,
        week,
        date,
        week_day,
        leap
    )
SELECT
    to_char(date, 'yyyymmdd') :: int AS date_id,
    extract(
        'year'
        FROM
            date
    ) :: int AS year,
    extract(
        'quarter'
        FROM
            date
    ) :: int AS quarter,
    extract(
        'month'
        FROM
            date
    ) :: int AS MONTH,
    extract(
        'week'
        FROM
            date
    ) :: int AS week,
    date :: date,
    to_char(date, 'dy') AS week_day,
    (
        CASE
            WHEN extract(
                'day'
                FROM
                    (date + INTERVAL '2 months')
            ) = 29 THEN TRUE
            ELSE false
        END
    ) AS leap
FROM
    generate_series(
        timestamp '2000-01-01',
        timestamp '2030-01-01',
        INTERVAL '1 day'
    ) AS t(date);
--checking
SELECT
    *
FROM
    dw.calendar_dim;
--METRICS;
--creating a table
DROP TABLE IF EXISTS dw.sales_fact;
CREATE TABLE dw.sales_fact (
    sales_id serial NOT NULL,
    cust_id integer NOT NULL,
    order_date_id integer NOT NULL,
    ship_date_id integer NOT NULL,
    prod_id integer NOT NULL,
    ship_id integer NOT NULL,
    geo_id integer NOT NULL,
    order_id varchar(25) NOT NULL,
    sales NUMERIC(9, 4) NOT NULL,
    profit NUMERIC(21, 16) NOT NULL,
    quantity int4 NOT NULL,
    discount NUMERIC(4, 2) NOT NULL,
    CONSTRAINT PK_sales_fact PRIMARY KEY (sales_id)
);
INSERT INTO
    dw.sales_fact
SELECT
    100 + ROW_NUMBER() OVER() AS sales_id,
    cust_id,
    to_char(order_date, 'yyyymmdd') :: int AS order_date_id,
    to_char(ship_date, 'yyyymmdd') :: int AS ship_date_id,
    p.prod_id,
    s.ship_id,
    geo_id,
    o.order_id,
    sales,
    profit,
    quantity,
    discount
FROM
    stg.orders o
    INNER JOIN dw.shipping_dim s ON o.ship_mode = s.shipping_mode
    INNER JOIN dw.geo_dim g ON o.postal_code = g.postal_code
    AND g.country = o.country
    AND g.city = o.city
    AND o.state = g.state --City Burlington doesn't have postal code
    INNER JOIN dw.product_dim p ON o.product_name = p.product_name
    AND o.segment = p.segment
    AND o.subcategory = p.sub_category
    AND o.category = p.category
    AND o.product_id = p.product_id
    INNER JOIN dw.customer_dim cd ON cd.customer_id = o.customer_id
    AND cd.customer_name = o.customer_name;
--get 9994rows
SELECT
    count(*)
FROM
    dw.sales_fact sf
    INNER JOIN dw.shipping_dim s ON sf.ship_id = s.ship_id
    INNER JOIN dw.geo_dim g ON sf.geo_id = g.geo_id
    INNER JOIN dw.product_dim p ON sf.prod_id = p.prod_id
    INNER JOIN dw.customer_dim cd ON sf.cust_id = cd.cust_id;
SELECT
    *
FROM
    dw.sales_fact sf;
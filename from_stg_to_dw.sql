-- create schema
-- create dim tables (shipping, customer, product, geo)
-- fix data quality problem
-- create sales_fact table
-- match number of rows between staging and dw (business layer);CREATE SCHEMA dw;
-- create 2 more tables and update the fact table
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

--CUSTOMER
DROP TABLE IF EXISTS dw.customer_dim;

CREATE TABLE dw.customer_dim (
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

--CALENDAR
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

--custom calendaer code
INSERT INTO
    dw.calendar_dim
SELECT
    to_char(date, 'yyyymmdd') :: int AS date_id,
    EXTRACT(
        'year'
        FROM
            date
    ) :: int AS YEAR,
    EXTRACT(
        'quarter'
        FROM
            date
    ) :: int AS quarter,
    EXTRACT(
        'month'
        FROM
            date
    ) :: int AS MONTH,
    EXTRACT(
        'week'
        FROM
            date
    ) :: int AS week,
    date :: date,
    to_char(date, 'dy') AS week_day,
    EXTRACT(
        'day'
        FROM
            (date + INTERVAL '2 month - 1 day')
    ) = 29 AS leap
FROM
    generate_series(
        date '2000-01-01',
        date '2030-01-01',
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

--check for all rows from stg.orders
SELECT
    count(*)
FROM
    dw.sales_fact sf
    INNER JOIN dw.shipping_dim s ON sf.ship_id = s.ship_id
    INNER JOIN dw.geo_dim g ON sf.geo_id = g.geo_id
    INNER JOIN dw.product_dim p ON sf.prod_id = p.prod_id
    INNER JOIN dw.customer_dim cd ON sf.cust_id = cd.cust_id;

--RETURNS
DROP TABLE IF EXISTS dw.returns_dim;

CREATE TABLE dw.returns_dim (
    return_id serial NOT NULL,
    returned varchar(10) NOT NULL,
    order_id varchar(20) NOT NULL,
    CONSTRAINT PK_returns_dim PRIMARY KEY (return_id)
);

--Add a column with returns
ALTER TABLE
    dw.sales_fact
ADD
    COLUMN return_id integer;

ALTER TABLE
    dw.sales_fact
ADD
    CONSTRAINT fk_sales_fact_returns_dim_return_id FOREIGN KEY (return_id) REFERENCES dw.returns_dim (return_id);

--Update rows
--the rows in dw.returns insterted in anotther script
UPDATE
    dw.sales_fact sf
SET
    return_id = r.return_id
FROM
    dw.returns_dim r
WHERE
    sf.order_id = r.order_id;

--Check
SELECT
    *
FROM
    dw.sales_fact sf
LIMIT
    10;

--MANAGERS
--create table with managers
DROP TABLE IF EXISTS dw.managers_dim;

CREATE TABLE managers_dim(
    manager_id serial NOT NULL PRIMARY KEY,
    manager VARCHAR(17) NOT NULL,
    region VARCHAR(7) NOT NULL
);

--insert rows into dw.managers_dim
INSERT INTO
    managers_dim(manager, region)
VALUES
    ('Anna Andreadi', 'West'),
    ('Chuck Magee', 'East'),
    ('Kelly Williams', 'Central'),
    ('Cassandra Brandow', 'South');

--Add a column with manager_id into sales_fact
ALTER TABLE
    dw.sales_fact
ADD
    COLUMN manager_id integer;

ALTER TABLE
    dw.sales_fact
ADD
    CONSTRAINT fk_sales_fact_managers FOREIGN KEY (manager_id) REFERENCES dw.managers_dim (manager_id);

--Insert rows from manager_dim based on rows in stg.orders
UPDATE
    dw.sales_fact sf
SET
    manager_id = m.manager_id
FROM
    stg.orders o
    JOIN managers_dim m ON o.Region = m.region
WHERE
    sf.order_id = o.Order_ID;

--Check
SELECT
    sf.sales_id,
    sf.order_id,
    m.manager_id,
    m.manager AS manager_name,
    m.region,
    o.region
FROM
    dw.sales_fact sf
    LEFT JOIN dw.managers_dim m ON sf.manager_id = m.manager_id
    LEFT JOIN stg.orders o ON sf.order_id = o.order_id
ORDER BY
    sf.sales_id
LIMIT
    20;
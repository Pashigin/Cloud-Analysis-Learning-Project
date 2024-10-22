DROP TABLE IF EXISTS dw.managers;

CREATE TABLE people(
    manager_id serial NOT NULL PRIMARY KEY,
    manager VARCHAR(17) NOT NULL,
    region VARCHAR(7) NOT NULL
);

INSERT INTO
    people(manager, Region)
VALUES
    ('Anna Andreadi', 'West');

INSERT INTO
    people(manager, Region)
VALUES
    ('Chuck Magee', 'East');

INSERT INTO
    people(manager, Region)
VALUES
    ('Kelly Williams', 'Central');

INSERT INTO
    people(manager, Region)
VALUES
    ('Cassandra Brandow', 'South');
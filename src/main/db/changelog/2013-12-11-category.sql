/*
    Create basic category table.

    - Carmen
*/

CREATE TABLE category (
    id      SERIAL      PRIMARY KEY,
    name    VARCHAR(255)    NOT NULL
);

ALTER TABLE category ADD CONSTRAINT category_name_uq UNIQUE (id, name);
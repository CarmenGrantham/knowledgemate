/**
 * File required to be run manually so that db_updater can be used for futher updates.
 * 
 * - Carmen
 */

CREATE TABLE db_update (
    id              SERIAL                      PRIMARY KEY,
    filename        VARCHAR(255)                NOT NULL,
    created_tstz    TIMESTAMP WITH TIME ZONE    NOT NULL    DEFAULT now()
);
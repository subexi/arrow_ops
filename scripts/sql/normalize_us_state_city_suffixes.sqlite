-- Normalisiert US-Verwaltungseinheiten auf das Format: ST-StateName
-- und US-Stadtfelder auf das Format: City, ST.
--
-- Ausfuehrung:
--   sqlite3 /pfad/zur/arrow_ops.db < scripts/sql/normalize_us_state_city_suffixes.sql

PRAGMA foreign_keys = ON;

CREATE TEMP TABLE IF NOT EXISTS us_states (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

DELETE FROM us_states;

INSERT INTO us_states(code, name) VALUES
('AL','Alabama'),
('AK','Alaska'),
('AZ','Arizona'),
('AR','Arkansas'),
('CA','California'),
('CO','Colorado'),
('CT','Connecticut'),
('DE','Delaware'),
('FL','Florida'),
('GA','Georgia'),
('HI','Hawaii'),
('ID','Idaho'),
('IL','Illinois'),
('IN','Indiana'),
('IA','Iowa'),
('KS','Kansas'),
('KY','Kentucky'),
('LA','Louisiana'),
('ME','Maine'),
('MD','Maryland'),
('MA','Massachusetts'),
('MI','Michigan'),
('MN','Minnesota'),
('MS','Mississippi'),
('MO','Missouri'),
('MT','Montana'),
('NE','Nebraska'),
('NV','Nevada'),
('NH','New Hampshire'),
('NJ','New Jersey'),
('NM','New Mexico'),
('NY','New York'),
('NC','North Carolina'),
('ND','North Dakota'),
('OH','Ohio'),
('OK','Oklahoma'),
('OR','Oregon'),
('PA','Pennsylvania'),
('RI','Rhode Island'),
('SC','South Carolina'),
('SD','South Dakota'),
('TN','Tennessee'),
('TX','Texas'),
('UT','Utah'),
('VT','Vermont'),
('VA','Virginia'),
('WA','Washington'),
('WV','West Virginia'),
('WI','Wisconsin'),
('WY','Wyoming'),
('DC','District of Columbia');

SELECT 'BEFORE_US_BILLING_STATE_NOT_ST_DASH_NAME' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_b_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c.c_state_b, '')) NOT IN ('', '-')
  AND trim(coalesce(c.c_state_b, '')) NOT LIKE '__-%';

SELECT 'BEFORE_US_DELIVERY_STATE_NOT_ST_DASH_NAME' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_d_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c.c_state_d, '')) NOT IN ('', '-')
  AND trim(coalesce(c.c_state_d, '')) NOT LIKE '__-%';

SELECT 'BEFORE_US_BILLING_CITY_MISSING_SUFFIX' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_b_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c.c_state_b, '')) LIKE '__-%'
  AND trim(coalesce(c.c_city_b, '')) NOT IN ('', '-')
  AND trim(c.c_city_b) NOT LIKE '%,' || ' ' || substr(trim(c.c_state_b), 1, 2);

SELECT 'BEFORE_US_DELIVERY_CITY_MISSING_SUFFIX' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_d_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c.c_state_d, '')) LIKE '__-%'
  AND trim(coalesce(c.c_city_d, '')) NOT IN ('', '-')
  AND trim(c.c_city_d) NOT LIKE '%,' || ' ' || substr(trim(c.c_state_d), 1, 2);

BEGIN TRANSACTION;

UPDATE customer
SET c_state_b = (
  SELECT us.code || '-' || us.name
  FROM us_states us
  WHERE us.code = upper(trim(
    CASE
      WHEN instr(trim(c_state_b), '-') > 0 THEN substr(trim(c_state_b), 1, instr(trim(c_state_b), '-') - 1)
      ELSE trim(c_state_b)
    END
  ))
  OR lower(trim(c_state_b)) = lower(us.name)
  LIMIT 1
)
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c_state_b, '')) NOT IN ('', '-')
  AND (
    SELECT us.code || '-' || us.name
    FROM us_states us
    WHERE us.code = upper(trim(
      CASE
        WHEN instr(trim(c_state_b), '-') > 0 THEN substr(trim(c_state_b), 1, instr(trim(c_state_b), '-') - 1)
        ELSE trim(c_state_b)
      END
    ))
    OR lower(trim(c_state_b)) = lower(us.name)
    LIMIT 1
  ) IS NOT NULL
  AND c_state_b != (
    SELECT us.code || '-' || us.name
    FROM us_states us
    WHERE us.code = upper(trim(
      CASE
        WHEN instr(trim(c_state_b), '-') > 0 THEN substr(trim(c_state_b), 1, instr(trim(c_state_b), '-') - 1)
        ELSE trim(c_state_b)
      END
    ))
    OR lower(trim(c_state_b)) = lower(us.name)
    LIMIT 1
  );

SELECT 'UPDATED_US_BILLING_STATE_TO_ST_DASH_NAME_ROWS' AS metric, changes() AS count;

UPDATE customer
SET c_state_d = (
  SELECT us.code || '-' || us.name
  FROM us_states us
  WHERE us.code = upper(trim(
    CASE
      WHEN instr(trim(c_state_d), '-') > 0 THEN substr(trim(c_state_d), 1, instr(trim(c_state_d), '-') - 1)
      ELSE trim(c_state_d)
    END
  ))
  OR lower(trim(c_state_d)) = lower(us.name)
  LIMIT 1
)
WHERE lower(trim(coalesce(c_country_d_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c_state_d, '')) NOT IN ('', '-')
  AND (
    SELECT us.code || '-' || us.name
    FROM us_states us
    WHERE us.code = upper(trim(
      CASE
        WHEN instr(trim(c_state_d), '-') > 0 THEN substr(trim(c_state_d), 1, instr(trim(c_state_d), '-') - 1)
        ELSE trim(c_state_d)
      END
    ))
    OR lower(trim(c_state_d)) = lower(us.name)
    LIMIT 1
  ) IS NOT NULL
  AND c_state_d != (
    SELECT us.code || '-' || us.name
    FROM us_states us
    WHERE us.code = upper(trim(
      CASE
        WHEN instr(trim(c_state_d), '-') > 0 THEN substr(trim(c_state_d), 1, instr(trim(c_state_d), '-') - 1)
        ELSE trim(c_state_d)
      END
    ))
    OR lower(trim(c_state_d)) = lower(us.name)
    LIMIT 1
  );

SELECT 'UPDATED_US_DELIVERY_STATE_TO_ST_DASH_NAME_ROWS' AS metric, changes() AS count;

UPDATE customer
SET c_city_b =
  trim(
    CASE
      WHEN substr(trim(c_city_b), -4) GLOB ', [A-Za-z][A-Za-z]'
        THEN substr(trim(c_city_b), 1, length(trim(c_city_b)) - 4)
      ELSE trim(c_city_b)
    END
  ) || ', ' || upper(substr(trim(c_state_b), 1, 2))
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c_state_b, '')) LIKE '__-%'
  AND trim(coalesce(c_city_b, '')) NOT IN ('', '-')
  AND trim(c_city_b) != (
    trim(
      CASE
        WHEN substr(trim(c_city_b), -4) GLOB ', [A-Za-z][A-Za-z]'
          THEN substr(trim(c_city_b), 1, length(trim(c_city_b)) - 4)
        ELSE trim(c_city_b)
      END
    ) || ', ' || upper(substr(trim(c_state_b), 1, 2))
  );

SELECT 'UPDATED_US_BILLING_CITY_TO_CITY_COMMA_ST_ROWS' AS metric, changes() AS count;

UPDATE customer
SET c_city_d =
  trim(
    CASE
      WHEN substr(trim(c_city_d), -4) GLOB ', [A-Za-z][A-Za-z]'
        THEN substr(trim(c_city_d), 1, length(trim(c_city_d)) - 4)
      ELSE trim(c_city_d)
    END
  ) || ', ' || upper(substr(trim(c_state_d), 1, 2))
WHERE lower(trim(coalesce(c_country_d_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c_state_d, '')) LIKE '__-%'
  AND trim(coalesce(c_city_d, '')) NOT IN ('', '-')
  AND trim(c_city_d) != (
    trim(
      CASE
        WHEN substr(trim(c_city_d), -4) GLOB ', [A-Za-z][A-Za-z]'
          THEN substr(trim(c_city_d), 1, length(trim(c_city_d)) - 4)
        ELSE trim(c_city_d)
      END
    ) || ', ' || upper(substr(trim(c_state_d), 1, 2))
  );

SELECT 'UPDATED_US_DELIVERY_CITY_TO_CITY_COMMA_ST_ROWS' AS metric, changes() AS count;

COMMIT;

SELECT 'AFTER_US_BILLING_STATE_NOT_ST_DASH_NAME' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_b_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c.c_state_b, '')) NOT IN ('', '-')
  AND trim(coalesce(c.c_state_b, '')) NOT LIKE '__-%';

SELECT 'AFTER_US_DELIVERY_STATE_NOT_ST_DASH_NAME' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_d_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c.c_state_d, '')) NOT IN ('', '-')
  AND trim(coalesce(c.c_state_d, '')) NOT LIKE '__-%';

SELECT 'AFTER_US_BILLING_CITY_MISSING_SUFFIX' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_b_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c.c_state_b, '')) LIKE '__-%'
  AND trim(coalesce(c.c_city_b, '')) NOT IN ('', '-')
  AND trim(c.c_city_b) NOT LIKE '%,' || ' ' || substr(trim(c.c_state_b), 1, 2);

SELECT 'AFTER_US_DELIVERY_CITY_MISSING_SUFFIX' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_d_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
  AND trim(coalesce(c.c_state_d, '')) LIKE '__-%'
  AND trim(coalesce(c.c_city_d, '')) NOT IN ('', '-')
  AND trim(c.c_city_d) NOT LIKE '%,' || ' ' || substr(trim(c.c_state_d), 1, 2);

SELECT c_id, c_city_b, c_state_b, c_city_d, c_state_d
FROM customer
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('us', 'usa', 'united states', 'united states of america', 'vereinigte staaten')
LIMIT 10;

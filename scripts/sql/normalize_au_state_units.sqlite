-- Normalisiert australische Verwaltungseinheiten auf das Format: CODE-StateName
-- und fuellt leere Verwaltungseinheiten per City-/State-/PLZ-Heuristik.
--
-- Ausfuehrung:
--   sqlite3 /pfad/zur/arrow_ops.db < scripts/sql/normalize_au_state_units.sql

PRAGMA foreign_keys = ON;

CREATE TEMP TABLE IF NOT EXISTS au_states (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

DELETE FROM au_states;

INSERT INTO au_states(code, name) VALUES
('NSW','New South Wales'),
('VIC','Victoria'),
('QLD','Queensland'),
('SA','South Australia'),
('WA','Western Australia'),
('TAS','Tasmania'),
('NT','Northern Territory'),
('ACT','Australian Capital Territory');

SELECT 'BEFORE_AU_BILLING_STATE_NOT_CODE_DASH_NAME' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_b_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c.c_state_b, '')) NOT IN ('', '-')
  AND trim(coalesce(c.c_state_b, '')) NOT LIKE '__-%'
  AND trim(coalesce(c.c_state_b, '')) NOT LIKE '___-%';

SELECT 'BEFORE_AU_DELIVERY_STATE_NOT_CODE_DASH_NAME' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_d_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c.c_state_d, '')) NOT IN ('', '-')
  AND trim(coalesce(c.c_state_d, '')) NOT LIKE '__-%'
  AND trim(coalesce(c.c_state_d, '')) NOT LIKE '___-%';

SELECT 'BEFORE_AU_BILLING_STATE_UNRESOLVED' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_b_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c.c_state_b, '')) IN ('', '-');

SELECT 'BEFORE_AU_DELIVERY_STATE_UNRESOLVED' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_d_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c.c_state_d, '')) IN ('', '-');

BEGIN TRANSACTION;

UPDATE customer
SET c_state_b = (
  SELECT au.code || '-' || au.name
  FROM au_states au
  WHERE au.code = upper(trim(
    CASE
      WHEN instr(trim(c_state_b), '-') > 0 THEN substr(trim(c_state_b), 1, instr(trim(c_state_b), '-') - 1)
      ELSE trim(c_state_b)
    END
  ))
  OR lower(trim(c_state_b)) = lower(au.name)
  LIMIT 1
)
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c_state_b, '')) NOT IN ('', '-')
  AND (
    SELECT au.code || '-' || au.name
    FROM au_states au
    WHERE au.code = upper(trim(
      CASE
        WHEN instr(trim(c_state_b), '-') > 0 THEN substr(trim(c_state_b), 1, instr(trim(c_state_b), '-') - 1)
        ELSE trim(c_state_b)
      END
    ))
    OR lower(trim(c_state_b)) = lower(au.name)
    LIMIT 1
  ) IS NOT NULL
  AND c_state_b != (
    SELECT au.code || '-' || au.name
    FROM au_states au
    WHERE au.code = upper(trim(
      CASE
        WHEN instr(trim(c_state_b), '-') > 0 THEN substr(trim(c_state_b), 1, instr(trim(c_state_b), '-') - 1)
        ELSE trim(c_state_b)
      END
    ))
    OR lower(trim(c_state_b)) = lower(au.name)
    LIMIT 1
  );

SELECT 'UPDATED_AU_BILLING_STATE_TO_CODE_DASH_NAME_ROWS' AS metric, changes() AS count;

UPDATE customer
SET c_state_d = (
  SELECT au.code || '-' || au.name
  FROM au_states au
  WHERE au.code = upper(trim(
    CASE
      WHEN instr(trim(c_state_d), '-') > 0 THEN substr(trim(c_state_d), 1, instr(trim(c_state_d), '-') - 1)
      ELSE trim(c_state_d)
    END
  ))
  OR lower(trim(c_state_d)) = lower(au.name)
  LIMIT 1
)
WHERE lower(trim(coalesce(c_country_d_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c_state_d, '')) NOT IN ('', '-')
  AND (
    SELECT au.code || '-' || au.name
    FROM au_states au
    WHERE au.code = upper(trim(
      CASE
        WHEN instr(trim(c_state_d), '-') > 0 THEN substr(trim(c_state_d), 1, instr(trim(c_state_d), '-') - 1)
        ELSE trim(c_state_d)
      END
    ))
    OR lower(trim(c_state_d)) = lower(au.name)
    LIMIT 1
  ) IS NOT NULL
  AND c_state_d != (
    SELECT au.code || '-' || au.name
    FROM au_states au
    WHERE au.code = upper(trim(
      CASE
        WHEN instr(trim(c_state_d), '-') > 0 THEN substr(trim(c_state_d), 1, instr(trim(c_state_d), '-') - 1)
        ELSE trim(c_state_d)
      END
    ))
    OR lower(trim(c_state_d)) = lower(au.name)
    LIMIT 1
  );

SELECT 'UPDATED_AU_DELIVERY_STATE_TO_CODE_DASH_NAME_ROWS' AS metric, changes() AS count;

UPDATE customer
SET c_state_b = (
  CASE
    WHEN lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '%new south wales%'
      OR lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '% nsw%'
      THEN 'NSW-New South Wales'
    WHEN lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '%queensland%'
      OR lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '% qld%'
      THEN 'QLD-Queensland'
    WHEN lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '%victoria%'
      OR lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '% vic%'
      THEN 'VIC-Victoria'
    WHEN lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '%western australia%'
      OR lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '% wa%'
      THEN 'WA-Western Australia'
    WHEN lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '%south australia%'
      OR lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '% sa%'
      OR upper(trim(coalesce(c_postal_code_b, ''))) LIKE 'SA%'
      THEN 'SA-South Australia'
    WHEN lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '%tasmania%'
      OR lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '% tas%'
      THEN 'TAS-Tasmania'
    WHEN lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '%northern territory%'
      OR lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '% nt%'
      THEN 'NT-Northern Territory'
    WHEN lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '%australian capital territory%'
      OR lower(coalesce(c_city_b, '') || ' ' || coalesce(c_postal_code_b, '') || ' ' || coalesce(c_state_b, '')) LIKE '% act%'
      THEN 'ACT-Australian Capital Territory'
    WHEN trim(coalesce(c_postal_code_b, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND (
        CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 1000 AND 2599
        OR CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 2619 AND 2899
        OR CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 2921 AND 2999
      )
      THEN 'NSW-New South Wales'
    WHEN trim(coalesce(c_postal_code_b, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND (
        CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 200 AND 299
        OR CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 2600 AND 2618
        OR CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 2900 AND 2920
      )
      THEN 'ACT-Australian Capital Territory'
    WHEN trim(coalesce(c_postal_code_b, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND (
        CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 3000 AND 3999
        OR CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 8000 AND 8999
      )
      THEN 'VIC-Victoria'
    WHEN trim(coalesce(c_postal_code_b, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND (
        CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 4000 AND 4999
        OR CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 9000 AND 9999
      )
      THEN 'QLD-Queensland'
    WHEN trim(coalesce(c_postal_code_b, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 5000 AND 5999
      THEN 'SA-South Australia'
    WHEN trim(coalesce(c_postal_code_b, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 6000 AND 6999
      THEN 'WA-Western Australia'
    WHEN trim(coalesce(c_postal_code_b, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 7000 AND 7999
      THEN 'TAS-Tasmania'
    WHEN trim(coalesce(c_postal_code_b, '')) GLOB '[0-9][0-9][0-9]*'
      AND CAST(trim(c_postal_code_b) AS INTEGER) BETWEEN 800 AND 999
      THEN 'NT-Northern Territory'
    ELSE c_state_b
  END
)
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c_state_b, '')) IN ('', '-');

SELECT 'UPDATED_AU_BILLING_STATE_FROM_HEURISTICS_ROWS' AS metric, changes() AS count;

UPDATE customer
SET c_state_d = (
  CASE
    WHEN lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '%new south wales%'
      OR lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '% nsw%'
      THEN 'NSW-New South Wales'
    WHEN lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '%queensland%'
      OR lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '% qld%'
      THEN 'QLD-Queensland'
    WHEN lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '%victoria%'
      OR lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '% vic%'
      THEN 'VIC-Victoria'
    WHEN lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '%western australia%'
      OR lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '% wa%'
      THEN 'WA-Western Australia'
    WHEN lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '%south australia%'
      OR lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '% sa%'
      OR upper(trim(coalesce(c_postal_code_d, ''))) LIKE 'SA%'
      THEN 'SA-South Australia'
    WHEN lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '%tasmania%'
      OR lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '% tas%'
      THEN 'TAS-Tasmania'
    WHEN lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '%northern territory%'
      OR lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '% nt%'
      THEN 'NT-Northern Territory'
    WHEN lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '%australian capital territory%'
      OR lower(coalesce(c_city_d, '') || ' ' || coalesce(c_postal_code_d, '') || ' ' || coalesce(c_state_d, '')) LIKE '% act%'
      THEN 'ACT-Australian Capital Territory'
    WHEN trim(coalesce(c_postal_code_d, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND (
        CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 1000 AND 2599
        OR CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 2619 AND 2899
        OR CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 2921 AND 2999
      )
      THEN 'NSW-New South Wales'
    WHEN trim(coalesce(c_postal_code_d, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND (
        CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 200 AND 299
        OR CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 2600 AND 2618
        OR CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 2900 AND 2920
      )
      THEN 'ACT-Australian Capital Territory'
    WHEN trim(coalesce(c_postal_code_d, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND (
        CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 3000 AND 3999
        OR CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 8000 AND 8999
      )
      THEN 'VIC-Victoria'
    WHEN trim(coalesce(c_postal_code_d, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND (
        CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 4000 AND 4999
        OR CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 9000 AND 9999
      )
      THEN 'QLD-Queensland'
    WHEN trim(coalesce(c_postal_code_d, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 5000 AND 5999
      THEN 'SA-South Australia'
    WHEN trim(coalesce(c_postal_code_d, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 6000 AND 6999
      THEN 'WA-Western Australia'
    WHEN trim(coalesce(c_postal_code_d, '')) GLOB '[0-9][0-9][0-9][0-9]*'
      AND CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 7000 AND 7999
      THEN 'TAS-Tasmania'
    WHEN trim(coalesce(c_postal_code_d, '')) GLOB '[0-9][0-9][0-9]*'
      AND CAST(trim(c_postal_code_d) AS INTEGER) BETWEEN 800 AND 999
      THEN 'NT-Northern Territory'
    ELSE c_state_d
  END
)
WHERE lower(trim(coalesce(c_country_d_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c_state_d, '')) IN ('', '-');

SELECT 'UPDATED_AU_DELIVERY_STATE_FROM_HEURISTICS_ROWS' AS metric, changes() AS count;

COMMIT;

SELECT 'AFTER_AU_BILLING_STATE_NOT_CODE_DASH_NAME' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_b_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c.c_state_b, '')) NOT IN ('', '-')
  AND trim(coalesce(c.c_state_b, '')) NOT LIKE '__-%'
  AND trim(coalesce(c.c_state_b, '')) NOT LIKE '___-%';

SELECT 'AFTER_AU_DELIVERY_STATE_NOT_CODE_DASH_NAME' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_d_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c.c_state_d, '')) NOT IN ('', '-')
  AND trim(coalesce(c.c_state_d, '')) NOT LIKE '__-%'
  AND trim(coalesce(c.c_state_d, '')) NOT LIKE '___-%';

SELECT 'AFTER_AU_BILLING_STATE_UNRESOLVED' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_b_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c.c_state_b, '')) IN ('', '-');

SELECT 'AFTER_AU_DELIVERY_STATE_UNRESOLVED' AS metric, COUNT(*) AS count
FROM customer c
WHERE lower(trim(coalesce(c.c_country_d_id, ''))) IN ('au', 'australia', 'australien')
  AND trim(coalesce(c.c_state_d, '')) IN ('', '-');

SELECT c_state_b AS state, COUNT(*) AS count
FROM customer
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('au', 'australia', 'australien')
GROUP BY c_state_b
ORDER BY count DESC;

SELECT c_state_d AS state, COUNT(*) AS count
FROM customer
WHERE lower(trim(coalesce(c_country_d_id, ''))) IN ('au', 'australia', 'australien')
GROUP BY c_state_d
ORDER BY count DESC;

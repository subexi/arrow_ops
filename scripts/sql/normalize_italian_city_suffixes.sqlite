-- Normalisiert italienische Stadtfelder auf das Format: Stadtname (XX)
-- wobei XX aus der Verwaltungseinheit XX-... in c_state_b/c_state_d stammt.
--
-- Ausfuehrung:
--   sqlite3 /pfad/zur/arrow_ops.db < scripts/sql/normalize_italian_city_suffixes.sql

PRAGMA foreign_keys = ON;

-- Vorher-Check: Billing ohne korrektes Suffix
SELECT 'BEFORE_BILLING_MISSING_SUFFIX' AS metric, COUNT(*) AS count
FROM customer
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('it', 'italy', 'italien')
  AND trim(coalesce(c_state_b, '')) LIKE '__-%'
  AND trim(coalesce(c_city_b, '')) NOT IN ('', '-')
  AND trim(c_city_b) NOT LIKE '% (' || substr(trim(c_state_b), 1, 2) || ')';

-- Vorher-Check: Delivery ohne korrektes Suffix
SELECT 'BEFORE_DELIVERY_MISSING_SUFFIX' AS metric, COUNT(*) AS count
FROM customer
WHERE lower(trim(coalesce(c_country_d_id, ''))) IN ('it', 'italy', 'italien')
  AND trim(coalesce(c_state_d, '')) LIKE '__-%'
  AND trim(coalesce(c_city_d, '')) NOT IN ('', '-')
  AND trim(c_city_d) NOT LIKE '% (' || substr(trim(c_state_d), 1, 2) || ')';

BEGIN TRANSACTION;

-- Billing normalisieren: optional vorhandenes End-Suffix (YY) entfernen, dann (XX) aus c_state_b anhaengen.
UPDATE customer
SET c_city_b =
  trim(
    CASE
      WHEN substr(trim(c_city_b), -5) GLOB ' ([A-Za-z][A-Za-z])'
        THEN substr(trim(c_city_b), 1, length(trim(c_city_b)) - 5)
      ELSE trim(c_city_b)
    END
  ) || ' (' || upper(substr(trim(c_state_b), 1, 2)) || ')'
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('it', 'italy', 'italien')
  AND trim(coalesce(c_state_b, '')) LIKE '__-%'
  AND trim(coalesce(c_city_b, '')) NOT IN ('', '-')
  AND trim(c_city_b) != (
    trim(
      CASE
        WHEN substr(trim(c_city_b), -5) GLOB ' ([A-Za-z][A-Za-z])'
          THEN substr(trim(c_city_b), 1, length(trim(c_city_b)) - 5)
        ELSE trim(c_city_b)
      END
    ) || ' (' || upper(substr(trim(c_state_b), 1, 2)) || ')'
  );

SELECT 'UPDATED_BILLING_ROWS' AS metric, changes() AS count;

-- Delivery normalisieren: optional vorhandenes End-Suffix (YY) entfernen, dann (XX) aus c_state_d anhaengen.
UPDATE customer
SET c_city_d =
  trim(
    CASE
      WHEN substr(trim(c_city_d), -5) GLOB ' ([A-Za-z][A-Za-z])'
        THEN substr(trim(c_city_d), 1, length(trim(c_city_d)) - 5)
      ELSE trim(c_city_d)
    END
  ) || ' (' || upper(substr(trim(c_state_d), 1, 2)) || ')'
WHERE lower(trim(coalesce(c_country_d_id, ''))) IN ('it', 'italy', 'italien')
  AND trim(coalesce(c_state_d, '')) LIKE '__-%'
  AND trim(coalesce(c_city_d, '')) NOT IN ('', '-')
  AND trim(c_city_d) != (
    trim(
      CASE
        WHEN substr(trim(c_city_d), -5) GLOB ' ([A-Za-z][A-Za-z])'
          THEN substr(trim(c_city_d), 1, length(trim(c_city_d)) - 5)
        ELSE trim(c_city_d)
      END
    ) || ' (' || upper(substr(trim(c_state_d), 1, 2)) || ')'
  );

SELECT 'UPDATED_DELIVERY_ROWS' AS metric, changes() AS count;

COMMIT;

-- Nachher-Check: Billing ohne korrektes Suffix
SELECT 'AFTER_BILLING_MISSING_SUFFIX' AS metric, COUNT(*) AS count
FROM customer
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('it', 'italy', 'italien')
  AND trim(coalesce(c_state_b, '')) LIKE '__-%'
  AND trim(coalesce(c_city_b, '')) NOT IN ('', '-')
  AND trim(c_city_b) NOT LIKE '% (' || substr(trim(c_state_b), 1, 2) || ')';

-- Nachher-Check: Delivery ohne korrektes Suffix
SELECT 'AFTER_DELIVERY_MISSING_SUFFIX' AS metric, COUNT(*) AS count
FROM customer
WHERE lower(trim(coalesce(c_country_d_id, ''))) IN ('it', 'italy', 'italien')
  AND trim(coalesce(c_state_d, '')) LIKE '__-%'
  AND trim(coalesce(c_city_d, '')) NOT IN ('', '-')
  AND trim(c_city_d) NOT LIKE '% (' || substr(trim(c_state_d), 1, 2) || ')';

-- Stichprobe
SELECT c_id, c_city_b, c_state_b, c_city_d, c_state_d
FROM customer
WHERE lower(trim(coalesce(c_country_b_id, ''))) IN ('it', 'italy', 'italien')
  AND trim(coalesce(c_state_b, '')) LIKE '__-%'
LIMIT 10;

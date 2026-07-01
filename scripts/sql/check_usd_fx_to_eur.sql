-- Release/Migration check for order currency normalization (USD -> EUR rate)
-- Usage example:
--   sqlite3 -header -column /path/to/arrow_ops.db < scripts/sql/check_usd_fx_to_eur.sql

SELECT 'schema_has_o_fx_to_eur' AS check_name,
       CASE
         WHEN EXISTS (
           SELECT 1
           FROM pragma_table_info('order')
           WHERE name = 'o_fx_to_eur'
         ) THEN 'OK'
         ELSE 'MISSING'
       END AS result;

SELECT 'usd_orders_total' AS check_name,
       COUNT(*) AS value
FROM "order"
WHERE UPPER(TRIM(COALESCE(o_currency, 'EUR'))) = 'USD';

SELECT 'usd_orders_missing_fx' AS check_name,
       COUNT(*) AS value
FROM "order"
WHERE UPPER(TRIM(COALESCE(o_currency, 'EUR'))) = 'USD'
  AND COALESCE(o_fx_to_eur, 0) <= 0;

SELECT 'usd_orders_with_fx' AS check_name,
       COUNT(*) AS value
FROM "order"
WHERE UPPER(TRIM(COALESCE(o_currency, 'EUR'))) = 'USD'
  AND COALESCE(o_fx_to_eur, 0) > 0;

SELECT o_id,
       o_date,
       o_delivery,
       o_currency,
       o_fx_to_eur,
       o_price_basis,
       o_total_price
FROM "order"
WHERE UPPER(TRIM(COALESCE(o_currency, 'EUR'))) = 'USD'
  AND COALESCE(o_fx_to_eur, 0) <= 0
ORDER BY o_date, o_id;

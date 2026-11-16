-- Point de contrôle de la partie B : vos compteurs du 10 au 30 septembre comparés à ceux que le
-- service lit aujourd'hui dans les fichiers parquet. Attendu : 0 et 0.
-- Remplacez team1 par le nom de votre dataset.
SELECT 'client' AS compteurs, COUNT(*) AS lignes_differentes FROM (
  SELECT customer_id, day, n, ROUND(amount_sum, 2) AS amount_sum FROM `team1.customer_daily` WHERE day <= '2026-09-30'
  EXCEPT DISTINCT
  SELECT customer_id, day, n, ROUND(amount_sum, 2) AS amount_sum FROM `fraudfinder.ref_customer_daily`
)
UNION ALL
SELECT 'terminal', COUNT(*) FROM (
  SELECT terminal_id, day, n, n_fraud FROM `team1.terminal_daily` WHERE day <= '2026-09-30'
  EXCEPT DISTINCT
  SELECT terminal_id, day, n, n_fraud FROM `fraudfinder.ref_terminal_daily`
);

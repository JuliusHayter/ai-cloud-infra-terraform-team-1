-- Séance 4, partie B : compteurs par client et par jour.
-- Remplacez team1 par le nom de votre dataset. Trois trous, repérés par "À COMPLÉTER".
CREATE OR REPLACE TABLE `team1.customer_daily` AS
WITH flux AS (
  -- Votre historique, une seule ligne par transaction même si Pub/Sub l'a livrée deux fois.
  SELECT
    TX_ID,
    ANY_VALUE(TX_TS) AS TX_TS,
    ANY_VALUE(CUSTOMER_ID) AS CUSTOMER_ID,
    ANY_VALUE(TX_AMOUNT) AS TX_AMOUNT
  FROM `team1.tx_history`
  WHERE TX_TS >= TIMESTAMP '2026-10-01'
  -- À COMPLÉTER (a) : GROUP BY, la colonne qui identifie une transaction.
),
tx AS (
  -- Le passé fourni par le socle, puis votre flux.
  SELECT TX_TS, CUSTOMER_ID, TX_AMOUNT
  FROM `fraudfinder.tx_seed`
  WHERE TX_TS >= TIMESTAMP '2026-09-10'
  -- À COMPLÉTER (b) : réunir avec les mêmes trois colonnes de flux (UNION ALL).
)
SELECT
  CUSTOMER_ID AS customer_id,
  DATE(TX_TS) AS day,
  -- À COMPLÉTER (c) : n, le nombre de transactions, et amount_sum, la somme des montants.
FROM tx
GROUP BY customer_id, day;

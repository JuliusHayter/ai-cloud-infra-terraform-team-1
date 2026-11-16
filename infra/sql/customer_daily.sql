-- Séance 4, partie B : compteurs par client et par jour.
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
  GROUP BY TX_ID -- (a) une ligne par transaction
),
tx AS (
  -- Le passé fourni par le socle, puis votre flux.
  SELECT TX_TS, CUSTOMER_ID, TX_AMOUNT
  FROM `fraudfinder.tx_seed`
  WHERE TX_TS >= TIMESTAMP '2026-09-10'
  UNION ALL -- (b) mêmes trois colonnes, même ordre
  SELECT TX_TS, CUSTOMER_ID, TX_AMOUNT
  FROM flux
)
SELECT
  CUSTOMER_ID AS customer_id,
  DATE(TX_TS) AS day,
  COUNT(*) AS n,               -- (c) nombre de transactions
  SUM(TX_AMOUNT) AS amount_sum -- (c) somme des montants
FROM tx
GROUP BY customer_id, day;

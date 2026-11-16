"""Copie les compteurs journaliers de BigQuery vers Firestore : un document par entité.

uv run tools/publish_features.py --project advanced-cloud-ai --dataset team1 --database team1

Chaque document contient les 28 derniers jours de compteurs : {"days": {"2026-09-30": [n, valeur]}}.
"""

from __future__ import annotations

import argparse
import time

from google.cloud import bigquery, firestore

DAYS = 28
QUERY = """
SELECT
  {key} AS id,
  ARRAY_AGG(STRUCT(CAST(day AS STRING) AS day, n, CAST({value} AS FLOAT64) AS v)) AS days
FROM `{dataset}.{table}`
WHERE day > DATE_SUB((SELECT MAX(day) FROM `{dataset}.{table}`), INTERVAL {days} DAY)
GROUP BY id
"""
TABLES = (
    ("customers", "customer_daily", "customer_id", "amount_sum"),
    ("terminals", "terminal_daily", "terminal_id", "n_fraud"),
)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--project", required=True)
    ap.add_argument("--dataset", required=True, help="dataset BigQuery de l'équipe")
    ap.add_argument("--database", required=True, help="base Firestore de l'équipe")
    ap.add_argument("--location", default="europe-west1")
    a = ap.parse_args(argv)

    bq = bigquery.Client(project=a.project, location=a.location)
    db = firestore.Client(project=a.project, database=a.database)
    for collection, table, key, value in TABLES:
        start = time.perf_counter()
        query = QUERY.format(
            key=key, value=value, dataset=f"{a.project}.{a.dataset}", table=table, days=DAYS
        )
        writer, written = db.bulk_writer(), 0
        for row in bq.query(query).result():
            doc = {"days": {d["day"]: [d["n"], d["v"]] for d in row.days}}
            writer.set(db.collection(collection).document(row.id), doc)
            written += 1
        writer.close()
        print(
            f"{collection}: {written:,} documents en {time.perf_counter() - start:.0f} s",
            flush=True,
        )


if __name__ == "__main__":
    main()

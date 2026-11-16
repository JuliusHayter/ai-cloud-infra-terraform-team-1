"""Séance 4, partie D : justificatifs KYC dans une base vectorielle (Qdrant), index HNSW.

RUN="uv run --with httpx --with pyarrow --with numpy docs/seance-4/kyc_vectors.py"
$RUN load --url $VURL --m 16
$RUN measure --url $VURL
$RUN neighbours --url $VURL --doc-id 0

Le jeton d'appel est lu dans la variable d'environnement TOKEN (gcloud auth print-identity-token).
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import time

import httpx
import numpy as np
import pyarrow.parquet as pq

COLLECTION = "kyc"
QUERIES, TOP_K, SEED = 300, 10, 20261116


def client(url: str) -> httpx.Client:
    token = os.environ.get("TOKEN")
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    return httpx.Client(base_url=url.rstrip("/"), headers=headers, timeout=120)


def call(http: httpx.Client, method: str, path: str, **kwargs) -> dict:
    resp = http.request(method, path, **kwargs)
    if resp.status_code >= 400:
        raise SystemExit(f"{method} {path} : HTTP {resp.status_code} {resp.text[:300]}")
    return resp.json()


def vectors(path: str) -> np.ndarray:
    column = pq.read_table(path, columns=["embedding"])["embedding"].combine_chunks()
    return column.values.to_numpy().reshape(len(column), -1)


def load(a) -> None:
    table = pq.read_table(a.file)
    emb = vectors(a.file)
    payloads = table.select(["customer_id", "doc_type", "text"]).to_pylist()
    http = client(a.url)
    http.delete(f"/collections/{COLLECTION}")
    call(
        http,
        "PUT",
        f"/collections/{COLLECTION}",
        json={
            "vectors": {"size": emb.shape[1], "distance": "Cosine"},
            "hnsw_config": {"m": a.m, "ef_construct": a.ef_construct},
            "optimizers_config": {"default_segment_number": 1, "indexing_threshold": 0},
        },
    )
    start = time.perf_counter()
    for lo in range(0, len(emb), a.batch):
        hi = min(lo + a.batch, len(emb))
        batch = {
            "ids": list(range(lo, hi)),
            "vectors": np.round(emb[lo:hi].astype(float), 4).tolist(),
            "payloads": payloads[lo:hi],
        }
        call(
            http,
            "PUT",
            f"/collections/{COLLECTION}/points?wait=true",
            content=gzip.compress(json.dumps({"batch": batch}).encode()),
            headers={"Content-Type": "application/json", "Content-Encoding": "gzip"},
        )
        print(f"\r{hi:,} / {len(emb):,} documents envoyés", end="", flush=True)
    print(f" en {time.perf_counter() - start:.0f} s")
    call(
        http,
        "PATCH",
        f"/collections/{COLLECTION}",
        json={"optimizers_config": {"indexing_threshold": 1000}},
    )
    while True:
        info = call(http, "GET", f"/collections/{COLLECTION}")["result"]
        indexed = info.get("indexed_vectors_count") or 0
        print(
            f"\rindex HNSW : {indexed:,} vecteurs, état {info['status']}   ",
            end="",
            flush=True,
        )
        if info["status"] == "green" and indexed >= 0.95 * len(emb):
            break
        time.sleep(2)
    elapsed = time.perf_counter() - start
    print(
        f"\nindex construit en {elapsed:.0f} s (m={a.m}, ef_construct={a.ef_construct})"
    )


def search(http: httpx.Client, vector, params: dict) -> tuple[list[int], float]:
    body = {"vector": vector, "limit": TOP_K, "params": params}
    out = call(http, "POST", f"/collections/{COLLECTION}/points/search", json=body)
    return [p["id"] for p in out["result"]], out["time"] * 1000


def measure(a) -> None:
    emb = vectors(a.file)
    queries = emb[
        np.random.default_rng(SEED).choice(len(emb), QUERIES, replace=False)
    ].tolist()
    http = client(a.url)
    exact, exact_ms = zip(
        *(search(http, q, {"exact": True}) for q in queries), strict=True
    )
    print(f"{QUERIES} requêtes, {TOP_K} voisins, temps mesuré par le serveur\n")
    print("| ef | rappel@10 | p50 (ms) | p95 (ms) |")
    print("| --- | --- | --- | --- |")
    row = "| {} | {:.3f} | {:.2f} | {:.2f} |"
    print(
        row.format(
            "exact", 1.0, np.percentile(exact_ms, 50), np.percentile(exact_ms, 95)
        )
    )
    for ef in a.ef:
        found, ms = zip(
            *(search(http, q, {"hnsw_ef": ef}) for q in queries), strict=True
        )
        recall = np.mean(
            [len(set(f) & set(e)) / TOP_K for f, e in zip(found, exact, strict=True)]
        )
        print(row.format(ef, recall, np.percentile(ms, 50), np.percentile(ms, 95)))


def neighbours(a) -> None:
    http = client(a.url)
    body = {"ids": [a.doc_id], "with_vector": True, "with_payload": True}
    doc = call(http, "POST", f"/collections/{COLLECTION}/points", json=body)["result"][
        0
    ]
    print(
        f"document {a.doc_id}, client {doc['payload']['customer_id']} : {doc['payload']['text']}\n"
    )
    body = {"vector": doc["vector"], "limit": 6, "with_payload": True}
    out = call(http, "POST", f"/collections/{COLLECTION}/points/search", json=body)
    for p in out["result"]:
        if p["id"] != a.doc_id:
            pay = p["payload"]
            print(f"{p['score']:.4f}  client {pay['customer_id']}  {pay['text']}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    sub = ap.add_subparsers(dest="command", required=True)
    for name, fn in (("load", load), ("measure", measure), ("neighbours", neighbours)):
        p = sub.add_parser(name)
        p.add_argument("--url", required=True, help="URL du service Qdrant")
        p.add_argument("--file", default="kyc_embeddings.parquet")
        p.set_defaults(fn=fn)
        if name == "load":
            p.add_argument("--m", type=int, default=16, help="liens par nœud du graphe")
            p.add_argument("--ef-construct", type=int, default=100)
            p.add_argument("--batch", type=int, default=1000)
        if name == "measure":
            p.add_argument(
                "--ef", type=int, nargs="+", default=[4, 8, 16, 32, 64, 128, 256]
            )
        if name == "neighbours":
            p.add_argument("--doc-id", type=int, required=True)
    a = ap.parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()

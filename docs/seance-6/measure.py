"""Mesure par révision Cloud Run à partir des logs structurés du service de scoring.

python3 tools/measure.py --service team1-scorer --minutes 5
python3 tools/measure.py --service team1-scorer \
    --compare team1-scorer-00001-abc team1-scorer-00002-def
python3 tools/measure.py --service team1-scorer --file logs.jsonl

Bibliothèque standard seulement : `gcloud` doit être installé et authentifié.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time

DELIVERIES = ("scored", "failed", "rejected")
ERRORS = ("failed", "rejected")
LIMIT_PER_MINUTE = 1500
DEFAULT_PROJECT = "advanced-cloud-ai"
QUOTA_WAITS = (20, 40, 60)
QUOTA_MARKERS = ("429", "resource_exhausted", "quota exceeded")
COLUMNS = (
    ("révision", None),
    ("n", "n"),
    ("tx distinctes", "tx_distinctes"),
    ("erreurs", "erreurs_pct"),
    ("alertes", "alertes_pct"),
    ("score moyen", "score_moyen"),
    ("p50 ms", "p50_ms"),
    ("p95 ms", "p95_ms"),
    ("dégradés", "degrade_pct"),
)
PERCENT_KEYS = {"erreurs_pct", "alertes_pct", "degrade_pct", "desaccord_pct"}


class MeasureError(Exception):
    pass


def limit_for(minutes: float) -> int:
    return max(1, int(LIMIT_PER_MINUTE * minutes))


def _normalize(raw: dict) -> dict | None:
    payload = raw.get("jsonPayload")
    if isinstance(payload, dict):
        entry = dict(payload)
        entry.setdefault("timestamp", raw.get("timestamp", ""))
        if not entry.get("revision"):
            labels = (raw.get("resource") or {}).get("labels") or {}
            entry["revision"] = labels.get("revision_name")
    else:
        entry = dict(raw)
    if entry.get("message") not in DELIVERIES:
        return None
    entry["sans_revision"] = not entry.get("revision")
    entry["revision"] = entry.get("revision") or "inconnue"
    entry["shadow"] = bool(entry.get("shadow"))
    entry["timestamp"] = str(entry.get("timestamp") or "")
    return entry


def _normalized(entries: list[dict]) -> list[dict]:
    kept = [e for e in map(_normalize, entries) if e is not None]
    return sorted(kept, key=lambda e: e["timestamp"])


def count_without_revision(entries: list[dict]) -> int:
    return sum(1 for e in _normalized(entries) if e["sans_revision"])


def _percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    pos = (len(ordered) - 1) * q
    low = int(pos)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (pos - low)


def _share(count: int, total: int) -> float | None:
    return count / total * 100 if total else None


def _row(entries: list[dict]) -> dict:
    scored = [e for e in entries if e["message"] == "scored"]
    errors = [e for e in entries if e["message"] in ERRORS]
    last = {e.get("tx_id"): e for e in scored}
    scores = [e["score"] for e in scored if e.get("score") is not None]
    latencies = [e["latency_ms"] for e in scored if e.get("latency_ms") is not None]
    return {
        "n": len(entries),
        "tx_distinctes": len(last),
        "erreurs_pct": _share(len(errors), len(entries)),
        "alertes_pct": _share(sum(1 for e in last.values() if e.get("decision")), len(last)),
        "score_moyen": sum(scores) / len(scores) if scores else None,
        "p50_ms": _percentile(latencies, 0.5),
        "p95_ms": _percentile(latencies, 0.95),
        "degrade_pct": _share(sum(1 for e in scored if e.get("degraded")), len(scored)),
    }


def summarize(
    entries: list[dict], shadow: bool = False, revisions: list[str] | None = None
) -> dict[str, dict]:
    by_revision: dict[str, list[dict]] = {name: [] for name in revisions or []}
    for entry in _normalized(entries):
        if entry["shadow"] == shadow:
            by_revision.setdefault(entry["revision"], []).append(entry)
    return {name: _row(group) for name, group in by_revision.items()}


def compare(entries: list[dict], rev_a: str, rev_b: str) -> dict:
    decisions: dict[str, dict[str, bool]] = {rev_a: {}, rev_b: {}}
    for entry in _normalized(entries):
        if entry["message"] == "scored" and entry["revision"] in decisions:
            decisions[entry["revision"]][entry.get("tx_id")] = bool(entry.get("decision"))
    common = decisions[rev_a].keys() & decisions[rev_b].keys()
    if not common:
        return {"n_communs": 0, "desaccord_pct": None, "ecart_alertes_points": None}
    a, b = decisions[rev_a], decisions[rev_b]
    return {
        "n_communs": len(common),
        "desaccord_pct": _share(sum(1 for t in common if a[t] != b[t]), len(common)),
        "ecart_alertes_points": _share(sum(b[t] for t in common), len(common))
        - _share(sum(a[t] for t in common), len(common)),
    }


def _fmt(value, key: str) -> str:
    if value is None:
        return "-"
    if key in ("n", "tx_distinctes", "n_communs"):
        return str(value)
    if key == "score_moyen":
        text = f"{value:.3f}"
    else:
        text = f"{value:.1f}"
    text = text.replace(".", ",")
    return f"{text} %" if key in PERCENT_KEYS else text


def render_table(rows: dict[str, dict]) -> str:
    lines = [
        "| " + " | ".join(title for title, _ in COLUMNS) + " |",
        "| " + " | ".join("---" for _ in COLUMNS) + " |",
    ]
    for name, row in rows.items():
        cells = [name, str(row["n"])] + [
            "-" if not row["n"] else _fmt(row[key], key) for _, key in COLUMNS[2:]
        ]
        lines.append("| " + " | ".join(cells) + " |")
    return "\n".join(lines)


def render_comparison(rev_a: str, rev_b: str, result: dict) -> str:
    return (
        f"Comparaison {rev_a} → {rev_b} : {_fmt(result['n_communs'], 'n_communs')} transactions "
        f"communes, désaccord {_fmt(result['desaccord_pct'], 'desaccord_pct')}, "
        f"écart d'alertes {_fmt(result['ecart_alertes_points'], 'ecart')} points"
    )


def read_logs(
    service: str,
    minutes: float,
    project: str = DEFAULT_PROJECT,
    runner=subprocess.run,
    now: float | None = None,
    sleep=None,
) -> list[dict]:
    since = (time.time() if now is None else now) - minutes * 60
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(since))
    flt = (
        'resource.type="cloud_run_revision" '
        f'AND resource.labels.service_name="{service}" '
        'AND jsonPayload.message=("scored" OR "failed" OR "rejected") '
        f'AND timestamp>="{stamp}"'
    )
    limit = limit_for(minutes)
    cmd = [
        "gcloud",
        "logging",
        "read",
        flt,
        f"--project={project}",
        "--format=json",
        f"--limit={limit}",
    ]
    waits = iter(QUOTA_WAITS)
    while True:
        try:
            done = runner(cmd, capture_output=True, text=True)
        except FileNotFoundError:
            raise MeasureError(
                "gcloud est introuvable : installez le SDK Google Cloud ou ouvrez Cloud Shell."
            ) from None
        if done.returncode == 0:
            break
        stderr = (done.stderr or "").strip()
        lowered = stderr.lower()
        if "active account" in lowered or "reauthentication" in lowered or "log in" in lowered:
            raise MeasureError(
                "gcloud n'est pas authentifié : lancez `gcloud auth login`, puis relancez."
            )
        if any(marker in lowered for marker in QUOTA_MARKERS):
            wait = next(waits, None)
            if wait is None:
                raise MeasureError("quota de lecture des logs atteint, relancez dans une minute.")
            print(
                f"Quota de lecture des logs atteint : nouvelle tentative dans {wait} s.",
                file=sys.stderr,
            )
            (sleep or time.sleep)(wait)
            continue
        raise MeasureError(f"gcloud logging read a échoué : {stderr or 'aucun détail'}")
    try:
        entries = json.loads(done.stdout or "[]")
    except json.JSONDecodeError as e:
        raise MeasureError(f"Réponse de gcloud illisible : {e}") from e
    return entries


def read_file(path: str) -> list[dict]:
    try:
        with open(path, encoding="utf-8") as f:
            lines = [line.strip() for line in f if line.strip()]
    except OSError as e:
        raise MeasureError(f"Lecture de {path} impossible : {e.strerror or e}") from e
    entries = []
    for number, line in enumerate(lines, 1):
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            raise MeasureError(f"{path} : une ligne n'est pas du JSON (entrée {number}).") from None
    return entries


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="Mesure par révision Cloud Run à partir des logs du service de scoring."
    )
    p.add_argument("--service", required=True, help="nom du service Cloud Run")
    p.add_argument("--minutes", type=float, default=5, help="fenêtre de lecture (défaut : 5)")
    p.add_argument(
        "--project", default=DEFAULT_PROJECT, help=f"projet (défaut : {DEFAULT_PROJECT})"
    )
    p.add_argument("--shadow", action="store_true", help="ne compter que les entrées d'ombre")
    p.add_argument(
        "--compare",
        nargs=2,
        metavar=("A", "B"),
        help=(
            "comparer les décisions de deux noms de révision Cloud Run "
            "(gcloud run revisions list), pas des tags"
        ),
    )
    p.add_argument(
        "--revisions",
        nargs="+",
        metavar="REV",
        help=(
            "noms de révision Cloud Run (gcloud run revisions list), pas des tags : "
            "affichés même sans log"
        ),
    )
    p.add_argument("--file", help="fichier JSONL à lire au lieu de gcloud")
    p.add_argument("--json", action="store_true", help="sortie JSON brute")
    return p


def main(argv: list[str] | None = None, runner=subprocess.run) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.file:
            entries = read_file(args.file)
        else:
            entries = read_logs(args.service, args.minutes, args.project, runner=runner)
    except MeasureError as e:
        print(f"Erreur : {e}", file=sys.stderr)
        return 2
    truncated = not args.file and len(entries) >= limit_for(args.minutes)
    orphans = count_without_revision(entries)
    wanted = list(args.revisions or [])
    if args.compare:
        wanted += [r for r in args.compare if r not in wanted]
    rows = summarize(entries, shadow=args.shadow, revisions=wanted)
    result = compare(entries, *args.compare) if args.compare else None
    if args.json:
        out = {"revisions": rows, "tronque": truncated, "sans_revision": orphans}
        if result is not None:
            out["comparaison"] = result
        print(json.dumps(out, ensure_ascii=False, indent=2))
        return 0
    print(render_table(rows) if rows else "Aucune livraison trouvée dans la fenêtre.")
    if result is not None:
        print()
        print(render_comparison(*args.compare, result))
    if truncated:
        print(
            f"\nAttention : la limite de {limit_for(args.minutes)} entrées est atteinte, les "
            "entrées les plus anciennes de la fenêtre manquent ; réduisez --minutes."
        )
    if orphans:
        print(f"\nAttention : {orphans} entrées sans révision, rangées sous « inconnue ».")
    return 0


if __name__ == "__main__":
    sys.exit(main())

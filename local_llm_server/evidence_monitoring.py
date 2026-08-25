from __future__ import annotations

import math
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Optional


SCHEMA = """
CREATE TABLE IF NOT EXISTS evidence_observations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    occurred_at TEXT NOT NULL,
    request_id TEXT NOT NULL,
    purpose TEXT NOT NULL,
    state TEXT NOT NULL,
    failure_type TEXT NOT NULL DEFAULT '',
    embedding_latency_ms REAL NOT NULL DEFAULT 0,
    search_latency_ms REAL NOT NULL DEFAULT 0,
    total_latency_ms REAL NOT NULL DEFAULT 0,
    searched_documents INTEGER NOT NULL DEFAULT 0,
    matched_documents INTEGER NOT NULL DEFAULT 0,
    prompt_characters INTEGER NOT NULL DEFAULT 0,
    estimated_cost_usd REAL NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_evidence_observations_occurred
ON evidence_observations(occurred_at);
"""


@dataclass(frozen=True)
class EvidenceObservation:
    request_id: str
    purpose: str
    state: str
    embedding_latency_ms: float = 0
    search_latency_ms: float = 0
    total_latency_ms: float = 0
    searched_documents: int = 0
    matched_documents: int = 0
    prompt_characters: int = 0
    estimated_cost_usd: float = 0
    failure_type: str = ""


class EvidenceMonitor:
    def __init__(self, path: Path, *, cost_per_million_characters: float = 0.0):
        self.path = path
        self.cost_per_million_characters = max(0.0, cost_per_million_characters)

    def connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(str(self.path), timeout=10)
        connection.row_factory = sqlite3.Row
        connection.execute("PRAGMA journal_mode = WAL")
        connection.executescript(SCHEMA)
        return connection

    def estimated_cost(self, prompt_characters: int) -> float:
        return round(
            max(0, prompt_characters) / 1_000_000 * self.cost_per_million_characters,
            8,
        )

    def record(self, observation: EvidenceObservation) -> None:
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO evidence_observations (
                    occurred_at, request_id, purpose, state, failure_type,
                    embedding_latency_ms, search_latency_ms, total_latency_ms,
                    searched_documents, matched_documents, prompt_characters,
                    estimated_cost_usd
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    datetime.now(timezone.utc).isoformat(),
                    observation.request_id,
                    observation.purpose,
                    observation.state,
                    observation.failure_type,
                    observation.embedding_latency_ms,
                    observation.search_latency_ms,
                    observation.total_latency_ms,
                    observation.searched_documents,
                    observation.matched_documents,
                    observation.prompt_characters,
                    observation.estimated_cost_usd,
                ),
            )

    def summary(self, *, days: int = 7, purpose: Optional[str] = None) -> dict[str, Any]:
        since = (datetime.now(timezone.utc) - timedelta(days=max(1, days))).isoformat()
        parameters: list[Any] = [since]
        purpose_clause = ""
        if purpose:
            purpose_clause = " AND purpose = ?"
            parameters.append(purpose)
        with self.connect() as connection:
            rows = connection.execute(
                f"SELECT * FROM evidence_observations WHERE occurred_at >= ?{purpose_clause}",
                parameters,
            ).fetchall()
        latencies = sorted(float(row["total_latency_ms"]) for row in rows)
        failures = [row for row in rows if row["failure_type"] or row["state"] == "unavailable"]
        matches = [row for row in rows if int(row["matched_documents"]) > 0]
        return {
            "window_days": max(1, days),
            "purpose": purpose or "all",
            "requests": len(rows),
            "successful_matches": len(matches),
            "match_rate": round(len(matches) / len(rows), 4) if rows else 0.0,
            "failures": len(failures),
            "failure_rate": round(len(failures) / len(rows), 4) if rows else 0.0,
            "latency_ms": {
                "p50": _percentile(latencies, 0.50),
                "p95": _percentile(latencies, 0.95),
                "maximum": round(max(latencies), 2) if latencies else 0.0,
            },
            "estimated_cost_usd": round(
                sum(float(row["estimated_cost_usd"]) for row in rows), 6
            ),
            "states": _counts(str(row["state"]) for row in rows),
            "failure_types": _counts(
                str(row["failure_type"]) for row in failures if row["failure_type"]
            ),
        }


def _percentile(values: list[float], percentile: float) -> float:
    if not values:
        return 0.0
    index = max(0, min(len(values) - 1, math.ceil(percentile * len(values)) - 1))
    return round(values[index], 2)


def _counts(values) -> dict[str, int]:
    result: dict[str, int] = {}
    for value in values:
        result[value] = result.get(value, 0) + 1
    return dict(sorted(result.items()))

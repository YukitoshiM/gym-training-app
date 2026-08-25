from __future__ import annotations

import asyncio
import array
import html
import json
import re
import sqlite3
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Optional
from urllib.parse import quote

import httpx
import sqlite_vec


EUROPE_PMC_SEARCH_URL = "https://www.ebi.ac.uk/europepmc/webservices/rest/search"
CROSSREF_WORK_URL = "https://api.crossref.org/works/{doi}"

VECTOR_TABLE = "evidence_chunks_vec"

QUERY_ALIASES = {
    "筋肥大": "muscle hypertrophy resistance training",
    "筋肉": "muscle hypertrophy",
    "筋力": "muscle strength resistance training",
    "重量": "training load strength",
    "回数": "repetitions resistance training",
    "セット": "sets resistance training volume",
    "ボリューム": "resistance training volume",
    "タンパク質": "protein muscle hypertrophy",
    "たんぱく質": "protein muscle hypertrophy",
    "どのくらい": "dose response recommended intake",
    "必要": "requirement recommended dose",
    "減量": "weight loss fat loss diet exercise",
    "脂肪": "fat loss body composition",
    "睡眠": "sleep recovery performance",
    "疲労": "fatigue recovery training",
    "回復": "recovery fatigue training",
    "休養": "recovery rest training",
    "健康": "physical activity health",
    "歩": "daily steps walking physical activity health",
    "ウォーキング": "walking daily steps physical activity health",
    "初心者": "beginner novice resistance training",
    "高齢": "older adults resistance training",
    "復帰": "return to training return to sport",
    "再開": "retraining detraining return to training",
    "ブランク": "detraining retraining return to training",
    "休んだ": "detraining retraining return to training",
    "ベンチプレス": "bench press resistance training",
    "スクワット": "squat resistance training",
}

QUERY_TOPIC_TERMS = {
    "hypertrophy": ("筋肥大", "筋肉", "hypertrophy", "muscle growth"),
    "strength": ("筋力", "重量", "strength", "one repetition maximum"),
    "protein": ("タンパク質", "たんぱく質", "protein"),
    "fat_loss": ("減量", "脂肪", "weight loss", "fat loss"),
    "sleep_recovery": ("睡眠", "sleep"),
    "fatigue": ("疲労", "回復", "休養", "fatigue", "recovery", "overreaching"),
    "wellness": ("健康", "歩", "ウォーキング", "wellness", "physical activity", "steps"),
    "return_to_training": (
        "復帰",
        "再開",
        "ブランク",
        "休んだ",
        "return to training",
        "return to sport",
        "retraining",
    ),
}

QUERY_SUBTOPIC_TERMS = {
    "training_volume": ("セット数", "ボリューム", "weekly sets", "training volume"),
    "daily_steps": ("何歩", "歩数", "daily steps", "step count"),
    "steps_and_neat": ("何歩", "歩数", "daily steps", "step count", "walking"),
    "detraining_retraining": (
        "ブランク",
        "休んだ",
        "detraining",
        "retraining",
        "after a break",
    ),
    "physical_inactivity": ("ブランク", "休んだ", "deconditioning", "inactivity"),
    "autoregulation": ("rpe", "rir", "repetitions in reserve", "自動調整"),
    "proximity_to_failure": ("限界", "failure", "rir", "repetitions in reserve"),
}


SCHEMA = """
CREATE TABLE IF NOT EXISTS evidence_documents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    pmid TEXT UNIQUE,
    pmcid TEXT,
    doi TEXT,
    title TEXT NOT NULL,
    abstract_text TEXT NOT NULL DEFAULT '',
    authors TEXT NOT NULL DEFAULT '',
    journal TEXT NOT NULL DEFAULT '',
    publication_year INTEGER,
    publication_types_json TEXT NOT NULL DEFAULT '[]',
    keywords_json TEXT NOT NULL DEFAULT '[]',
    topics_json TEXT NOT NULL DEFAULT '[]',
    goals_json TEXT NOT NULL DEFAULT '[]',
    subtopics_json TEXT NOT NULL DEFAULT '[]',
    collection_queries_json TEXT NOT NULL DEFAULT '[]',
    source_url TEXT NOT NULL,
    is_open_access INTEGER NOT NULL DEFAULT 0,
    retracted INTEGER NOT NULL DEFAULT 0,
    corrected INTEGER NOT NULL DEFAULT 0,
    study_type TEXT NOT NULL DEFAULT 'other',
    quality_score REAL NOT NULL DEFAULT 0,
    source_updated_at TEXT,
    full_text TEXT NOT NULL DEFAULT '',
    full_text_license TEXT NOT NULL DEFAULT '',
    full_text_source_url TEXT NOT NULL DEFAULT '',
    population TEXT NOT NULL DEFAULT '',
    interventions_json TEXT NOT NULL DEFAULT '[]',
    outcomes_json TEXT NOT NULL DEFAULT '[]',
    constraints_json TEXT NOT NULL DEFAULT '[]',
    conclusion TEXT NOT NULL DEFAULT '',
    correction_of_doi TEXT NOT NULL DEFAULT '',
    corrected_by_doi TEXT NOT NULL DEFAULT '',
    version_status TEXT NOT NULL DEFAULT 'current',
    indexed_at TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_evidence_documents_doi
ON evidence_documents(doi) WHERE doi IS NOT NULL AND doi != '';

CREATE TABLE IF NOT EXISTS evidence_chunks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    document_id INTEGER NOT NULL,
    chunk_kind TEXT NOT NULL,
    text TEXT NOT NULL,
    embedding_model TEXT,
    vector_json TEXT,
    UNIQUE(document_id, chunk_kind),
    FOREIGN KEY(document_id) REFERENCES evidence_documents(id) ON DELETE CASCADE
);

CREATE VIRTUAL TABLE IF NOT EXISTS evidence_chunks_fts USING fts5(
    chunk_id UNINDEXED,
    title,
    text,
    keywords,
    tokenize='unicode61 remove_diacritics 2'
);

CREATE TABLE IF NOT EXISTS evidence_sync_state (
    source TEXT PRIMARY KEY,
    last_started_at TEXT,
    last_completed_at TEXT,
    last_status TEXT NOT NULL DEFAULT 'never',
    document_count INTEGER NOT NULL DEFAULT 0,
    error_message TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS evidence_vector_config (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    dimension INTEGER NOT NULL,
    embedding_model TEXT NOT NULL,
    sqlite_vec_version TEXT NOT NULL,
    migrated_at TEXT NOT NULL
);
"""


@dataclass(frozen=True)
class EvidenceDocument:
    pmid: str
    pmcid: str
    doi: str
    title: str
    abstract_text: str
    authors: str
    journal: str
    publication_year: Optional[int]
    publication_types: tuple[str, ...]
    keywords: tuple[str, ...]
    source_url: str
    is_open_access: bool
    retracted: bool
    corrected: bool
    study_type: str
    quality_score: float
    source_updated_at: str
    topics: tuple[str, ...] = ()
    goals: tuple[str, ...] = ()
    subtopics: tuple[str, ...] = ()
    collection_queries: tuple[str, ...] = ()
    full_text: str = ""
    full_text_license: str = ""
    full_text_source_url: str = ""
    population: str = ""
    interventions: tuple[str, ...] = ()
    outcomes: tuple[str, ...] = ()
    constraints: tuple[str, ...] = ()
    conclusion: str = ""
    correction_of_doi: str = ""
    corrected_by_doi: str = ""
    version_status: str = "current"


@dataclass(frozen=True)
class EvidenceUserProfile:
    age: Optional[int] = None
    sex: str = ""
    experience_level: str = ""
    population_tags: tuple[str, ...] = ()
    constraints: tuple[str, ...] = ()


@dataclass(frozen=True)
class EvidenceCitation:
    id: str
    title: str
    year: Optional[int]
    study_type: str
    confidence: str
    url: str
    doi: str
    relevance: float
    source_scope: str = "abstract"
    evidence_summary: str = ""
    population: str = ""
    intervention: str = ""
    outcomes: tuple[str, ...] = ()
    limitations: tuple[str, ...] = ()
    applicability_score: float = 0.5
    applicability_label: str = "unclear"
    version_status: str = "current"
    conclusion_consistency: str = "unknown"
    newer_evidence_note: str = ""
    full_text_license: str = ""
    source_detail_url: str = ""


@dataclass(frozen=True)
class EvidenceSearchResult:
    citations: tuple[EvidenceCitation, ...]
    prompt_context: str
    confidence: str
    searched_documents: int
    last_updated_at: Optional[str]
    state: str = "ready"
    reason: str = ""
    matched_documents: int = 0


@dataclass(frozen=True)
class CrossrefVersionStatus:
    retracted: bool = False
    corrected: bool = False
    correction_of_doi: str = ""
    corrected_by_doi: str = ""


class EvidenceStore:
    def __init__(self, path: Path):
        self.path = path

    def connect(self) -> sqlite3.Connection:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(str(self.path), timeout=30)
        connection.row_factory = sqlite3.Row
        if not hasattr(connection, "enable_load_extension"):
            connection.close()
            raise RuntimeError(
                "sqlite-vec requires a Python SQLite build with extension loading enabled"
            )
        connection.enable_load_extension(True)
        try:
            sqlite_vec.load(connection)
        finally:
            connection.enable_load_extension(False)
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute("PRAGMA journal_mode = WAL")
        connection.executescript(SCHEMA)
        columns = {
            str(row[1])
            for row in connection.execute("PRAGMA table_info(evidence_documents)").fetchall()
        }
        if "topics_json" not in columns:
            connection.execute(
                "ALTER TABLE evidence_documents ADD COLUMN topics_json TEXT NOT NULL DEFAULT '[]'"
            )
        for name in ("goals_json", "subtopics_json", "collection_queries_json"):
            if name not in columns:
                connection.execute(
                    f"ALTER TABLE evidence_documents ADD COLUMN {name} TEXT NOT NULL DEFAULT '[]'"
                )
        text_columns = (
            "full_text", "full_text_license", "full_text_source_url", "population",
            "conclusion", "correction_of_doi", "corrected_by_doi", "version_status",
        )
        for name in text_columns:
            if name not in columns:
                default = "current" if name == "version_status" else ""
                connection.execute(
                    f"ALTER TABLE evidence_documents ADD COLUMN {name} TEXT NOT NULL DEFAULT '{default}'"
                )
        for name in ("interventions_json", "outcomes_json", "constraints_json"):
            if name not in columns:
                connection.execute(
                    f"ALTER TABLE evidence_documents ADD COLUMN {name} TEXT NOT NULL DEFAULT '[]'"
                )
        self._migrate_legacy_vectors(connection)
        return connection

    def _migrate_legacy_vectors(self, connection: sqlite3.Connection) -> None:
        candidate = connection.execute(
            "SELECT 1 FROM evidence_chunks WHERE vector_json IS NOT NULL LIMIT 1"
        ).fetchone()
        if not candidate:
            return
        connection.execute("BEGIN IMMEDIATE")
        try:
            rows = connection.execute(
                """
                SELECT id, embedding_model, vector_json
                FROM evidence_chunks
                WHERE vector_json IS NOT NULL
                ORDER BY id
                """
            ).fetchall()
            if not rows:
                connection.commit()
                return
            first_vector = _json_vector(rows[0]["vector_json"])
            if not first_vector:
                connection.commit()
                return
            self._ensure_vector_table(
                connection,
                dimension=len(first_vector),
                embedding_model=str(rows[0]["embedding_model"] or "legacy"),
            )
            migrated_ids = []
            for row in rows:
                vector = _json_vector(row["vector_json"])
                if len(vector) != len(first_vector):
                    continue
                self._put_vector(connection, int(row["id"]), vector)
                migrated_ids.append(int(row["id"]))
            if migrated_ids:
                placeholders = ",".join("?" for _ in migrated_ids)
                connection.execute(
                    f"UPDATE evidence_chunks SET vector_json = NULL WHERE id IN ({placeholders})",
                    migrated_ids,
                )
            connection.commit()
        except Exception:
            connection.rollback()
            raise

    def _put_vector(
        self,
        connection: sqlite3.Connection,
        chunk_id: int,
        vector: list[float],
    ) -> None:
        connection.execute(f"DELETE FROM {VECTOR_TABLE} WHERE rowid = ?", (chunk_id,))
        connection.execute(
            f"INSERT INTO {VECTOR_TABLE}(rowid, embedding) VALUES (?, ?)",
            (chunk_id, sqlite_vec.serialize_float32(vector)),
        )

    def _ensure_vector_table(
        self,
        connection: sqlite3.Connection,
        *,
        dimension: int,
        embedding_model: str,
    ) -> None:
        config = connection.execute(
            "SELECT dimension, embedding_model FROM evidence_vector_config WHERE id = 1"
        ).fetchone()
        table_exists = connection.execute(
            "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
            (VECTOR_TABLE,),
        ).fetchone()
        if config and int(config["dimension"]) != dimension:
            raise ValueError(
                f"embedding dimension changed from {config['dimension']} to {dimension}; rebuild required"
            )
        if not table_exists:
            connection.execute(
                f"CREATE VIRTUAL TABLE {VECTOR_TABLE} USING "
                f"vec0(embedding float[{dimension}] distance_metric=cosine)"
            )
        connection.execute(
            """
            INSERT INTO evidence_vector_config (
                id, dimension, embedding_model, sqlite_vec_version, migrated_at
            ) VALUES (1, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                embedding_model=excluded.embedding_model,
                sqlite_vec_version=excluded.sqlite_vec_version,
                migrated_at=excluded.migrated_at
            """,
            (dimension, embedding_model, sqlite_vec.__version__, _utc_now()),
        )

    def upsert_documents(
        self,
        documents: Iterable[EvidenceDocument],
        *,
        embedding_model: Optional[str] = None,
        vectors: Optional[dict[str, list[float]]] = None,
        replace_existing: bool = False,
    ) -> int:
        vectors = vectors or {}
        indexed_at = _utc_now()
        count = 0
        with self.connect() as connection:
            vector_dimension = next((len(value) for value in vectors.values() if value), 0)
            if vector_dimension:
                self._ensure_vector_table(
                    connection,
                    dimension=vector_dimension,
                    embedding_model=embedding_model or "unknown",
                )
            if replace_existing:
                if connection.execute(
                    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
                    (VECTOR_TABLE,),
                ).fetchone():
                    connection.execute(f"DELETE FROM {VECTOR_TABLE}")
                connection.execute("DELETE FROM evidence_chunks_fts")
                connection.execute("DELETE FROM evidence_chunks")
                connection.execute("DELETE FROM evidence_documents")
            for document in documents:
                connection.execute(
                    """
                    INSERT INTO evidence_documents (
                        pmid, pmcid, doi, title, abstract_text, authors, journal,
                        publication_year, publication_types_json, keywords_json,
                        topics_json, goals_json, subtopics_json, collection_queries_json,
                        source_url, is_open_access, retracted, corrected, study_type,
                        quality_score, source_updated_at, full_text, full_text_license,
                        full_text_source_url, population, interventions_json, outcomes_json,
                        constraints_json, conclusion, correction_of_doi, corrected_by_doi,
                        version_status, indexed_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(pmid) DO UPDATE SET
                        pmcid=excluded.pmcid, doi=excluded.doi, title=excluded.title,
                        abstract_text=excluded.abstract_text, authors=excluded.authors,
                        journal=excluded.journal, publication_year=excluded.publication_year,
                        publication_types_json=excluded.publication_types_json,
                        keywords_json=excluded.keywords_json, topics_json=excluded.topics_json,
                        goals_json=excluded.goals_json, subtopics_json=excluded.subtopics_json,
                        collection_queries_json=excluded.collection_queries_json,
                        source_url=excluded.source_url,
                        is_open_access=excluded.is_open_access, retracted=excluded.retracted,
                        corrected=excluded.corrected, study_type=excluded.study_type,
                        quality_score=excluded.quality_score,
                        source_updated_at=excluded.source_updated_at,
                        full_text=excluded.full_text,
                        full_text_license=excluded.full_text_license,
                        full_text_source_url=excluded.full_text_source_url,
                        population=excluded.population,
                        interventions_json=excluded.interventions_json,
                        outcomes_json=excluded.outcomes_json,
                        constraints_json=excluded.constraints_json,
                        conclusion=excluded.conclusion,
                        correction_of_doi=excluded.correction_of_doi,
                        corrected_by_doi=excluded.corrected_by_doi,
                        version_status=excluded.version_status,
                        indexed_at=excluded.indexed_at
                    """,
                    (
                        document.pmid,
                        document.pmcid,
                        document.doi,
                        document.title,
                        document.abstract_text,
                        document.authors,
                        document.journal,
                        document.publication_year,
                        json.dumps(document.publication_types, ensure_ascii=False),
                        json.dumps(document.keywords, ensure_ascii=False),
                        json.dumps(document.topics, ensure_ascii=False),
                        json.dumps(document.goals, ensure_ascii=False),
                        json.dumps(document.subtopics, ensure_ascii=False),
                        json.dumps(document.collection_queries, ensure_ascii=False),
                        document.source_url,
                        int(document.is_open_access),
                        int(document.retracted),
                        int(document.corrected),
                        document.study_type,
                        document.quality_score,
                        document.source_updated_at,
                        document.full_text,
                        document.full_text_license,
                        document.full_text_source_url,
                        document.population,
                        json.dumps(document.interventions, ensure_ascii=False),
                        json.dumps(document.outcomes, ensure_ascii=False),
                        json.dumps(document.constraints, ensure_ascii=False),
                        document.conclusion,
                        document.correction_of_doi,
                        document.corrected_by_doi,
                        document.version_status,
                        indexed_at,
                    ),
                )
                row = connection.execute(
                    "SELECT id FROM evidence_documents WHERE pmid = ?", (document.pmid,)
                ).fetchone()
                if row is None:
                    continue
                document_id = int(row["id"])
                chunk_text = _chunk_text(document)
                vector = vectors.get(document.pmid)
                connection.execute(
                    """
                    INSERT INTO evidence_chunks (
                        document_id, chunk_kind, text, embedding_model, vector_json
                    ) VALUES (?, 'abstract', ?, ?, NULL)
                    ON CONFLICT(document_id, chunk_kind) DO UPDATE SET
                        text=excluded.text,
                        embedding_model=COALESCE(excluded.embedding_model, evidence_chunks.embedding_model)
                    """,
                    (
                        document_id,
                        chunk_text,
                        embedding_model if vector else None,
                    ),
                )
                chunk = connection.execute(
                    "SELECT id FROM evidence_chunks WHERE document_id = ? AND chunk_kind = 'abstract'",
                    (document_id,),
                ).fetchone()
                if chunk is None:
                    continue
                chunk_id = int(chunk["id"])
                if vector:
                    if len(vector) != vector_dimension:
                        raise ValueError("all embedding vectors must have the same dimension")
                    self._put_vector(connection, chunk_id, vector)
                connection.execute("DELETE FROM evidence_chunks_fts WHERE chunk_id = ?", (chunk_id,))
                connection.execute(
                    "INSERT INTO evidence_chunks_fts(chunk_id, title, text, keywords) VALUES (?, ?, ?, ?)",
                    (
                        chunk_id,
                        document.title,
                        chunk_text,
                        " ".join(
                            (
                                *document.keywords,
                                *document.topics,
                                *document.goals,
                                *document.subtopics,
                            )
                        ),
                    ),
                )
                if document.full_text and document.full_text_license:
                    connection.execute(
                        """
                        INSERT INTO evidence_chunks (
                            document_id, chunk_kind, text, embedding_model, vector_json
                        ) VALUES (?, 'full_text', ?, NULL, NULL)
                        ON CONFLICT(document_id, chunk_kind) DO UPDATE SET text=excluded.text
                        """,
                        (document_id, _full_text_chunk(document)),
                    )
                    full_chunk = connection.execute(
                        "SELECT id FROM evidence_chunks WHERE document_id = ? AND chunk_kind = 'full_text'",
                        (document_id,),
                    ).fetchone()
                    if full_chunk:
                        full_chunk_id = int(full_chunk["id"])
                        connection.execute(
                            "DELETE FROM evidence_chunks_fts WHERE chunk_id = ?", (full_chunk_id,)
                        )
                        connection.execute(
                            "INSERT INTO evidence_chunks_fts(chunk_id, title, text, keywords) VALUES (?, ?, ?, ?)",
                            (
                                full_chunk_id,
                                document.title,
                                _full_text_chunk(document),
                                " ".join((*document.keywords, *document.topics, *document.goals)),
                            ),
                        )
                else:
                    stale_full_text = connection.execute(
                        "SELECT id FROM evidence_chunks WHERE document_id = ? AND chunk_kind = 'full_text'",
                        (document_id,),
                    ).fetchone()
                    if stale_full_text:
                        stale_id = int(stale_full_text["id"])
                        connection.execute(
                            "DELETE FROM evidence_chunks_fts WHERE chunk_id = ?", (stale_id,)
                        )
                        connection.execute("DELETE FROM evidence_chunks WHERE id = ?", (stale_id,))
                count += 1
        return count

    def record_sync(
        self,
        *,
        status: str,
        document_count: int = 0,
        error_message: str = "",
        completed: bool = False,
    ) -> None:
        now = _utc_now()
        with self.connect() as connection:
            connection.execute(
                """
                INSERT INTO evidence_sync_state (
                    source, last_started_at, last_completed_at, last_status,
                    document_count, error_message
                ) VALUES ('europe_pmc', ?, ?, ?, ?, ?)
                ON CONFLICT(source) DO UPDATE SET
                    last_started_at=CASE WHEN excluded.last_status = 'running'
                        THEN excluded.last_started_at ELSE evidence_sync_state.last_started_at END,
                    last_completed_at=CASE WHEN ? THEN excluded.last_completed_at
                        ELSE evidence_sync_state.last_completed_at END,
                    last_status=excluded.last_status,
                    document_count=excluded.document_count,
                    error_message=excluded.error_message
                """,
                (now, now if completed else None, status, document_count, error_message[:500], int(completed)),
            )

    def clear_topics_outside(self, pmids: Iterable[str]) -> None:
        retained = sorted({str(pmid) for pmid in pmids if str(pmid)})
        with self.connect() as connection:
            if not retained:
                connection.execute(
                    """
                    UPDATE evidence_documents
                    SET topics_json = '[]', goals_json = '[]', subtopics_json = '[]',
                        collection_queries_json = '[]'
                    """
                )
                return
            placeholders = ",".join("?" for _ in retained)
            connection.execute(
                f"""
                UPDATE evidence_documents
                SET topics_json = '[]', goals_json = '[]', subtopics_json = '[]',
                    collection_queries_json = '[]'
                WHERE pmid NOT IN ({placeholders})
                """,
                retained,
            )

    def status(self) -> dict[str, Any]:
        with self.connect() as connection:
            totals = connection.execute(
                """
                SELECT COUNT(*) AS documents,
                       SUM(CASE WHEN retracted = 0 AND topics_json != '[]' THEN 1 ELSE 0 END)
                           AS usable_documents,
                       SUM(CASE WHEN full_text != '' AND full_text_license != '' THEN 1 ELSE 0 END)
                           AS full_text_documents,
                       SUM(CASE WHEN version_status = 'superseded' THEN 1 ELSE 0 END)
                           AS superseded_documents
                FROM evidence_documents
                """
            ).fetchone()
            chunks = connection.execute("SELECT COUNT(*) AS chunks FROM evidence_chunks").fetchone()
            vector_config = connection.execute(
                "SELECT dimension, embedding_model, sqlite_vec_version FROM evidence_vector_config WHERE id = 1"
            ).fetchone()
            vector_chunks = 0
            if vector_config:
                vector_chunks = int(
                    connection.execute(f"SELECT COUNT(*) FROM {VECTOR_TABLE}").fetchone()[0]
                )
            goal_rows = connection.execute(
                """
                SELECT goals_json FROM evidence_documents
                WHERE retracted = 0 AND goals_json != '[]'
                """
            ).fetchall()
            sync = connection.execute(
                "SELECT * FROM evidence_sync_state WHERE source = 'europe_pmc'"
            ).fetchone()
        documents = int(totals["documents"] or 0)
        goal_counts: dict[str, int] = {}
        for row in goal_rows:
            for goal in _json_strings(row["goals_json"]):
                goal_counts[goal] = goal_counts.get(goal, 0) + 1
        return {
            "state": "ready" if documents else "empty",
            "documents": documents,
            "usable_documents": int(totals["usable_documents"] or 0),
            "full_text_documents": int(totals["full_text_documents"] or 0),
            "superseded_documents": int(totals["superseded_documents"] or 0),
            "chunks": int(chunks["chunks"] or 0),
            "vector_chunks": vector_chunks,
            "vector_dimension": int(vector_config["dimension"]) if vector_config else None,
            "embedding_model": str(vector_config["embedding_model"]) if vector_config else None,
            "sqlite_vec_version": str(vector_config["sqlite_vec_version"]) if vector_config else None,
            "goal_counts": dict(sorted(goal_counts.items())),
            "last_updated_at": sync["last_completed_at"] if sync else None,
            "last_sync_status": sync["last_status"] if sync else "never",
        }

    def existing_vectors(
        self,
        pmids: Iterable[str],
        *,
        embedding_model: str,
    ) -> dict[str, list[float]]:
        retained = {str(pmid) for pmid in pmids if str(pmid)}
        if not retained:
            return {}
        with self.connect() as connection:
            config = connection.execute(
                "SELECT embedding_model FROM evidence_vector_config WHERE id = 1"
            ).fetchone()
            if not config or str(config["embedding_model"]) != embedding_model:
                return {}
            rows = connection.execute(
                f"""
                SELECT d.pmid, vectors.embedding
                FROM {VECTOR_TABLE} AS vectors
                JOIN evidence_chunks c ON c.id = vectors.rowid
                JOIN evidence_documents d ON d.id = c.document_id
                """
            ).fetchall()
        vectors: dict[str, list[float]] = {}
        for row in rows:
            pmid = str(row["pmid"])
            if pmid not in retained:
                continue
            values = array.array("f")
            values.frombytes(bytes(row["embedding"]))
            vectors[pmid] = [float(value) for value in values]
        return vectors

    def search(
        self,
        query: str,
        *,
        query_vector: Optional[list[float]] = None,
        goal: Optional[str] = None,
        user_profile: Optional[EvidenceUserProfile] = None,
        purpose: str = "chat",
        limit: int = 5,
        candidate_limit: int = 80,
    ) -> EvidenceSearchResult:
        expanded_query = expand_query(query)
        fts_query = _fts_query(expanded_query)
        query_topics = detect_query_topics(query)
        query_subtopics = detect_query_subtopics(query)
        status = self.status()
        with self.connect() as connection:
            lexical_rows: list[sqlite3.Row] = []
            if fts_query:
                try:
                    lexical_rows = connection.execute(
                        """
                        SELECT d.*, c.text AS chunk_text, c.chunk_kind,
                               c.vector_json, c.embedding_model,
                               bm25(evidence_chunks_fts, 0.0, 4.0, 1.0) AS lexical_rank
                        FROM evidence_chunks_fts
                        JOIN evidence_chunks c ON c.id = evidence_chunks_fts.chunk_id
                        JOIN evidence_documents d ON d.id = c.document_id
                        WHERE evidence_chunks_fts MATCH ? AND d.retracted = 0
                              AND d.version_status != 'superseded'
                        ORDER BY lexical_rank, d.quality_score DESC
                        LIMIT ?
                        """,
                        (fts_query, candidate_limit),
                    ).fetchall()
                except sqlite3.OperationalError:
                    lexical_rows = []

            vector_rows: list[sqlite3.Row] = []
            vector_config = connection.execute(
                "SELECT dimension FROM evidence_vector_config WHERE id = 1"
            ).fetchone()
            if (
                query_vector
                and vector_config
                and len(query_vector) == int(vector_config["dimension"])
            ):
                vector_rows = connection.execute(
                    f"""
                    SELECT d.*, c.text AS chunk_text, c.chunk_kind, c.embedding_model,
                           NULL AS lexical_rank, neighbors.distance AS vector_distance
                    FROM (
                        SELECT rowid, distance
                        FROM {VECTOR_TABLE}
                        WHERE embedding MATCH ? AND k = ?
                        ORDER BY distance
                    ) AS neighbors
                    JOIN evidence_chunks c ON c.id = neighbors.rowid
                    JOIN evidence_documents d ON d.id = c.document_id
                    WHERE d.retracted = 0 AND d.version_status != 'superseded'
                    ORDER BY neighbors.distance
                    """,
                    (
                        sqlite_vec.serialize_float32(query_vector),
                        max(candidate_limit, 300),
                    ),
                ).fetchall()

        candidates: dict[int, dict[str, Any]] = {}
        for position, row in enumerate(lexical_rows):
            value = {
                "row": row,
                "lexical": max(0.4, 1.0 - position / max(1, len(lexical_rows) * 5)),
                "semantic": 0.0,
            }
            existing = candidates.get(int(row["id"]))
            if existing is None or value["lexical"] > existing["lexical"]:
                candidates[int(row["id"])] = value
        for row in vector_rows:
            semantic = max(0.0, 1.0 - float(row["vector_distance"] or 0.0))
            if semantic < 0.35:
                continue
            item = candidates.setdefault(
                int(row["id"]), {"row": row, "lexical": 0.0, "semantic": 0.0}
            )
            item["semantic"] = max(item["semantic"], semantic)

        ranked = []
        current_year = datetime.now(timezone.utc).year
        for item in candidates.values():
            row = item["row"]
            document_topics = set(_json_strings(row["topics_json"]))
            document_goals = set(_json_strings(row["goals_json"]))
            document_subtopics = set(_json_strings(row["subtopics_json"]))
            topic_matches = not query_topics or bool(query_topics & document_topics)
            if not topic_matches:
                continue
            subtopic_match = bool(query_subtopics.intersection(document_subtopics))
            if subtopic_match and "detraining_retraining" in query_subtopics:
                title = str(row["title"] or "").lower()
                subtopic_match = any(
                    term in title
                    for term in ("detraining", "retraining", "training cessation")
                )
            goal_match = bool(goal and goal in document_goals)
            applicability, applicability_label = study_applicability(row, user_profile)
            year = int(row["publication_year"] or 0)
            recency = max(0.0, 1.0 - max(0, current_year - year) / 20.0) if year else 0.0
            score = min(
                1.0,
                0.36 * item["lexical"]
                + 0.28 * item["semantic"]
                + 0.18 * float(row["quality_score"] or 0)
                + 0.04 * recency
                + (0.08 if query_topics else 0.0)
                + (0.08 if goal_match else 0.0)
                + (0.12 if subtopic_match else 0.0)
                + 0.22 * applicability
                + purpose_score_adjustment(purpose, str(row["study_type"]), year)
            )
            if score >= 0.18:
                ranked.append((score, row, subtopic_match, applicability, applicability_label))
        ranked.sort(key=lambda value: value[0], reverse=True)
        if query_subtopics:
            subtopic_ranked = [item for item in ranked if item[2]]
            if subtopic_ranked:
                ranked = subtopic_ranked
        applicable_ranked = [item for item in ranked if item[4] != "mismatch"]
        selected = applicable_ranked[: max(1, min(limit, 8))]

        confidence = evidence_confidence([row for _, row, _, _, _ in selected])
        citations = tuple(
            EvidenceCitation(
                id=f"PMID:{row['pmid']}",
                title=str(row["title"]),
                year=int(row["publication_year"]) if row["publication_year"] else None,
                study_type=str(row["study_type"]),
                confidence=_quality_confidence(float(row["quality_score"] or 0)),
                url=str(row["source_url"]),
                doi=str(row["doi"] or ""),
                relevance=round(score, 4),
                source_scope="full_text" if str(row["chunk_kind"] or "") == "full_text" else "abstract",
                evidence_summary=evidence_summary(row),
                population=str(row["population"] or ""),
                intervention="; ".join(_json_strings(row["interventions_json"])[:2]),
                outcomes=tuple(_json_strings(row["outcomes_json"])[:3]),
                limitations=tuple(_json_strings(row["constraints_json"])[:3]),
                applicability_score=round(applicability, 3),
                applicability_label=applicability_label,
                version_status=str(row["version_status"] or "current"),
                conclusion_consistency=conclusion_consistency(row, selected),
                newer_evidence_note=newer_evidence_note(row, selected),
                full_text_license=str(row["full_text_license"] or ""),
                source_detail_url=str(row["full_text_source_url"] or row["source_url"] or ""),
            )
            for score, row, _, applicability, applicability_label in selected
        )
        context_blocks = []
        for index, (score, row, _, applicability, applicability_label) in enumerate(selected, 1):
            excerpt = str(row["chunk_text"] or "")[:1600]
            context_blocks.append(
                f"[E{index}] PMID:{row['pmid']} | {row['title']} | "
                f"{row['publication_year'] or 'year unknown'} | {row['study_type']} | "
                f"scope={row['chunk_kind']} | quality={float(row['quality_score'] or 0):.2f} | "
                f"relevance={score:.3f} | applicability={applicability_label}:{applicability:.2f}\n"
                f"Population: {row['population'] or 'not reported'}\n"
                f"Intervention: {'; '.join(_json_strings(row['interventions_json'])[:2]) or 'not reported'}\n"
                f"Outcomes: {'; '.join(_json_strings(row['outcomes_json'])[:3]) or 'not reported'}\n"
                f"Conclusion: {row['conclusion'] or 'not reported'}\n"
                f"Constraints: {'; '.join(_json_strings(row['constraints_json'])[:3]) or 'not reported'}\n"
                f"Excerpt: {excerpt}"
            )
        if citations:
            state = "ready"
            reason = ""
        elif ranked:
            state = "population_mismatch"
            reason = "Retrieved studies did not match the available user population information."
        else:
            state = "no_match"
            reason = "No non-retracted, current study matched the query and purpose filters."
        return EvidenceSearchResult(
            citations=citations,
            prompt_context="\n\n".join(context_blocks),
            confidence=confidence,
            searched_documents=int(status["usable_documents"]),
            last_updated_at=status["last_updated_at"],
            state=state,
            reason=reason,
            matched_documents=len(citations),
        )


class EuropePMCClient:
    def __init__(
        self,
        *,
        timeout_seconds: float = 30.0,
        transport: Optional[httpx.AsyncBaseTransport] = None,
    ):
        self.timeout_seconds = timeout_seconds
        self.transport = transport

    async def search(self, query: str, *, page_size: int = 25) -> list[EvidenceDocument]:
        return await self.search_pages(query, max_results=page_size, sort="relevance")

    async def search_pages(
        self,
        query: str,
        *,
        max_results: int,
        sort: str = "relevance",
    ) -> list[EvidenceDocument]:
        maximum = max(1, max_results)
        cursor = "*"
        collected: list[EvidenceDocument] = []
        headers = {"User-Agent": "BodyMode-Evidence-RAG/0.2"}
        async with httpx.AsyncClient(
            timeout=self.timeout_seconds,
            headers=headers,
            transport=self.transport,
        ) as client:
            while len(collected) < maximum:
                params = {
                    "query": query,
                    "format": "json",
                    "resultType": "core",
                    "pageSize": str(min(100, maximum - len(collected))),
                    "cursorMark": cursor,
                }
                if sort == "recent":
                    params["sort"] = "FIRST_PDATE_D desc"
                response = None
                for attempt in range(3):
                    try:
                        response = await client.get(EUROPE_PMC_SEARCH_URL, params=params)
                        response.raise_for_status()
                        break
                    except httpx.HTTPError:
                        if attempt == 2:
                            raise
                        await asyncio.sleep(1.5 * (attempt + 1))
                if response is None:
                    raise RuntimeError("Europe PMC returned no response")
                payload = response.json()
                results = payload.get("resultList", {}).get("result", [])
                collected.extend(
                    parse_europe_pmc_document(item) for item in results if item.get("pmid")
                )
                next_cursor = str(payload.get("nextCursorMark") or "")
                if not results or not next_cursor or next_cursor == cursor:
                    break
                cursor = next_cursor
        return collected[:maximum]


class CrossrefClient:
    def __init__(
        self,
        *,
        mailto: str = "",
        timeout_seconds: float = 15.0,
        transport: Optional[httpx.AsyncBaseTransport] = None,
    ):
        self.mailto = mailto
        self.timeout_seconds = timeout_seconds
        self.transport = transport

    async def update_flags(self, doi: str) -> tuple[bool, bool]:
        status = await self.update_status(doi)
        return status.retracted, status.corrected

    async def update_status(self, doi: str) -> CrossrefVersionStatus:
        if not doi:
            return CrossrefVersionStatus()
        headers = {"User-Agent": "BodyMode-Evidence-RAG/0.1"}
        params = {"mailto": self.mailto} if self.mailto else None
        try:
            async with httpx.AsyncClient(
                timeout=self.timeout_seconds,
                headers=headers,
                transport=self.transport,
            ) as client:
                response = await client.get(
                    CROSSREF_WORK_URL.format(doi=quote(doi, safe="")),
                    params=params,
                )
                response.raise_for_status()
            message = response.json().get("message", {})
        except (httpx.HTTPError, ValueError, UnicodeError):
            return CrossrefVersionStatus()
        updates = message.get("update-to", []) or []
        update_types = {str(update.get("type", "")).lower() for update in updates}
        relations = message.get("relation", {}) or {}
        correction_of = _relation_doi(relations, "is-correction-of")
        corrected_by = _relation_doi(relations, "is-corrected-by")
        if not corrected_by:
            corrected_by = next(
                (
                    str(update.get("DOI") or update.get("doi") or "").lower().strip()
                    for update in updates
                    if str(update.get("type", "")).lower() in {"correction", "update"}
                    and str(update.get("DOI") or update.get("doi") or "").strip()
                ),
                "",
            )
        return CrossrefVersionStatus(
            retracted="retraction" in update_types,
            corrected=bool(update_types & {"correction", "update"}) or bool(correction_of),
            correction_of_doi=correction_of,
            corrected_by_doi=corrected_by,
        )


def parse_europe_pmc_document(item: dict[str, Any]) -> EvidenceDocument:
    publication_types = tuple(_list_value(item.get("pubTypeList"), "pubType"))
    keywords = tuple(_list_value(item.get("keywordList"), "keyword"))
    title = _clean_markup(str(item.get("title") or "Untitled"))
    abstract = _clean_markup(str(item.get("abstractText") or ""))
    lowered_types = " ".join(publication_types).lower()
    lowered_title = title.lower()
    retracted = "retracted publication" in lowered_types or lowered_title.startswith("retracted:")
    corrected = "corrected and republished article" in lowered_types
    study_type = classify_study_type(publication_types, title)
    pmid = str(item.get("pmid") or item.get("id") or "")
    year_value = str(item.get("pubYear") or "")
    year = int(year_value) if year_value.isdigit() else None
    return EvidenceDocument(
        pmid=pmid,
        pmcid=str(item.get("pmcid") or ""),
        doi=str(item.get("doi") or "").lower(),
        title=title,
        abstract_text=abstract,
        authors=str(item.get("authorString") or ""),
        journal=str(item.get("journalTitle") or ""),
        publication_year=year,
        publication_types=publication_types,
        keywords=keywords,
        source_url=f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/",
        is_open_access=str(item.get("isOpenAccess") or "").upper() == "Y",
        retracted=retracted,
        corrected=corrected,
        study_type=study_type,
        quality_score=study_quality_score(study_type),
        source_updated_at=str(item.get("firstIndexDate") or item.get("dateOfRevision") or ""),
    )


def classify_study_type(publication_types: Iterable[str], title: str = "") -> str:
    value = " ".join(publication_types).lower() + " " + title.lower()
    if "practice guideline" in value or "guideline" in value or "consensus statement" in value:
        return "guideline"
    if "meta-analysis" in value or "meta analysis" in value:
        return "meta_analysis"
    if "systematic review" in value:
        return "systematic_review"
    if "randomized controlled trial" in value or "randomised controlled trial" in value:
        return "randomized_controlled_trial"
    if "clinical trial" in value:
        return "clinical_trial"
    if "review" in value:
        return "review"
    if "observational" in value or "cohort" in value or "cross-sectional" in value:
        return "observational"
    return "other"


def study_quality_score(study_type: str) -> float:
    return {
        "guideline": 1.0,
        "meta_analysis": 0.95,
        "systematic_review": 0.9,
        "randomized_controlled_trial": 0.8,
        "clinical_trial": 0.7,
        "review": 0.62,
        "observational": 0.55,
        "other": 0.4,
    }.get(study_type, 0.4)


def expand_query(query: str) -> str:
    additions = [alias for key, alias in QUERY_ALIASES.items() if key in query]
    return " ".join([query, *additions]).strip()


def user_profile_from_context(context: dict[str, Any]) -> EvidenceUserProfile:
    flattened = json.dumps(context, ensure_ascii=False).lower()
    age_match = re.search(r"(?:年齢目安|age)\D{0,8}(\d{1,3})", flattened)
    age = int(age_match.group(1)) if age_match else None
    sex = ""
    if any(term in flattened for term in ("性別: 女性", "sex: female", "gender: female")):
        sex = "female"
    elif any(term in flattened for term in ("性別: 男性", "sex: male", "gender: male")):
        sex = "male"
    experience = ""
    experience_terms = {
        "beginner": ("経験レベル: 初心者", "experience level: beginner", "novice"),
        "intermediate": ("経験レベル: 中級", "experience level: intermediate"),
        "advanced": ("経験レベル: 上級", "experience level: advanced"),
    }
    for value, terms in experience_terms.items():
        if any(term in flattened for term in terms):
            experience = value
            break
    tags = tuple(
        tag
        for tag, terms in {
            "older adults": ("高齢", "older adult"),
            "athlete": ("アスリート", "athlete"),
            "postmenopausal women": ("閉経後", "postmenopausal"),
        }.items()
        if any(term in flattened for term in terms)
    )
    constraints = tuple(
        value
        for value in context.get("preferences", [])
        if isinstance(value, str) and any(term in value for term in ("制約", "怪我", "痛み", "不可"))
    )
    return EvidenceUserProfile(
        age=age,
        sex=sex,
        experience_level=experience,
        population_tags=tags,
        constraints=constraints,
    )


def detect_query_topics(query: str) -> set[str]:
    lowered = query.lower()
    return {
        topic
        for topic, terms in QUERY_TOPIC_TERMS.items()
        if any(term.lower() in lowered for term in terms)
    }


def detect_query_subtopics(query: str) -> set[str]:
    lowered = query.lower()
    return {
        subtopic
        for subtopic, terms in QUERY_SUBTOPIC_TERMS.items()
        if any(term.lower() in lowered for term in terms)
    }


def document_matches_topic(document: EvidenceDocument, topic: str) -> bool:
    title = document.title.lower()
    value = f"{title} {document.abstract_text} {' '.join(document.keywords)}".lower()
    if topic == "protein" and not (
        any(term in title for term in ("protein", "amino acid"))
        or any(
            term in value
            for term in (
                "protein intake",
                "protein supplementation",
                "dietary protein",
                "amino acid intake",
                "amino acid supplementation",
            )
        )
    ):
        return False
    if topic == "sleep_recovery" and not any(
        term in title for term in ("sleep", "nap", "napping")
    ):
        return False
    rules = {
        "hypertrophy": (
            ("hypertrophy", "muscle mass", "muscle growth"),
            ("resistance", "strength training", "exercise"),
        ),
        "strength": (
            ("strength", "one repetition maximum", "1rm"),
            ("resistance", "strength training", "exercise"),
        ),
        "protein": (
            ("protein",),
            ("muscle", "resistance", "exercise", "athlete", "hypertrophy"),
        ),
        "fat_loss": (
            ("weight loss", "fat loss", "fat mass", "body composition", "obesity"),
            ("exercise", "physical activity", "diet", "energy restriction"),
        ),
        "sleep_recovery": (
            ("sleep",),
            ("exercise", "training", "athlete", "physical performance", "muscle"),
        ),
        "fatigue": (
            ("fatigue", "recovery", "overreach", "overtraining"),
            ("exercise", "training", "athlete", "resistance"),
        ),
        "wellness": (
            ("physical activity", "exercise"),
            ("health", "wellbeing", "well-being", "mortality", "cardiovascular"),
        ),
        "return_to_training": (
            ("return to training", "return to sport", "return-to-sport"),
            ("exercise", "training", "sport", "rehabilitation"),
        ),
    }
    groups = rules.get(topic)
    return bool(groups) and all(any(term in value for term in group) for group in groups)


def evidence_confidence(rows: list[sqlite3.Row]) -> str:
    if not rows:
        return "insufficient"
    scores = [float(row["quality_score"] or 0) for row in rows]
    if len(scores) >= 2 and max(scores) >= 0.9:
        return "high"
    if max(scores) >= 0.7:
        return "moderate"
    return "low"


def study_applicability(
    row: sqlite3.Row,
    profile: Optional[EvidenceUserProfile],
) -> tuple[float, str]:
    if profile is None:
        return 0.5, "unclear"
    population = str(row["population"] or "").lower()
    if not population:
        return 0.45, "unclear"
    score = 0.55
    hard_mismatch = False
    if profile.age is not None:
        older_study = any(term in population for term in ("older adult", "elderly", "aged 65"))
        youth_study = any(term in population for term in ("adolescent", "children", "youth"))
        if profile.age >= 65 and older_study:
            score += 0.2
        elif profile.age < 18 and youth_study:
            score += 0.2
        elif (profile.age >= 65 and youth_study) or (profile.age >= 18 and youth_study):
            hard_mismatch = True
    sex = profile.sex.lower()
    if sex:
        men_only = any(term in population for term in ("men only", "male participants", "healthy men"))
        women_only = any(term in population for term in ("women only", "female participants", "healthy women"))
        if (sex in {"female", "woman", "women"} and men_only) or (
            sex in {"male", "man", "men"} and women_only
        ):
            score -= 0.25
        elif not men_only and not women_only:
            score += 0.05
    experience = profile.experience_level.lower()
    if experience:
        trained = any(term in population for term in ("trained", "experienced", "athlete"))
        untrained = any(term in population for term in ("untrained", "novice", "beginner", "sedentary"))
        if experience in {"beginner", "novice", "untrained"}:
            score += 0.15 if untrained else (-0.1 if trained else 0)
        elif experience in {"intermediate", "advanced", "trained"}:
            score += 0.15 if trained else (-0.1 if untrained else 0)
    tags = {item.lower() for item in profile.population_tags}
    if tags and any(tag in population for tag in tags):
        score += 0.15
    score = max(0.0, min(1.0, score))
    if hard_mismatch or score < 0.3:
        return score, "mismatch"
    if score >= 0.7:
        return score, "direct"
    if score >= 0.5:
        return score, "partial"
    return score, "unclear"


def purpose_score_adjustment(purpose: str, study_type: str, year: int) -> float:
    purpose = purpose.lower()
    if purpose == "daily_recommendation":
        return 0.04 if study_type in {"guideline", "meta_analysis", "systematic_review"} else 0.0
    if purpose == "plan_generation":
        return 0.04 if study_type in {"meta_analysis", "systematic_review", "randomized_controlled_trial"} else 0.0
    if purpose == "safety":
        return 0.06 if study_type in {"guideline", "systematic_review"} else 0.0
    return 0.02 if year and year >= datetime.now(timezone.utc).year - 5 else 0.0


def evidence_summary(row: sqlite3.Row) -> str:
    conclusion = str(row["conclusion"] or "").strip()
    if conclusion:
        return conclusion[:600]
    outcomes = _json_strings(row["outcomes_json"])
    if outcomes:
        return outcomes[0][:600]
    return str(row["abstract_text"] or "")[:600]


def conclusion_consistency(
    row: sqlite3.Row,
    selected: list[tuple[float, sqlite3.Row, bool, float, str]],
) -> str:
    own = _conclusion_polarity(str(row["conclusion"] or row["abstract_text"] or ""))
    others = {
        _conclusion_polarity(str(candidate["conclusion"] or candidate["abstract_text"] or ""))
        for _, candidate, _, _, _ in selected
        if candidate["pmid"] != row["pmid"]
    }
    others.discard("unclear")
    if own == "unclear" or not others:
        return "unknown"
    return "mixed" if any(value != own for value in others) else "consistent"


def newer_evidence_note(
    row: sqlite3.Row,
    selected: list[tuple[float, sqlite3.Row, bool, float, str]],
) -> str:
    year = int(row["publication_year"] or 0)
    own = _conclusion_polarity(str(row["conclusion"] or row["abstract_text"] or ""))
    newer = [
        candidate
        for _, candidate, _, _, _ in selected
        if int(candidate["publication_year"] or 0) > year
        and _conclusion_polarity(str(candidate["conclusion"] or candidate["abstract_text"] or ""))
        not in {"unclear", own}
    ]
    if not newer:
        return ""
    latest = max(newer, key=lambda candidate: int(candidate["publication_year"] or 0))
    return f"A newer included study ({latest['publication_year']}) reports a different conclusion."


def _conclusion_polarity(value: str) -> str:
    lowered = value.lower()
    negative = ("no significant", "did not improve", "no effect", "not associated")
    positive = ("improved", "increased", "decreased", "benefit", "effective", "associated with")
    if any(term in lowered for term in negative):
        return "negative"
    if any(term in lowered for term in positive):
        return "positive"
    return "unclear"


def _quality_confidence(score: float) -> str:
    if score >= 0.9:
        return "high"
    if score >= 0.7:
        return "moderate"
    return "low"


def _chunk_text(document: EvidenceDocument) -> str:
    types = ", ".join(document.publication_types)
    keywords = ", ".join(document.keywords)
    return "\n".join(
        part
        for part in (
            document.title,
            f"Publication types: {types}" if types else "",
            f"Keywords: {keywords}" if keywords else "",
            document.abstract_text,
        )
        if part
    )


def _full_text_chunk(document: EvidenceDocument) -> str:
    structured = "\n".join(
        part
        for part in (
            f"Population: {document.population}" if document.population else "",
            f"Interventions: {'; '.join(document.interventions)}" if document.interventions else "",
            f"Outcomes: {'; '.join(document.outcomes)}" if document.outcomes else "",
            f"Constraints: {'; '.join(document.constraints)}" if document.constraints else "",
            f"Conclusion: {document.conclusion}" if document.conclusion else "",
        )
        if part
    )
    return f"{structured}\n{document.full_text}"[:120_000].strip()


def _clean_markup(value: str) -> str:
    with_breaks = re.sub(r"</?(?:h\d|p|br)[^>]*>", " ", value, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", html.unescape(re.sub(r"<[^>]+>", "", with_breaks))).strip()


def _list_value(value: Any, key: str) -> list[str]:
    if isinstance(value, dict):
        value = value.get(key, [])
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [str(item) for item in value if str(item).strip()]
    return []


def _fts_query(value: str) -> str:
    tokens = re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]+", value.lower())
    unique = []
    for token in tokens:
        if len(token) >= 2 and token not in unique:
            unique.append(token)
    return " OR ".join(f'"{token}"' for token in unique[:16])


def _json_vector(value: Any) -> list[float]:
    try:
        parsed = json.loads(str(value))
        return [float(item) for item in parsed] if isinstance(parsed, list) else []
    except (TypeError, ValueError, json.JSONDecodeError):
        return []


def _json_strings(value: Any) -> list[str]:
    try:
        parsed = json.loads(str(value))
        return [str(item) for item in parsed] if isinstance(parsed, list) else []
    except (TypeError, ValueError, json.JSONDecodeError):
        return []


def _relation_doi(relations: Any, key: str) -> str:
    if not isinstance(relations, dict):
        return ""
    values = relations.get(key, [])
    if isinstance(values, dict):
        values = [values]
    if not isinstance(values, list):
        return ""
    for value in values:
        if isinstance(value, dict):
            identifier = str(value.get("id") or value.get("doi") or "").lower().strip()
            if identifier:
                return identifier
    return ""


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def citation_dict(citation: EvidenceCitation) -> dict[str, Any]:
    return asdict(citation)

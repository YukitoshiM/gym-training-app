#!/usr/bin/env python3
"""Export the local evidence corpus for D1 and Cloudflare Vectorize."""

from __future__ import annotations

import argparse
import json
import sqlite3
import struct
from pathlib import Path

import sqlite_vec


def parse_args() -> argparse.Namespace:
    default_db = Path.home() / "Library/Application Support/BodyMode/evidence-rag.sqlite3"
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", type=Path, default=default_db)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--batch-size", type=int, default=200)
    return parser.parse_args()


def sql_text(value: object) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def json_array(value: object) -> list[str]:
    try:
        decoded = json.loads(str(value or "[]"))
    except (TypeError, ValueError, json.JSONDecodeError):
        return []
    return [str(item) for item in decoded] if isinstance(decoded, list) else []


def vector_values(blob: bytes, dimensions: int) -> list[float]:
    expected = dimensions * 4
    if len(blob) != expected:
        raise ValueError(f"Unexpected vector byte length: {len(blob)} != {expected}")
    return list(struct.unpack(f"<{dimensions}f", blob))


def main() -> None:
    args = parse_args()
    if not args.db.is_file():
        raise SystemExit(f"Evidence database not found: {args.db}")
    if args.batch_size < 1 or args.batch_size > 1_000:
        raise SystemExit("--batch-size must be between 1 and 1000")

    output = args.output.resolve()
    d1_output = output / "d1"
    d1_output.mkdir(parents=True, exist_ok=True)
    vectors_path = output / "vectors.ndjson"

    connection = sqlite3.connect(f"file:{args.db.resolve()}?mode=ro", uri=True)
    if not hasattr(connection, "enable_load_extension"):
        raise SystemExit(
            "Python with SQLite extension loading is required. "
            "Use local_llm_server/.venv/bin/python."
        )
    connection.enable_load_extension(True)
    sqlite_vec.load(connection)
    connection.enable_load_extension(False)
    connection.row_factory = sqlite3.Row

    config = connection.execute(
        "SELECT dimension, embedding_model FROM evidence_vector_config WHERE id = 1"
    ).fetchone()
    if config is None:
        raise SystemExit("Evidence vector configuration is missing")
    dimensions = int(config["dimension"])
    embedding_model = str(config["embedding_model"])

    rows = connection.execute(
        """
        SELECT
            c.id AS chunk_row_id,
            c.chunk_kind,
            c.text AS chunk_text,
            v.embedding,
            d.pmid,
            d.doi,
            d.title,
            d.abstract_text,
            d.source_url,
            d.publication_year,
            d.full_text_license,
            d.indexed_at,
            d.topics_json,
            d.goals_json,
            d.subtopics_json
        FROM evidence_chunks AS c
        JOIN evidence_documents AS d ON d.id = c.document_id
        JOIN evidence_chunks_vec AS v ON v.rowid = c.id
        ORDER BY c.id
        """
    ).fetchall()

    sql_batches: list[list[str]] = [[]]
    document_ids: set[str] = set()
    with vectors_path.open("w", encoding="utf-8") as vectors_file:
        for row in rows:
            document_id = str(row["pmid"] or row["doi"] or f"local:{row['chunk_row_id']}")
            chunk_id = f"chunk:{row['chunk_row_id']}"
            if document_id not in document_ids:
                document_ids.add(document_id)
                publication_date = str(row["publication_year"] or "")
                sql_batches[-1].append(
                    "INSERT OR REPLACE INTO evidence_documents("
                    "document_id, source, title, abstract, source_url, publication_date, "
                    "license, updated_at) VALUES ("
                    f"{sql_text(document_id)}, 'Europe PMC', {sql_text(row['title'])}, "
                    f"{sql_text(row['abstract_text'])}, {sql_text(row['source_url'])}, "
                    f"{sql_text(publication_date)}, {sql_text(row['full_text_license'])}, "
                    "unixepoch());"
                )

            purpose_tags = sorted(
                set(
                    json_array(row["topics_json"])
                    + json_array(row["goals_json"])
                    + json_array(row["subtopics_json"])
                )
            )
            sql_batches[-1].append(
                "INSERT OR REPLACE INTO evidence_chunks("
                "chunk_id, document_id, ordinal, content, purpose_tags, population_tags, "
                "updated_at) VALUES ("
                f"{sql_text(chunk_id)}, {sql_text(document_id)}, 0, "
                f"{sql_text(row['chunk_text'])}, {sql_text(json.dumps(purpose_tags))}, "
                "'[]', unixepoch());"
            )

            vector_record = {
                "id": chunk_id,
                "values": vector_values(row["embedding"], dimensions),
                "metadata": {
                    "document_id": document_id,
                    "chunk_kind": str(row["chunk_kind"]),
                },
            }
            vectors_file.write(json.dumps(vector_record, separators=(",", ":")) + "\n")

            if len(sql_batches[-1]) >= args.batch_size:
                sql_batches.append([])

    if sql_batches and not sql_batches[-1]:
        sql_batches.pop()
    for index, statements in enumerate(sql_batches, 1):
        path = d1_output / f"evidence-{index:04d}.sql"
        path.write_text("PRAGMA foreign_keys = ON;\n" + "\n".join(statements) + "\n", encoding="utf-8")

    manifest = {
        "schema_version": 1,
        "embedding_model": embedding_model,
        "dimensions": dimensions,
        "documents": len(document_ids),
        "vectors": len(rows),
        "d1_batches": len(sql_batches),
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(manifest, separators=(",", ":")))


if __name__ == "__main__":
    main()

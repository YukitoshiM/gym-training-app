from __future__ import annotations

import argparse
import asyncio
import json
import os
from dataclasses import replace
from pathlib import Path

import httpx

from evidence_rag import (
    DEFAULT_EVIDENCE_QUERIES,
    CrossrefClient,
    EvidenceDocument,
    EvidenceStore,
    EuropePMCClient,
    document_matches_topic,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sync BodyMode's local scientific evidence index.")
    parser.add_argument("--limit-per-topic", type=int, default=25)
    parser.add_argument("--skip-crossref", action="store_true")
    parser.add_argument("--skip-embeddings", action="store_true")
    return parser.parse_args()


async def ollama_embeddings(texts: list[str], model: str) -> list[list[float]]:
    if not texts:
        return []
    base_url = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
    async with httpx.AsyncClient(timeout=180.0) as client:
        response = await client.post(
            f"{base_url}/api/embed",
            json={"model": model, "input": texts, "truncate": True},
        )
        response.raise_for_status()
    values = response.json().get("embeddings", [])
    return [[float(item) for item in vector] for vector in values]


async def main() -> int:
    args = parse_args()
    database_path = Path(
        os.getenv(
            "EVIDENCE_RAG_DB_PATH",
            str(Path.home() / "Library/Application Support/BodyMode/evidence-rag.sqlite3"),
        )
    ).expanduser()
    embedding_model = os.getenv("EVIDENCE_EMBEDDING_MODEL", "bge-m3")
    store = EvidenceStore(database_path)
    store.record_sync(status="running")
    try:
        europe_pmc = EuropePMCClient()
        documents_by_pmid: dict[str, EvidenceDocument] = {}
        for topic, query in DEFAULT_EVIDENCE_QUERIES.items():
            for document in await europe_pmc.search(query, page_size=args.limit_per_topic):
                if not document_matches_topic(document, topic):
                    continue
                existing = documents_by_pmid.get(document.pmid)
                topics = set(existing.topics if existing else ())
                topics.add(topic)
                documents_by_pmid[document.pmid] = replace(
                    document,
                    topics=tuple(sorted(topics)),
                )

        documents = list(documents_by_pmid.values())
        if not args.skip_crossref:
            crossref = CrossrefClient(mailto=os.getenv("CROSSREF_MAILTO", ""))
            semaphore = asyncio.Semaphore(4)

            async def enrich(document: EvidenceDocument) -> EvidenceDocument:
                async with semaphore:
                    retracted, corrected = await crossref.update_flags(document.doi)
                return EvidenceDocument(
                    **{
                        **document.__dict__,
                        "retracted": document.retracted or retracted,
                        "corrected": document.corrected or corrected,
                    }
                )

            documents = list(await asyncio.gather(*(enrich(item) for item in documents)))

        vectors: dict[str, list[float]] = {}
        if not args.skip_embeddings and documents:
            for offset in range(0, len(documents), 16):
                batch = documents[offset : offset + 16]
                try:
                    embedded = await ollama_embeddings(
                        [f"{item.title}\n{item.abstract_text}"[:8000] for item in batch],
                        embedding_model,
                    )
                except httpx.HTTPError:
                    embedded = []
                if len(embedded) == len(batch):
                    vectors.update({item.pmid: vector for item, vector in zip(batch, embedded)})

        saved = store.upsert_documents(
            documents,
            embedding_model=embedding_model,
            vectors=vectors,
        )
        store.clear_topics_outside(item.pmid for item in documents)
        store.record_sync(status="completed", document_count=saved, completed=True)
        print(
            json.dumps(
                {
                    "status": "completed",
                    "database": str(database_path),
                    "documents": saved,
                    "vectors": len(vectors),
                    "topics": len(DEFAULT_EVIDENCE_QUERIES),
                },
                ensure_ascii=False,
            )
        )
        return 0
    except Exception as error:
        store.record_sync(status="failed", error_message=str(error), completed=True)
        print(json.dumps({"status": "failed", "error": str(error)}, ensure_ascii=False))
        return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))

from __future__ import annotations

import argparse
import asyncio
import json
import os
from dataclasses import replace
from datetime import datetime, timezone
from pathlib import Path

import httpx

from evidence_collection import EVIDENCE_COLLECTION_PLAN, collection_text_matches
from evidence_rag import (
    CrossrefClient,
    EvidenceDocument,
    EvidenceStore,
    EuropePMCClient,
    document_matches_topic,
)
from evidence_enrichment import (
    EuropePMCFullTextClient,
    enrich_document_structure,
    with_full_text,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Sync BodyMode's local scientific evidence index.")
    parser.add_argument("--limit-per-query", type=int, default=160)
    parser.add_argument("--limit-per-topic", type=int, dest="legacy_limit", help=argparse.SUPPRESS)
    parser.add_argument("--max-queries", type=int, default=0)
    parser.add_argument("--minimum-documents", type=int, default=1500)
    parser.add_argument("--crossref-limit", type=int, default=400)
    parser.add_argument("--full-text-limit", type=int, default=500)
    parser.add_argument("--skip-crossref", action="store_true")
    parser.add_argument("--skip-full-text", action="store_true")
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


def merge_document(
    existing: EvidenceDocument | None,
    incoming: EvidenceDocument,
    *,
    goal_ids: tuple[str, ...],
    topic: str,
    subtopic: str,
    collection_query: str,
) -> EvidenceDocument:
    return replace(
        existing or incoming,
        topics=tuple(sorted({*(existing.topics if existing else ()), topic})),
        goals=tuple(sorted({*(existing.goals if existing else ()), *goal_ids})),
        subtopics=tuple(sorted({*(existing.subtopics if existing else ()), subtopic})),
        collection_queries=tuple(
            sorted({*(existing.collection_queries if existing else ()), collection_query})
        ),
    )


async def collect_documents(
    *,
    limit_per_query: int,
    max_queries: int,
) -> dict[str, EvidenceDocument]:
    documents: dict[str, EvidenceDocument] = {}
    plan = EVIDENCE_COLLECTION_PLAN[:max_queries] if max_queries else EVIDENCE_COLLECTION_PLAN
    relevance_limit = max(1, int(limit_per_query * 0.375))
    recent_limit = max(1, int(limit_per_query * 0.3125))
    foundational_limit = max(1, limit_per_query - relevance_limit - recent_limit)
    current_year = datetime.now(timezone.utc).year
    semaphore = asyncio.Semaphore(4)

    async def collect_item(item):
        async with semaphore:
            europe_pmc = EuropePMCClient()
            batches = [
                await europe_pmc.search_pages(
                    item.query,
                    max_results=relevance_limit,
                    sort="relevance",
                )
            ]
            if recent_limit:
                recent_query = (
                    f"({item.query}) AND FIRST_PDATE:[2017-01-01 TO {current_year}-12-31]"
                )
                batches.append(
                    await europe_pmc.search_pages(
                        recent_query,
                        max_results=recent_limit,
                        sort="recent",
                    )
                )
            if foundational_limit:
                foundational_query = (
                    f"({item.query}) AND FIRST_PDATE:[1990-01-01 TO 2016-12-31]"
                )
                batches.append(
                    await europe_pmc.search_pages(
                        foundational_query,
                        max_results=foundational_limit,
                        sort="relevance",
                    )
                )
            return item, batches

    results = await asyncio.gather(*(collect_item(item) for item in plan))
    for index, (item, batches) in enumerate(results, 1):
        for document in (document for batch in batches for document in batch):
            special_match = collection_text_matches(
                item.identifier,
                document.title,
                document.abstract_text,
            )
            topic_match = (
                special_match
                if special_match is not None
                else document_matches_topic(document, item.topic)
            )
            if not document.abstract_text or not topic_match:
                continue
            documents[document.pmid] = merge_document(
                documents.get(document.pmid),
                document,
                goal_ids=item.goals,
                topic=item.topic,
                subtopic=item.subtopic,
                collection_query=item.identifier,
            )
        if index % 5 == 0 or index == len(plan):
            print(
                json.dumps(
                    {
                        "stage": "collect",
                        "queries_completed": index,
                        "queries_total": len(plan),
                        "unique_documents": len(documents),
                    }
                ),
                flush=True,
            )
    return documents


async def enrich_crossref(
    documents: list[EvidenceDocument],
    *,
    limit: int,
) -> list[EvidenceDocument]:
    if limit <= 0:
        return documents
    selected_pmids = {
        item.pmid
        for item in sorted(
            (item for item in documents if item.doi),
            key=lambda item: (item.quality_score, item.publication_year or 0),
            reverse=True,
        )[:limit]
    }
    crossref = CrossrefClient(mailto=os.getenv("CROSSREF_MAILTO", ""))
    semaphore = asyncio.Semaphore(6)

    async def enrich(document: EvidenceDocument) -> EvidenceDocument:
        if document.pmid not in selected_pmids:
            return document
        async with semaphore:
            status = await crossref.update_status(document.doi)
        return replace(
            document,
            retracted=document.retracted or status.retracted,
            corrected=document.corrected or status.corrected,
            correction_of_doi=status.correction_of_doi,
            corrected_by_doi=status.corrected_by_doi,
            version_status="superseded" if status.corrected_by_doi else document.version_status,
        )

    return list(await asyncio.gather(*(enrich(item) for item in documents)))


async def enrich_full_text(
    documents: list[EvidenceDocument],
    *,
    limit: int,
) -> list[EvidenceDocument]:
    selected_pmids = {
        item.pmid
        for item in sorted(
            (item for item in documents if item.is_open_access and item.pmcid),
            key=lambda item: (item.quality_score, item.publication_year or 0),
            reverse=True,
        )[: max(0, limit)]
    }
    client = EuropePMCFullTextClient()
    semaphore = asyncio.Semaphore(4)

    async def enrich(document: EvidenceDocument) -> EvidenceDocument:
        if document.pmid not in selected_pmids:
            return enrich_document_structure(document)
        async with semaphore:
            full_text = await client.fetch(document)
        return (
            with_full_text(document, full_text)
            if full_text is not None
            else enrich_document_structure(document)
        )

    return list(await asyncio.gather(*(enrich(item) for item in documents)))


async def embed_documents(
    documents: list[EvidenceDocument],
    *,
    model: str,
    existing_vectors: dict[str, list[float]] | None = None,
) -> dict[str, list[float]]:
    vectors = dict(existing_vectors or {})
    pending = [item for item in documents if item.pmid not in vectors]
    for offset in range(0, len(pending), 24):
        batch = pending[offset : offset + 24]
        embedded = await ollama_embeddings(
            [f"{item.title}\n{item.abstract_text}"[:8000] for item in batch],
            model,
        )
        if len(embedded) != len(batch):
            raise RuntimeError(
                f"embedding count mismatch at offset {offset}: {len(embedded)} != {len(batch)}"
            )
        vectors.update({item.pmid: vector for item, vector in zip(batch, embedded)})
        if offset == 0 or offset + len(batch) == len(pending) or offset % 240 == 0:
            print(
                json.dumps(
                    {
                        "stage": "embed",
                        "embedded": len(vectors),
                        "total": len(documents),
                        "reused": len(existing_vectors or {}),
                    }
                ),
                flush=True,
            )
    return vectors


async def main() -> int:
    args = parse_args()
    limit_per_query = args.legacy_limit or args.limit_per_query
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
        documents_by_pmid = await collect_documents(
            limit_per_query=max(2, limit_per_query),
            max_queries=max(0, args.max_queries),
        )
        documents = list(documents_by_pmid.values())
        if len(documents) < args.minimum_documents:
            raise RuntimeError(
                f"collection validation failed: {len(documents)} documents; "
                f"minimum is {args.minimum_documents}"
            )
        if not args.skip_crossref:
            documents = await enrich_crossref(documents, limit=max(0, args.crossref_limit))
        if not args.skip_full_text:
            documents = await enrich_full_text(documents, limit=max(0, args.full_text_limit))
        else:
            documents = [enrich_document_structure(item) for item in documents]

        vectors: dict[str, list[float]] = {}
        if not args.skip_embeddings:
            existing_vectors = store.existing_vectors(
                (item.pmid for item in documents),
                embedding_model=embedding_model,
            )
            vectors = await embed_documents(
                documents,
                model=embedding_model,
                existing_vectors=existing_vectors,
            )
            if len(vectors) != len(documents):
                raise RuntimeError("not every document received an embedding")

        saved = store.upsert_documents(
            documents,
            embedding_model=embedding_model,
            vectors=vectors,
            replace_existing=True,
        )
        store.record_sync(status="completed", document_count=saved, completed=True)
        status = store.status()
        print(
            json.dumps(
                {
                    "status": "completed",
                    "database": str(database_path),
                    "documents": saved,
                    "vectors": len(vectors),
                    "collection_queries": len(EVIDENCE_COLLECTION_PLAN),
                    "goal_counts": status["goal_counts"],
                    "full_text_documents": status["full_text_documents"],
                    "sqlite_vec_version": status["sqlite_vec_version"],
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

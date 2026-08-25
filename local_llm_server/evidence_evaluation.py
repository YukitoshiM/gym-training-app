from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable

from evidence_rag import EvidenceStore, EvidenceUserProfile


@dataclass(frozen=True)
class EvaluationCase:
    identifier: str
    purpose: str
    query: str
    goal: str
    expected_subtopics: tuple[str, ...]
    user_profile: EvidenceUserProfile = EvidenceUserProfile()


def load_evaluation_set(path: Path) -> list[EvaluationCase]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return [
        EvaluationCase(
            identifier=str(item["id"]),
            purpose=str(item["purpose"]),
            query=str(item["query"]),
            goal=str(item["goal"]),
            expected_subtopics=tuple(item.get("expected_subtopics", [])),
            user_profile=EvidenceUserProfile(**item.get("user_profile", {})),
        )
        for item in payload["cases"]
    ]


def evaluate(
    store: EvidenceStore,
    cases: Iterable[EvaluationCase],
    *,
    k: int = 5,
) -> dict[str, Any]:
    case_results = []
    for case in cases:
        relevant_ids = _relevant_document_ids(store, case)
        result = store.search(
            case.query,
            goal=case.goal,
            purpose=case.purpose,
            user_profile=case.user_profile,
            limit=k,
        )
        returned_ids = {citation.id.removeprefix("PMID:") for citation in result.citations}
        hits = returned_ids & relevant_ids
        recall = len(hits) / len(relevant_ids) if relevant_ids else None
        relevance = len(hits) / len(returned_ids) if returned_ids else 0.0
        case_results.append(
            {
                "id": case.identifier,
                "purpose": case.purpose,
                "relevant_documents": len(relevant_ids),
                "returned_documents": len(returned_ids),
                "recall_at_k": round(recall, 4) if recall is not None else None,
                "relevance_precision": round(relevance, 4),
                "retraction_safety": _returned_documents_are_safe(store, returned_ids),
                "population_match_rate": round(
                    sum(citation.applicability_label != "mismatch" for citation in result.citations)
                    / len(result.citations),
                    4,
                ) if result.citations else 0.0,
                "state": result.state,
            }
        )
    return aggregate_evaluation(case_results, k=k)


def aggregate_evaluation(case_results: list[dict[str, Any]], *, k: int) -> dict[str, Any]:
    recalls = [item["recall_at_k"] for item in case_results if item["recall_at_k"] is not None]
    return {
        "cases": len(case_results),
        "k": k,
        "recall_at_k": round(sum(recalls) / len(recalls), 4) if recalls else None,
        "relevance_precision": _mean(case_results, "relevance_precision"),
        "retraction_safety_rate": round(
            sum(bool(item["retraction_safety"]) for item in case_results) / len(case_results), 4
        ) if case_results else 0.0,
        "population_match_rate": _mean(case_results, "population_match_rate"),
        "by_purpose": {
            purpose: {
                "cases": len(items),
                "recall_at_k": _nullable_mean(items, "recall_at_k"),
                "relevance_precision": _mean(items, "relevance_precision"),
                "population_match_rate": _mean(items, "population_match_rate"),
            }
            for purpose in sorted({item["purpose"] for item in case_results})
            for items in [[item for item in case_results if item["purpose"] == purpose]]
        },
        "results": case_results,
    }


def _relevant_document_ids(store: EvidenceStore, case: EvaluationCase) -> set[str]:
    with store.connect() as connection:
        rows = connection.execute(
            """
            SELECT pmid, goals_json, subtopics_json
            FROM evidence_documents
            WHERE retracted = 0 AND version_status != 'superseded'
            """
        ).fetchall()
    expected = set(case.expected_subtopics)
    relevant = set()
    for row in rows:
        goals = set(json.loads(row["goals_json"]))
        subtopics = set(json.loads(row["subtopics_json"]))
        if case.goal in goals and expected.intersection(subtopics):
            relevant.add(str(row["pmid"]))
    return relevant


def _returned_documents_are_safe(store: EvidenceStore, pmids: set[str]) -> bool:
    if not pmids:
        return True
    placeholders = ",".join("?" for _ in pmids)
    with store.connect() as connection:
        count = connection.execute(
            f"""
            SELECT COUNT(*) FROM evidence_documents
            WHERE pmid IN ({placeholders})
              AND (retracted = 1 OR version_status = 'superseded')
            """,
            tuple(sorted(pmids)),
        ).fetchone()[0]
    return int(count) == 0


def _mean(items: list[dict[str, Any]], key: str) -> float:
    return round(sum(float(item[key]) for item in items) / len(items), 4) if items else 0.0


def _nullable_mean(items: list[dict[str, Any]], key: str):
    values = [float(item[key]) for item in items if item[key] is not None]
    return round(sum(values) / len(values), 4) if values else None


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate BodyMode evidence retrieval.")
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument(
        "--cases",
        type=Path,
        default=Path(__file__).with_name("evidence_evaluation_set.json"),
    )
    parser.add_argument("--k", type=int, default=5)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    report = evaluate(EvidenceStore(args.database), load_evaluation_set(args.cases), k=args.k)
    value = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(value + "\n", encoding="utf-8")
    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

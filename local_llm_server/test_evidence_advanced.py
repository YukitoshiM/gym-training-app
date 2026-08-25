from __future__ import annotations

import asyncio
import json
import tempfile
import unittest
from dataclasses import replace
from pathlib import Path

import httpx

from evidence_enrichment import (
    EuropePMCFullTextClient,
    enrich_document_structure,
    parse_reusable_full_text,
    with_full_text,
)
from evidence_evaluation import EvaluationCase, evaluate
from evidence_monitoring import EvidenceMonitor, EvidenceObservation
from evidence_rag import (
    CrossrefClient,
    EvidenceDocument,
    EvidenceStore,
    EvidenceUserProfile,
)
from main import claim_citation_links


def document(
    pmid: str,
    title: str,
    *,
    population: str = "healthy trained adults",
    year: int = 2024,
    retracted: bool = False,
    version_status: str = "current",
    conclusion: str = "Resistance training improved strength.",
    subtopics: tuple[str, ...] = ("training_volume",),
) -> EvidenceDocument:
    return EvidenceDocument(
        pmid=pmid,
        pmcid=f"PMC{pmid}",
        doi=f"10.1000/{pmid}",
        title=title,
        abstract_text=(
            f"Participants were {population}. Resistance training was performed. "
            f"{conclusion} Limitations include a small sample."
        ),
        authors="Test Author",
        journal="Test Journal",
        publication_year=year,
        publication_types=("Systematic Review",),
        keywords=("resistance training", "strength"),
        source_url=f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/",
        is_open_access=True,
        retracted=retracted,
        corrected=False,
        study_type="systematic_review",
        quality_score=0.9,
        source_updated_at="2026-01-01",
        topics=("strength",),
        goals=("strength",),
        subtopics=subtopics,
        population=population,
        interventions=("Resistance training was performed.",),
        outcomes=(conclusion,),
        constraints=("Small sample.",),
        conclusion=conclusion,
        version_status=version_status,
    )


class FullTextSafetyTests(unittest.TestCase):
    def test_full_text_requires_explicit_reusable_license(self) -> None:
        body = "<body><sec><title>Results</title><p>" + ("Useful result. " * 30) + "</p></sec></body>"
        closed = f"<article><front><article-meta><permissions><license>All rights reserved</license></permissions></article-meta></front>{body}</article>"
        reusable = f"<article><front><article-meta><permissions><license>Creative Commons CC BY 4.0</license></permissions></article-meta></front>{body}</article>"
        noncommercial = f"<article><front><article-meta><permissions><license>Creative Commons CC BY-NC 4.0</license></permissions></article-meta></front>{body}</article>"

        self.assertIsNone(parse_reusable_full_text(closed, source_url="closed"))
        self.assertIsNone(parse_reusable_full_text(noncommercial, source_url="noncommercial"))
        parsed = parse_reusable_full_text(reusable, source_url="oa")
        self.assertIsNotNone(parsed)
        self.assertEqual(parsed.source_url, "oa")
        self.assertIn("cc by", parsed.license_name)

    def test_client_does_not_request_non_oa_or_missing_pmcid(self) -> None:
        requests: list[httpx.Request] = []

        def handler(request: httpx.Request) -> httpx.Response:
            requests.append(request)
            return httpx.Response(500)

        client = EuropePMCFullTextClient(transport=httpx.MockTransport(handler))
        value = asyncio.run(client.fetch(replace(document("1", "Study"), is_open_access=False)))
        self.assertIsNone(value)
        self.assertEqual(requests, [])

    def test_structure_extracts_pico_and_constraints(self) -> None:
        raw = replace(
            document("2", "Structured study"),
            population="",
            interventions=(),
            outcomes=(),
            constraints=(),
            conclusion="",
        )
        enriched = enrich_document_structure(raw)
        self.assertIn("Participants", enriched.population)
        self.assertTrue(enriched.interventions)
        self.assertTrue(enriched.outcomes)
        self.assertTrue(enriched.constraints)
        self.assertTrue(enriched.conclusion)


class RetrievalSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = tempfile.TemporaryDirectory()
        self.store = EvidenceStore(Path(self.directory.name) / "evidence.sqlite3")

    def tearDown(self) -> None:
        self.directory.cleanup()

    def test_full_text_is_distinguished_and_details_are_returned(self) -> None:
        base = document("10", "Resistance training volume for strength")
        enriched = with_full_text(
            base,
            parse_reusable_full_text(
                "<article><front><article-meta><permissions><license>CC BY 4.0</license></permissions></article-meta></front>"
                "<body><sec><title>Results</title><p>" + ("Training volume improved strength outcomes. " * 20) + "</p></sec></body></article>",
                source_url="https://example.test/full",
            ),
        )
        self.store.upsert_documents([enriched])

        result = self.store.search("strength training volume", goal="strength")

        self.assertEqual(result.state, "ready")
        self.assertEqual(result.citations[0].source_scope, "full_text")
        self.assertTrue(result.citations[0].evidence_summary)
        self.assertTrue(result.citations[0].limitations)
        self.assertEqual(self.store.status()["full_text_documents"], 1)

    def test_population_mismatch_is_explicit_and_not_returned(self) -> None:
        self.store.upsert_documents(
            [document("11", "Training volume in adolescents", population="adolescent athletes")]
        )
        result = self.store.search(
            "strength training volume",
            goal="strength",
            user_profile=EvidenceUserProfile(age=70, population_tags=("older adults",)),
        )
        self.assertEqual(result.state, "population_mismatch")
        self.assertEqual(result.citations, ())
        self.assertIn("population", result.reason.lower())

    def test_applicability_reranks_matching_population(self) -> None:
        self.store.upsert_documents(
            [
                document("12", "Training volume in trained athletes", population="trained athletes"),
                document("13", "Training volume in novice adults", population="untrained novice adults"),
            ]
        )
        result = self.store.search(
            "strength training volume",
            goal="strength",
            user_profile=EvidenceUserProfile(experience_level="beginner"),
        )
        self.assertEqual(result.citations[0].id, "PMID:13")
        self.assertEqual(result.citations[0].applicability_label, "direct")

    def test_retracted_and_superseded_versions_are_excluded(self) -> None:
        self.store.upsert_documents(
            [
                document("14", "Retracted strength training volume", retracted=True),
                document("15", "Superseded strength training volume", version_status="superseded"),
                document("16", "Current strength training volume"),
            ]
        )
        result = self.store.search("strength training volume", goal="strength")
        self.assertEqual([item.id for item in result.citations], ["PMID:16"])

    def test_newer_conflicting_conclusion_is_flagged(self) -> None:
        self.store.upsert_documents(
            [
                document("17", "Older training volume review", year=2020),
                document(
                    "18",
                    "Newer training volume review",
                    year=2025,
                    conclusion="Training volume had no significant effect on strength.",
                ),
            ]
        )
        result = self.store.search("strength training volume", goal="strength")
        by_id = {item.id: item for item in result.citations}
        self.assertEqual(by_id["PMID:17"].conclusion_consistency, "mixed")
        self.assertIn("newer", by_id["PMID:17"].newer_evidence_note.lower())


class CrossrefVersionTests(unittest.TestCase):
    def test_crossref_relation_identifies_superseded_work(self) -> None:
        def handler(_: httpx.Request) -> httpx.Response:
            return httpx.Response(
                200,
                json={"message": {"relation": {"is-corrected-by": [{"id": "10.1000/new"}]}}},
            )

        status = asyncio.run(
            CrossrefClient(transport=httpx.MockTransport(handler)).update_status("10.1000/old")
        )
        self.assertEqual(status.corrected_by_doi, "10.1000/new")


class ContractAndEvaluationTests(unittest.TestCase):
    def test_claims_are_mapped_only_to_known_citations(self) -> None:
        links = claim_citation_links(
            "筋力は改善しました。[E1]\n未知の出典です。[E8]",
            {"E1": "PMID:1"},
        )
        self.assertEqual(links, [{"claim": "筋力は改善しました。", "citation_ids": ["PMID:1"]}])

    def test_purpose_evaluation_reports_all_safety_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            store = EvidenceStore(Path(directory) / "evidence.sqlite3")
            store.upsert_documents([document("20", "Strength training volume review")])
            report = evaluate(
                store,
                [
                    EvaluationCase(
                        identifier="strength",
                        purpose="plan_generation",
                        query="strength training volume",
                        goal="strength",
                        expected_subtopics=("training_volume",),
                    )
                ],
                k=5,
            )
        self.assertEqual(report["recall_at_k"], 1.0)
        self.assertEqual(report["relevance_precision"], 1.0)
        self.assertEqual(report["retraction_safety_rate"], 1.0)
        self.assertEqual(report["population_match_rate"], 1.0)
        self.assertIn("plan_generation", report["by_purpose"])

    def test_monitor_reports_latency_cost_and_failure_rate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            monitor = EvidenceMonitor(
                Path(directory) / "monitor.sqlite3",
                cost_per_million_characters=2.0,
            )
            monitor.record(
                EvidenceObservation(
                    request_id="one",
                    purpose="chat",
                    state="ready",
                    total_latency_ms=100,
                    matched_documents=2,
                    prompt_characters=1_000,
                    estimated_cost_usd=monitor.estimated_cost(1_000),
                )
            )
            monitor.record(
                EvidenceObservation(
                    request_id="two",
                    purpose="chat",
                    state="unavailable",
                    total_latency_ms=300,
                    failure_type="OperationalError",
                )
            )
            report = monitor.summary(purpose="chat")
        self.assertEqual(report["requests"], 2)
        self.assertEqual(report["failure_rate"], 0.5)
        self.assertEqual(report["latency_ms"]["p95"], 300)
        self.assertGreater(report["estimated_cost_usd"], 0)


if __name__ == "__main__":
    unittest.main()

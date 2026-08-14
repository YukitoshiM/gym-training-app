import asyncio
import json
import tempfile
import unittest
from pathlib import Path

import httpx

from evidence_collection import (
    EVIDENCE_COLLECTION_PLAN,
    SUPPORTED_EVIDENCE_GOALS,
    collection_text_matches,
)
from evidence_rag import (
    EvidenceDocument,
    EvidenceStore,
    EuropePMCClient,
    detect_query_subtopics,
    detect_query_topics,
    document_matches_topic,
    parse_europe_pmc_document,
)


def make_document(
    pmid: str,
    title: str,
    *,
    abstract: str = "",
    study_type: str = "systematic_review",
    quality: float = 0.9,
    retracted: bool = False,
    topics: tuple[str, ...] = ("hypertrophy",),
) -> EvidenceDocument:
    return EvidenceDocument(
        pmid=pmid,
        pmcid="",
        doi=f"10.1000/{pmid}",
        title=title,
        abstract_text=abstract,
        authors="Test Author",
        journal="Test Journal",
        publication_year=2025,
        publication_types=("Systematic Review",),
        keywords=("resistance training", "hypertrophy"),
        source_url=f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/",
        is_open_access=False,
        retracted=retracted,
        corrected=False,
        study_type=study_type,
        quality_score=quality,
        source_updated_at="2025-01-01",
        topics=topics,
    )


class EvidenceStoreTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.store = EvidenceStore(Path(self.temporary_directory.name) / "evidence.sqlite3")

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_japanese_query_uses_aliases_to_find_english_research(self) -> None:
        self.store.upsert_documents(
            [
                make_document(
                    "1001",
                    "Resistance training volume and muscle hypertrophy",
                    abstract="A systematic review of dose response relationships.",
                )
            ]
        )

        result = self.store.search("筋肥大のためにセット数を増やすべき？")

        self.assertEqual([citation.id for citation in result.citations], ["PMID:1001"])
        self.assertIn("[E1]", result.prompt_context)
        self.assertEqual(result.searched_documents, 1)

    def test_retracted_document_is_never_returned(self) -> None:
        self.store.upsert_documents(
            [
                make_document(
                    "1002",
                    "Protein and muscle hypertrophy",
                    retracted=True,
                    topics=("protein",),
                )
            ]
        )

        result = self.store.search("タンパク質と筋肥大")

        self.assertEqual(result.citations, ())
        self.assertEqual(result.searched_documents, 0)

    def test_vector_search_can_retrieve_when_lexical_terms_do_not_overlap(self) -> None:
        document = make_document("1003", "Progressive overload in trained adults")
        self.store.upsert_documents(
            [document],
            embedding_model="test-vector",
            vectors={document.pmid: [1.0, 0.0]},
        )

        result = self.store.search("unrelated words", query_vector=[1.0, 0.0])

        self.assertEqual(result.citations[0].id, "PMID:1003")
        self.assertLessEqual(result.citations[0].relevance, 1.0)
        self.assertEqual(
            self.store.existing_vectors([document.pmid], embedding_model="test-vector"),
            {document.pmid: [1.0, 0.0]},
        )

    def test_legacy_json_vectors_are_migrated_to_sqlite_vec(self) -> None:
        document = make_document("1007", "Legacy progressive overload evidence")
        self.store.upsert_documents([document])
        with self.store.connect() as connection:
            connection.execute(
                "UPDATE evidence_chunks SET embedding_model = 'legacy', vector_json = ?",
                (json.dumps([0.0, 1.0]),),
            )

        status = self.store.status()
        result = self.store.search("unrelated query", query_vector=[0.0, 1.0])

        self.assertEqual(status["vector_chunks"], 1)
        self.assertEqual(status["vector_dimension"], 2)
        self.assertEqual(status["sqlite_vec_version"], "0.1.9")
        self.assertEqual(result.citations[0].id, "PMID:1007")
        with self.store.connect() as connection:
            remaining = connection.execute(
                "SELECT COUNT(*) FROM evidence_chunks WHERE vector_json IS NOT NULL"
            ).fetchone()[0]
        self.assertEqual(remaining, 0)

    def test_europe_pmc_parser_cleans_markup_and_classifies_meta_analysis(self) -> None:
        document = parse_europe_pmc_document(
            {
                "pmid": "1004",
                "title": "<i>Resistance</i> training &amp; strength",
                "abstractText": "<p>Useful result.</p>",
                "pubYear": "2024",
                "pubTypeList": {"pubType": ["Meta-Analysis"]},
            }
        )

        self.assertEqual(document.title, "Resistance training & strength")
        self.assertEqual(document.abstract_text, "Useful result.")
        self.assertEqual(document.study_type, "meta_analysis")

    def test_topic_filter_rejects_incidental_protein_and_non_sleep_recovery_mentions(self) -> None:
        beetroot = make_document(
            "1005",
            "Beetroot juice and exercise-induced muscle damage",
            abstract="Protein carbonyl and recovery markers were measured after exercise.",
        )
        water_immersion = make_document(
            "1006",
            "Cold-water immersion and performance recovery",
            abstract="Sleep was one of several secondary recovery considerations.",
        )

        self.assertFalse(document_matches_topic(beetroot, "protein"))
        self.assertFalse(document_matches_topic(water_immersion, "sleep_recovery"))

    def test_japanese_steps_and_retraining_queries_detect_their_topics(self) -> None:
        self.assertIn("wellness", detect_query_topics("健康のために一日何歩？"))
        self.assertIn(
            "return_to_training",
            detect_query_topics("ブランク後に運動を再開したい"),
        )
        self.assertEqual(
            detect_query_subtopics("ブランク後に運動を再開したい"),
            {"detraining_retraining", "physical_inactivity"},
        )


class EuropePMCClientTests(unittest.TestCase):
    def test_cursor_pagination_collects_until_requested_limit(self) -> None:
        requests = []

        def handler(request: httpx.Request) -> httpx.Response:
            requests.append(request)
            cursor = request.url.params.get("cursorMark")
            start = 1 if cursor == "*" else 3
            results = [
                {
                    "pmid": str(index),
                    "title": f"Resistance training strength study {index}",
                    "abstractText": "Resistance training improves strength.",
                    "pubYear": "2025",
                }
                for index in range(start, start + 2)
            ]
            return httpx.Response(
                200,
                json={
                    "nextCursorMark": "page-two" if cursor == "*" else "page-three",
                    "resultList": {"result": results},
                },
            )

        client = EuropePMCClient(transport=httpx.MockTransport(handler))
        documents = asyncio.run(
            client.search_pages("test", max_results=3, sort="recent")
        )

        self.assertEqual([item.pmid for item in documents], ["1", "2", "3"])
        self.assertEqual(len(requests), 2)
        self.assertEqual(requests[0].url.params["sort"], "FIRST_PDATE_D desc")


class EvidenceCollectionPlanTests(unittest.TestCase):
    def test_plan_covers_every_bodymode_goal_and_major_research_area(self) -> None:
        self.assertEqual(
            set(SUPPORTED_EVIDENCE_GOALS),
            {
                "athletic_performance",
                "body_recomposition",
                "fat_loss",
                "hypertrophy",
                "return_to_training",
                "strength",
                "wellness",
            },
        )
        subtopics = {item.subtopic for item in EVIDENCE_COLLECTION_PLAN}
        self.assertTrue(
            {
                "training_volume",
                "protein_dose",
                "energy_deficit",
                "daily_steps",
                "readiness_monitoring",
                "return_to_sport",
            }.issubset(subtopics)
        )
        self.assertGreaterEqual(len(EVIDENCE_COLLECTION_PLAN), 40)

    def test_detraining_collection_requires_the_concept_in_the_title(self) -> None:
        self.assertTrue(
            collection_text_matches(
                "ret_detraining",
                "Effects of detraining and retraining on muscle strength",
                "Exercise training was evaluated.",
            )
        )
        self.assertFalse(
            collection_text_matches(
                "ret_detraining",
                "Rehabilitation after patellar fracture",
                "Proprioceptive retraining supported return to sport.",
            )
        )


if __name__ == "__main__":
    unittest.main()

import tempfile
import unittest
from pathlib import Path

from evidence_rag import (
    EvidenceDocument,
    EvidenceStore,
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


if __name__ == "__main__":
    unittest.main()

import tempfile
import unittest
from pathlib import Path

from check_public_legal_pages import check_pages, marker_digest
from prepare_public_legal_pages import PAGES, prepare, source_digest


class PreparePublicLegalPagesTests(unittest.TestCase):
    def test_renders_all_pages_with_front_matter_and_language_links(self) -> None:
        repository = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            written = prepare(repository / "docs" / "legal", output)

            self.assertEqual(len(written), len(PAGES))
            privacy = (output / "privacy.md").read_text(encoding="utf-8")
            english_terms = (output / "en" / "terms.md").read_text(encoding="utf-8")
            self.assertIn("permalink: /privacy/", privacy)
            self.assertIn("[English]", privacy)
            self.assertIn("Cloudflare", privacy)
            self.assertIn("OpenAI", privacy)
            self.assertEqual(
                marker_digest(privacy),
                source_digest(repository / "docs" / "legal" / "privacy-policy-ja.md"),
            )
            self.assertIn("lang: en", english_terms)
            self.assertIn("permalink: /en/terms/", english_terms)

    def test_rejects_a_source_with_the_wrong_heading(self) -> None:
        from prepare_public_legal_pages import render

        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "bad.md"
            source.write_text("# Wrong\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                render(source, "Expected", "/expected/", "English")

    def test_public_check_accepts_matching_rendered_pages(self) -> None:
        repository = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            prepare(repository / "docs" / "legal", output)

            payloads = {
                permalink: (output / output_name).read_text(encoding="utf-8")
                for _, output_name, _, permalink, _ in PAGES
            }

            def fetcher(url: str, _: float) -> str:
                permalink = "/" + url.split("/", 3)[-1].split("/", 1)[-1]
                if not permalink.endswith("/"):
                    permalink += "/"
                return payloads[permalink]

            results = check_pages(
                repository / "docs" / "legal",
                "https://example.com/root",
                fetcher=fetcher,
            )
            self.assertTrue(all(result.passed for result in results))

    def test_public_check_rejects_missing_or_stale_markers(self) -> None:
        repository = Path(__file__).resolve().parents[1]
        results = check_pages(
            repository / "docs" / "legal",
            "https://example.com/root",
            fetcher=lambda _url, _timeout: "<html>old page</html>",
        )
        self.assertEqual(len(results), len(PAGES))
        self.assertTrue(all(not result.passed for result in results))
        self.assertTrue(all(result.error == "source marker is missing" for result in results))


if __name__ == "__main__":
    unittest.main()

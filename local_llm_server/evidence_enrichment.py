from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, replace
from typing import Iterable, Optional

import httpx

from evidence_rag import EvidenceDocument


EUROPE_PMC_FULL_TEXT_URL = (
    "https://www.ebi.ac.uk/europepmc/webservices/rest/{pmcid}/fullTextXML"
)

# Only licenses that explicitly permit reuse are accepted. A free-to-read page is not enough.
REUSABLE_OA_LICENSES = {
    "cc by",
    "cc-by",
    "cc0",
    "public domain",
}


@dataclass(frozen=True)
class FullTextEnrichment:
    text: str
    license_name: str
    source_url: str


class EuropePMCFullTextClient:
    def __init__(
        self,
        *,
        timeout_seconds: float = 30.0,
        transport: Optional[httpx.AsyncBaseTransport] = None,
    ):
        self.timeout_seconds = timeout_seconds
        self.transport = transport

    async def fetch(self, document: EvidenceDocument) -> Optional[FullTextEnrichment]:
        if not document.is_open_access or not document.pmcid:
            return None
        url = EUROPE_PMC_FULL_TEXT_URL.format(pmcid=document.pmcid)
        try:
            async with httpx.AsyncClient(
                timeout=self.timeout_seconds,
                transport=self.transport,
                headers={"User-Agent": "BodyMode-Evidence-RAG/0.3"},
            ) as client:
                response = await client.get(url)
                response.raise_for_status()
        except httpx.HTTPError:
            return None
        return parse_reusable_full_text(response.text, source_url=url)


def parse_reusable_full_text(xml_text: str, *, source_url: str) -> Optional[FullTextEnrichment]:
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return None
    license_nodes = root.findall(".//license")
    license_text = " ".join(
        " ".join(
            (
                " ".join(node.itertext()).strip(),
                " ".join(str(value) for value in node.attrib.values()),
            )
        ).strip()
        for node in license_nodes
    ).strip()
    normalized_license = re.sub(r"\s+", " ", license_text).lower()
    disallowed = (
        "all rights reserved",
        "not licensed under",
        "cc by-nc",
        "cc-by-nc",
        "/licenses/by-nc",
        "cc by-nd",
        "cc-by-nd",
        "/licenses/by-nd",
        "cc by-sa",
        "cc-by-sa",
        "/licenses/by-sa",
    )
    if any(value in normalized_license for value in disallowed):
        return None
    license_name = ""
    for name in sorted(REUSABLE_OA_LICENSES, key=len, reverse=True):
        if name in normalized_license:
            license_name = name
            break
    if "creativecommons.org/licenses/" in normalized_license and not license_name:
        match = re.search(r"creativecommons\.org/licenses/([^/\s]+)", normalized_license)
        license_name = f"cc {match.group(1).replace('-', ' ')}" if match else ""
    if not license_name:
        return None
    body = root.find(".//body")
    if body is None:
        return None
    sections: list[str] = []
    for section in body.findall(".//sec"):
        title = " ".join(section.findtext("title", default="").split())
        paragraphs = [
            " ".join(" ".join(paragraph.itertext()).split())
            for paragraph in section.findall("./p")
        ]
        value = "\n".join(part for part in (title, *paragraphs) if part)
        if value:
            sections.append(value)
    text = "\n\n".join(sections)
    if not text:
        text = " ".join(" ".join(body.itertext()).split())
    text = text[:120_000].strip()
    if len(text) < 200:
        return None
    return FullTextEnrichment(text=text, license_name=license_name, source_url=source_url)


def enrich_document_structure(document: EvidenceDocument) -> EvidenceDocument:
    source = document.full_text or document.abstract_text
    population = document.population or _first_matching_sentence(
        source,
        ("participant", "adult", "men", "women", "athlete", "trained", "untrained", "older"),
    )
    interventions = document.interventions or _matching_sentences(
        source,
        ("training", "exercise", "supplement", "protein", "diet", "intervention"),
        maximum=3,
    )
    outcomes = document.outcomes or _matching_sentences(
        source,
        ("result", "increased", "decreased", "improved", "effect", "change", "difference"),
        maximum=3,
    )
    constraints = document.constraints or _matching_sentences(
        source,
        ("limitation", "limited", "uncertain", "heterogeneity", "small sample", "short duration"),
        maximum=3,
    )
    conclusion = document.conclusion or _conclusion_sentence(source)
    return replace(
        document,
        population=population[:800],
        interventions=tuple(item[:800] for item in interventions),
        outcomes=tuple(item[:800] for item in outcomes),
        constraints=tuple(item[:800] for item in constraints),
        conclusion=conclusion[:1200],
    )


def with_full_text(
    document: EvidenceDocument,
    enrichment: FullTextEnrichment,
) -> EvidenceDocument:
    return enrich_document_structure(
        replace(
            document,
            full_text=enrichment.text,
            full_text_license=enrichment.license_name,
            full_text_source_url=enrichment.source_url,
        )
    )


def _sentences(text: str) -> list[str]:
    return [
        value.strip()
        for value in re.split(r"(?<=[.!?])\s+|\n+", re.sub(r"\s+", " ", text))
        if len(value.strip()) >= 30
    ]


def _first_matching_sentence(text: str, terms: Iterable[str]) -> str:
    return next(iter(_matching_sentences(text, terms, maximum=1)), "")


def _matching_sentences(text: str, terms: Iterable[str], *, maximum: int) -> tuple[str, ...]:
    lowered_terms = tuple(term.lower() for term in terms)
    return tuple(
        sentence
        for sentence in _sentences(text)
        if any(term in sentence.lower() for term in lowered_terms)
    )[:maximum]


def _conclusion_sentence(text: str) -> str:
    sentences = _sentences(text)
    explicit = next(
        (
            sentence
            for sentence in reversed(sentences)
            if any(term in sentence.lower() for term in ("conclusion", "we conclude", "suggests that"))
        ),
        "",
    )
    return explicit or (sentences[-1] if sentences else "")

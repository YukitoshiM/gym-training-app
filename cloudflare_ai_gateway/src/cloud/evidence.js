export async function cloudEvidenceStatus(env) {
  requireDatabase(env);
  const counts = await env.BODYMODE_DB.prepare(`
    SELECT
      (SELECT COUNT(*) FROM evidence_documents) AS documents,
      (SELECT COUNT(*) FROM evidence_documents WHERE length(trim(coalesce(abstract, ''))) > 0) AS usable_documents,
      (SELECT COUNT(*) FROM evidence_chunks) AS vector_chunks,
      (SELECT MAX(updated_at) FROM evidence_documents) AS last_updated_at
  `).first();
  const documents = Number(counts?.documents || 0);
  const usableDocuments = Number(counts?.usable_documents || 0);
  const vectorChunks = Number(counts?.vector_chunks || 0);
  const ready = usableDocuments > 0 && vectorChunks > 0;
  return {
    state: ready ? "ready" : "empty",
    confidence: ready ? "moderate" : "insufficient",
    documents,
    usable_documents: usableDocuments,
    vector_chunks: vectorChunks,
    searched_documents: documents,
    matched_documents: 0,
    last_updated_at: isoTimestamp(counts?.last_updated_at),
    reason: ready ? "Cloudflareの論文索引を利用できます。" : "利用可能な論文索引がありません。",
    runtime: "cloudflare",
  };
}

export async function searchCloudEvidence(query, env, options = {}) {
  const text = String(query || "").trim().slice(0, 1_000);
  if (!text || !env.AI || !env.EVIDENCE_VECTORIZE || !env.BODYMODE_DB) {
    return unavailableSearch("evidence_search_not_configured");
  }
  try {
    const embedding = await env.AI.run(
      String(env.BODYMODE_EMBEDDING_MODEL || "@cf/baai/bge-m3"),
      { text: [text] },
    );
    const vector = Array.isArray(embedding?.data?.[0])
      ? embedding.data[0]
      : Array.isArray(embedding?.data)
        ? embedding.data
        : null;
    if (!vector?.length) return unavailableSearch("embedding_unavailable");

    const result = await env.EVIDENCE_VECTORIZE.query(vector, {
      topK: Math.max(1, Math.min(Number(options.limit || 5), 8)),
      returnMetadata: "all",
    });
    const matches = (result?.matches || []).filter((match) => Number(match.score || 0) >= 0.25);
    if (!matches.length) return unavailableSearch("no_relevant_evidence", "insufficient");

    const chunkIDs = matches.map((match) => String(match.id));
    const placeholders = chunkIDs.map(() => "?").join(",");
    const rows = await env.BODYMODE_DB.prepare(`
      SELECT
        c.chunk_id, c.content, c.purpose_tags,
        d.document_id, d.title, d.source_url, d.publication_date, d.license
      FROM evidence_chunks c
      JOIN evidence_documents d ON d.document_id = c.document_id
      WHERE c.chunk_id IN (${placeholders})
    `).bind(...chunkIDs).all();
    const byChunk = new Map((rows?.results || []).map((row) => [String(row.chunk_id), row]));
    const citations = matches.flatMap((match) => {
      const row = byChunk.get(String(match.id));
      if (!row) return [];
      return [{
        id: String(row.document_id),
        title: String(row.title || "Untitled research"),
        year: parsedYear(row.publication_date),
        study_type: inferredStudyType(row.title),
        confidence: Number(match.score || 0) >= 0.6 ? "moderate" : "low",
        url: safeHTTPSURL(row.source_url),
        doi: "",
        relevance: Math.max(0, Math.min(Number(match.score || 0), 1)),
        source_scope: "abstract",
        evidence_summary: String(row.content || "").slice(0, 600),
        population: "",
        intervention: "",
        outcomes: [],
        limitations: ["個人の結果を保証するものではありません。"],
        applicability_score: Math.max(0, Math.min(Number(match.score || 0), 1)),
        applicability_label: Number(match.score || 0) >= 0.6 ? "moderate" : "unclear",
        version_status: "current",
        conclusion_consistency: "unknown",
        newer_evidence_note: "",
        full_text_license: String(row.license || ""),
        source_detail_url: safeHTTPSURL(row.source_url),
      }];
    });
    const unique = [...new Map(citations.map((citation) => [citation.id, citation])).values()];
    return {
      state: unique.length ? "ready" : "insufficient",
      confidence: unique.some((item) => item.confidence === "moderate") ? "moderate" : "low",
      citations: unique,
      promptContext: unique.map((citation, index) => [
        `[E${index + 1}] ${citation.title} (${citation.year || "year unknown"})`,
        citation.evidence_summary,
        `Source: ${citation.url}`,
      ].join("\n")).join("\n\n"),
      searchedDocuments: Number(result?.count || matches.length),
      matchedDocuments: unique.length,
      lastUpdatedAt: null,
      reason: unique.length ? "関連する論文を検索しました。" : "関連する論文を確認できませんでした。",
    };
  } catch {
    return unavailableSearch("evidence_search_failed");
  }
}

function isoTimestamp(value) {
  const timestamp = Number(value || 0);
  return timestamp > 0 ? new Date(timestamp * 1_000).toISOString() : null;
}

function requireDatabase(env) {
  if (!env.BODYMODE_DB) {
    const error = new Error("cloud_database_not_configured");
    error.status = 503;
    error.code = "cloud_database_not_configured";
    throw error;
  }
}

function unavailableSearch(reason, state = "unavailable") {
  return {
    state,
    confidence: "insufficient",
    citations: [],
    promptContext: "No relevant scientific evidence was available. Do not invent citations.",
    searchedDocuments: 0,
    matchedDocuments: 0,
    lastUpdatedAt: null,
    reason,
  };
}

function parsedYear(value) {
  const match = String(value || "").match(/(?:19|20)\d{2}/);
  return match ? Number(match[0]) : null;
}

function inferredStudyType(title) {
  const normalized = String(title || "").toLowerCase();
  if (normalized.includes("meta-analysis") || normalized.includes("meta analysis")) return "meta_analysis";
  if (normalized.includes("systematic review")) return "systematic_review";
  if (normalized.includes("randomized") || normalized.includes("randomised")) return "randomized_controlled_trial";
  return "research_article";
}

function safeHTTPSURL(value) {
  try {
    const url = new URL(String(value || ""));
    return url.protocol === "https:" ? String(url) : "";
  } catch {
    return "";
  }
}

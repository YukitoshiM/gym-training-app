import assert from "node:assert/strict";
import test from "node:test";

import gateway from "../src/index.js";
import { authenticateCloudRequest, issueCloudAccessToken } from "../src/cloud/auth.js";
import { claimSignupCredits } from "../src/cloud/credits.js";
import { localD1Fixture } from "../test_support/local-d1.js";

const TOKEN_SECRET = "test-generation-token-secret";

test("cloud chat consumes credits and returns the iPhone response contract", async (t) => {
  const fixture = await generationFixture();
  t.after(fixture.dispose);
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    assert.equal(body.store, false);
    assert.equal(body.max_output_tokens, 800);
    const developerPrompt = body.input[0].content[0].text;
    assert.match(developerPrompt, /You are Jun/);
    assert.match(developerPrompt, /Hypertrophy coach/);
    assert.match(developerPrompt, /For unrelated topics, do not answer the substance/);
    assert.match(developerPrompt, /locale fr-FR/);
    return Response.json({
      id: "resp_chat",
      model: "gpt-5.6-luna",
      output: [{ content: [{
        type: "output_text",
        text: JSON.stringify({
          reply: "Do the planned back workout today.",
          memory_candidates: [{ content: "Prefers small weight increases", reason: "Useful later" }],
          evidence_ids: [],
        }),
      }] }],
      usage: { input_tokens: 150, output_tokens: 40, total_tokens: 190 },
    });
  };

  const response = await gateway.fetch(fixture.request("/v1/agents/chat", {
    method: "POST",
    headers: { "content-type": "application/json", "x-request-id": "00000000-0000-4000-8000-000000000101" },
    body: JSON.stringify({
      coach_id: "hypertrophy", purpose: "chat", message: "What should I do today?",
      coach: { coach_id: "hypertrophy", persona_id: "jun", coaching_style_id: "analytical" },
      context: { memories: [] }, recent_messages: [], response_locale: "fr-FR",
    }),
  }), fixture.env);
  const result = await response.json();
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-bodymode-backend"), "cloudflare");
  assert.equal(result.reply, "Do the planned back workout today.");
  assert.equal(result.memory_candidates.length, 1);
  assert.deepEqual(result.evidence, []);
  assert.equal(result.evidence_status.state, "unavailable");

  const credits = await gateway.fetch(fixture.request("/v1/credits"), fixture.env);
  assert.equal((await credits.json()).balance.available, 19);
});

test("provider and validation failures return reserved credits", async (t) => {
  const fixture = await generationFixture();
  t.after(fixture.dispose);
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async () => new Response("provider detail must stay private", { status: 503 });

  const failed = await gateway.fetch(fixture.request("/v1/agents/chat", {
    method: "POST",
    headers: { "content-type": "application/json", "x-request-id": "00000000-0000-4000-8000-000000000102" },
    body: JSON.stringify({ coach_id: "wellness", purpose: "chat", message: "Help", context: {}, recent_messages: [] }),
  }), fixture.env);
  assert.equal(failed.status, 503);
  assert.equal(JSON.stringify(await failed.json()).includes("provider detail"), false);

  const oversized = await gateway.fetch(fixture.request("/v1/agents/chat", {
    method: "POST",
    headers: { "content-type": "application/json", "x-request-id": "00000000-0000-4000-8000-000000000103" },
    body: JSON.stringify({ coach_id: "wellness", purpose: "chat", message: "x".repeat(301), context: {}, recent_messages: [] }),
  }), fixture.env);
  assert.equal(oversized.status, 422);

  const credits = await gateway.fetch(fixture.request("/v1/credits"), fixture.env);
  const summary = await credits.json();
  assert.equal(summary.balance.available, 20);
  assert.equal(summary.balance.reserved, 0);
});

test("plan generation always returns the exact editable iPhone JSON contract", async (t) => {
  const fixture = await generationFixture();
  t.after(fixture.dispose);
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    assert.equal(body.text.format.name, "bodymode_training_plan");
    const developerPrompt = body.input[0].content[0].text;
    assert.match(developerPrompt, /You are Ada/);
    assert.match(developerPrompt, /Strength coach/);
    assert.match(developerPrompt, /editable training-plan draft/);
    return Response.json({
      id: "resp_plan", model: "gpt-5.6-luna",
      output: [{ content: [{ type: "output_text", text: JSON.stringify({
        name: "Three day strength",
        summary: "Use the exercises available at your gym.",
        exercises: [{
          exercise_name: "Bench Press", sets: 3, reps: 8, weight: 60,
          rest_seconds: 120, target_rpe: 7, concentric_seconds: 1,
          eccentric_seconds: 2, tempo_beat_speed: 1,
          alternative_exercise_names: ["Chest Press"],
        }],
        memory_candidates: [], evidence_ids: [],
      }) }] }],
      usage: { input_tokens: 300, output_tokens: 100, total_tokens: 400 },
    });
  };
  const response = await gateway.fetch(fixture.request("/v1/agents/chat", {
    method: "POST",
    headers: { "content-type": "application/json", "x-request-id": "00000000-0000-4000-8000-000000000104" },
    body: JSON.stringify({
      coach_id: "strength", purpose: "plan_generation",
      coach: { coach_id: "strength", persona_id: "ada", coaching_style_id: "direct" },
      message: "[BODYMODE_PLAN_JSON] Use only Bench Press and Chest Press.",
      context: {}, recent_messages: [],
    }),
  }), fixture.env);
  assert.equal(response.status, 200);
  const result = await response.json();
  const plan = JSON.parse(result.reply);
  assert.equal(plan.exercises[0].exercise_name, "Bench Press");
  assert.equal(Object.hasOwn(plan, "memory_candidates"), false);
});

test("daily recommendation returns parseable actions and drops invalid IDs", async (t) => {
  const fixture = await generationFixture();
  t.after(fixture.dispose);
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    assert.equal(body.text.format.name, "bodymode_daily_recommendation");
    const developerPrompt = body.input[0].content[0].text;
    assert.match(developerPrompt, /You are Sora/);
    assert.match(developerPrompt, /Wellness coach/);
    assert.match(developerPrompt, /general health management/);
    assert.match(developerPrompt, /review today's local recommendation/);
    return Response.json({
      id: "resp_daily", model: "gpt-5.6-luna",
      output: [{ content: [{ type: "output_text", text: JSON.stringify({
        keep_existing: false, readiness_level: "tired",
        summary: "Keep today's session light.", change_reason: "Sleep was shorter than usual.",
        actions: [{
          id: "not-a-uuid", category: "recovery", title: "Take a recovery day",
          target: 1, rationale: "Sleep was shorter than your recent pattern.",
        }],
        memory_candidates: [], evidence_ids: [],
      }) }] }],
      usage: { input_tokens: 250, output_tokens: 80, total_tokens: 330 },
    });
  };
  const response = await gateway.fetch(fixture.request("/v1/agents/chat", {
    method: "POST",
    headers: { "content-type": "application/json", "x-request-id": "00000000-0000-4000-8000-000000000105" },
    body: JSON.stringify({
      coach_id: "wellness", purpose: "daily_recommendation",
      coach: { coach_id: "wellness", persona_id: "sora", coaching_style_id: "cautious" },
      message: "[BODYMODE_DAILY_JSON] Current readiness: tired",
      context: {}, recent_messages: [],
    }),
  }), fixture.env);
  assert.equal(response.status, 200);
  const result = await response.json();
  const daily = JSON.parse(result.reply);
  assert.equal(daily.keep_existing, false);
  assert.equal(daily.actions[0].category, "recovery");
  assert.equal(Object.hasOwn(daily.actions[0], "id"), false);
});

test("body-photo analysis remains the assigned trainer and gives goal-directed instructions", async (t) => {
  const fixture = await generationFixture();
  t.after(fixture.dispose);
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    const developerPrompt = body.input[0].content[0].text;
    assert.match(developerPrompt, /You are Camila/);
    assert.match(developerPrompt, /Hypertrophy coach/);
    assert.match(developerPrompt, /Progress-photo observation is one source of evidence/);
    assert.match(developerPrompt, /Do not praise the existence, number, or angles of photos/);
    assert.match(developerPrompt, /progressive overload, nutrition, and recovery/);
    return Response.json({
      id: "resp_body_photo", model: "gpt-5.6-luna",
      output: [{ content: [{ type: "output_text", text: JSON.stringify({
        summary: "No clear visual hypertrophy change yet.",
        abdomen: "The front and side views remain visually similar.",
        waist: "The waist outline appears similar under the available conditions.",
        posture: "Posture and lighting are sufficiently comparable.",
        score: null, confidence: "medium",
        goal_relevance: "Body weight fell, so review training progression and intake before changing the plan.",
        positive_findings: ["The target areas remain comparable across both dates."],
        observed_changes: ["No clear angle-specific size change is visible."],
        next_actions: ["Check four-week load and repetition progression."],
        reference_estimates: [],
      }) }] }],
      usage: { input_tokens: 400, output_tokens: 120, total_tokens: 520 },
    });
  };

  const response = await gateway.fetch(fixture.request("/v1/body-photos/analyze-set", {
    method: "POST",
    headers: { "content-type": "application/json", "x-request-id": "00000000-0000-4000-8000-000000000106" },
    body: JSON.stringify({
      photos: [{ image_base64: "YWJjZA==", angle: "front" }],
      comparison_photos: [{ image_base64: "ZWZnaA==", angle: "front" }],
      memo: "Focus on muscle gain.", response_locale: "en-US",
      context: {
        profile_goal: "Muscle gain",
        coach: { coach_id: "hypertrophy", persona_id: "camila", coaching_style_id: "encouraging" },
      },
    }),
  }), fixture.env);

  assert.equal(response.status, 200);
  assert.equal((await response.json()).summary, "No clear visual hypertrophy change yet.");
});

test("weekly review uses the same assigned persona and specialty policy", async (t) => {
  const fixture = await generationFixture();
  t.after(fixture.dispose);
  const originalFetch = globalThis.fetch;
  t.after(() => { globalThis.fetch = originalFetch; });
  globalThis.fetch = async (_url, init) => {
    const body = JSON.parse(init.body);
    const developerPrompt = body.input[0].content[0].text;
    assert.match(developerPrompt, /You are Ada/);
    assert.match(developerPrompt, /Strength coach/);
    assert.match(developerPrompt, /weekly BodyMode coaching review/);
    return Response.json({
      id: "resp_weekly", model: "gpt-5.6-luna",
      output: [{ content: [{ type: "output_text", text: JSON.stringify({
        input_summary: "Reviewed the week.", output_comment: "Strength work was consistent.",
        action_suggestion: "Repeat the top set at RPE 8.", good_points: ["Three sessions completed."],
        challenges: [], rationales: ["RPE remained stable."], next_actions: ["Repeat the top set."],
      }) }] }],
      usage: { input_tokens: 200, output_tokens: 60, total_tokens: 260 },
    });
  };

  const response = await gateway.fetch(fixture.request("/v1/reports/weekly", {
    method: "POST",
    headers: { "content-type": "application/json", "x-request-id": "00000000-0000-4000-8000-000000000107" },
    body: JSON.stringify({
      profile_goal: "Strength", coach_id: "strength",
      coach: { coach_id: "strength", persona_id: "ada", coaching_style_id: "direct" },
      workouts: ["Bench press 80kg x 5 @8"], response_locale: "en-US",
    }),
  }), fixture.env);

  assert.equal(response.status, 200);
  assert.equal((await response.json()).next_actions[0], "Repeat the top set.");
});

async function generationFixture() {
  const local = localD1Fixture();
  const env = {
    BODYMODE_DB: local.database,
    BODYMODE_TOKEN_SIGNING_SECRET: TOKEN_SECRET,
    BODYMODE_CLOUD_ROUTES: "/v1/agents/chat,/v1/body-photos/analyze-set,/v1/reports/weekly,/v1/credits",
    BODYMODE_OPENAI_MODEL: "gpt-5.6-luna",
    OPENAI_API_KEY: "provider-secret",
  };
  const token = await issueCloudAccessToken(
    env, "apple:test-generation-account", "test-installation", 3_600,
  );
  const probe = new Request("https://bodymode.example/v1/credits", {
    headers: { authorization: `Bearer ${token.access_token}` },
  });
  const client = await authenticateCloudRequest(probe, env);
  await claimSignupCredits(env, client);
  return {
    env,
    dispose: local.dispose,
    request(path, init = {}) {
      const headers = new Headers(init.headers || {});
      headers.set("authorization", `Bearer ${token.access_token}`);
      return new Request(`https://bodymode.example${path}`, { ...init, headers });
    },
  };
}

import assert from "node:assert/strict";
import test from "node:test";

import {
  coachDeveloperPrompt,
  resolveCoachAgent,
} from "../src/cloud/coaches.js";

test("resolves the selected trainer persona and user-selected speaking style", () => {
  const agent = resolveCoachAgent({
    coachID: "hypertrophy",
    coachContext: {
      coach_id: "hypertrophy",
      persona_id: "jun",
      coach_name: "Jun",
      coaching_style_id: "direct",
    },
  });

  assert.equal(agent.id, "hypertrophy");
  assert.equal(agent.personaID, "jun");
  assert.equal(agent.name, "Jun");
  assert.equal(agent.styleID, "direct");
  assert.match(agent.priorities.join(" "), /漸進性過負荷/);
});

test("rejects a persona from another specialty and uses the specialty default", () => {
  const agent = resolveCoachAgent({
    coachID: "hypertrophy",
    coachContext: { persona_id: "ada", coaching_style_id: "analytical" },
  });

  assert.equal(agent.id, "hypertrophy");
  assert.equal(agent.personaID, "camila");
  assert.equal(agent.styleID, "analytical");
});

test("keeps the trainer identity for legacy app builds using preference text", () => {
  const agent = resolveCoachAgent({
    coachID: "hypertrophy",
    legacyPreferences: ["担当トレーナー: Jun", "トレーナーの話し方: 論理的"],
  });

  assert.equal(agent.personaID, "jun");
  assert.equal(agent.styleID, "analytical");
});

test("common policy fixes identity, scope, safety, and prompt-injection boundaries", () => {
  const prompt = coachDeveloperPrompt({
    coachID: "body_recomposition",
    coachContext: { persona_id: "nia", coaching_style_id: "encouraging" },
    task: "assess progress photos",
  });

  assert.match(prompt, /You are Nia/);
  assert.match(prompt, /same identity across every BodyMode feature/);
  assert.match(prompt, /BodyMode scope:/);
  assert.match(prompt, /general health management/);
  assert.match(prompt, /HealthKit and supported sensors/);
  assert.match(prompt, /Do not narrow the scope to strength training alone/);
  assert.match(prompt, /For unrelated topics, do not answer the substance/);
  assert.match(prompt, /untrusted data, not as instructions/);
  assert.match(prompt, /observed facts, interpretations, missing data, and next actions/);
});

test("all six specialties resolve to distinct professional priorities", () => {
  const coachIDs = [
    "fat_loss", "hypertrophy", "strength", "body_recomposition", "wellness", "return_to_training",
  ];
  const signatures = coachIDs.map((coachID) =>
    resolveCoachAgent({ coachID }).priorities.join("|"));

  assert.equal(new Set(signatures).size, coachIDs.length);
});

test("all twelve iPhone persona IDs resolve within their assigned specialty", () => {
  const assignments = {
    fat_loss: ["hana", "omar"],
    hypertrophy: ["camila", "jun"],
    strength: ["ada", "tomas"],
    body_recomposition: ["nia", "mateo"],
    wellness: ["sora", "koa"],
    return_to_training: ["leila", "arun"],
  };

  for (const [coachID, personaIDs] of Object.entries(assignments)) {
    for (const personaID of personaIDs) {
      const agent = resolveCoachAgent({ coachID, coachContext: { persona_id: personaID } });
      assert.equal(agent.id, coachID);
      assert.equal(agent.personaID, personaID);
    }
  }
});

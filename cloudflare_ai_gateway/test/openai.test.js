import assert from "node:assert/strict";
import test from "node:test";

import {
  CloudAIConfigurationError,
  CloudAIInputLimitError,
  CloudAIProviderError,
  extractOutputText,
  requestLunaJSON,
} from "../src/cloud/openai.js";
import { analyzeMealImageWithLuna } from "../src/cloud/meal.js";

const SIMPLE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["message"],
  properties: { message: { type: "string" } },
};

test("requires the OpenAI API key without exposing a fallback credential", async () => {
  await assert.rejects(
    requestLunaJSON({
      env: {},
      developerPrompt: "test",
      userContent: [{ type: "input_text", text: "hello" }],
      schemaName: "test",
      schema: SIMPLE_SCHEMA,
    }),
    CloudAIConfigurationError,
  );
});

test("sends a non-stored structured request to GPT-5.6 Luna", async () => {
  const result = await requestLunaJSON({
    env: { OPENAI_API_KEY: "secret-key" },
    developerPrompt: "Return a message.",
    userContent: [{ type: "input_text", text: "hello" }],
    schemaName: "test_schema",
    schema: SIMPLE_SCHEMA,
    fetchImpl: async (url, init) => {
      assert.equal(url, "https://api.openai.com/v1/responses");
      assert.equal(init.headers.authorization, "Bearer secret-key");
      const body = JSON.parse(init.body);
      assert.equal(body.model, "gpt-5.6-luna");
      assert.equal(body.store, false);
      assert.equal(body.max_output_tokens, 1_000);
      assert.equal(body.text.format.type, "json_schema");
      assert.equal(body.text.format.strict, true);
      return new Response(
        JSON.stringify({
          id: "resp_123",
          model: "gpt-5.6-luna",
          output: [{ content: [{ type: "output_text", text: '{"message":"ok"}' }] }],
          usage: { input_tokens: 20, output_tokens: 4, total_tokens: 24 },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    },
  });

  assert.deepEqual(result.data, { message: "ok" });
  assert.equal(result.usage.totalTokens, 24);
});

test("applies bounded output budgets and rejects oversized text before provider calls", async () => {
  let called = false;
  await assert.rejects(
    requestLunaJSON({
      env: { OPENAI_API_KEY: "secret-key" },
      developerPrompt: "test",
      userContent: [{ type: "input_text", text: "123456" }],
      schemaName: "test",
      schema: SIMPLE_SCHEMA,
      maxInputCharacters: 5,
      fetchImpl: async () => { called = true; },
    }),
    CloudAIInputLimitError,
  );
  assert.equal(called, false);

  await requestLunaJSON({
    env: { OPENAI_API_KEY: "secret-key" },
    developerPrompt: "test",
    userContent: [{ type: "input_text", text: "ok" }],
    schemaName: "test",
    schema: SIMPLE_SCHEMA,
    maxOutputTokens: 99_999,
    fetchImpl: async (_url, init) => {
      assert.equal(JSON.parse(init.body).max_output_tokens, 2_000);
      return new Response(
        JSON.stringify({
          output: [{ content: [{ type: "output_text", text: '{"message":"ok"}' }] }],
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    },
  });
});

test("does not include provider response bodies in public errors", async () => {
  await assert.rejects(
    requestLunaJSON({
      env: { OPENAI_API_KEY: "secret-key" },
      developerPrompt: "test",
      userContent: [{ type: "input_text", text: "hello" }],
      schemaName: "test",
      schema: SIMPLE_SCHEMA,
      fetchImpl: async () => new Response("sensitive provider details", { status: 429 }),
    }),
    (error) =>
      error instanceof CloudAIProviderError &&
      error.code === "provider_rate_limited" &&
      !error.message.includes("sensitive"),
  );
});

test("extracts text only from output_text content", () => {
  assert.equal(
    extractOutputText({ output: [{ content: [{ type: "output_text", text: "result" }] }] }),
    "result",
  );
  assert.equal(extractOutputText({ output: [{ content: [{ type: "refusal", text: "no" }] }] }), "");
});

test("meal analysis sends a scrubbed JPEG data URL and preserves the API contract", async () => {
  const result = await analyzeMealImageWithLuna(
    {
      image_base64: "YWJjZA==",
      meal_type: "lunch",
      memo: "rice bowl",
      locale: "en-US",
      coach: { coach_id: "hypertrophy", persona_id: "jun", coaching_style_id: "analytical" },
    },
    { OPENAI_API_KEY: "secret-key" },
    {
      fetchImpl: async (_url, init) => {
        const body = JSON.parse(init.body);
        assert.equal(body.max_output_tokens, 900);
        assert.match(body.input[0].content[0].text, /You are Jun/);
        assert.match(body.input[0].content[0].text, /Hypertrophy coach/);
        assert.match(body.input[0].content[0].text, /Meal recognition supplies an editable factual draft/);
        const image = body.input[1].content.find((item) => item.type === "input_image");
        assert.equal(image.image_url, "data:image/jpeg;base64,YWJjZA==");
        assert.equal(image.detail, "low");
        return new Response(
          JSON.stringify({
            id: "resp_meal",
            model: "gpt-5.6-luna",
            output: [
              {
                content: [
                  {
                    type: "output_text",
                    text: JSON.stringify({
                      meal_name: "Chicken rice bowl",
                      calories: 640,
                      protein: 32,
                      fat: 16,
                      carbs: 88,
                      confidence: "medium",
                      comment: "Check the rice portion.",
                      items: [
                        {
                          name: "Rice",
                          amount: "200g",
                          calories: 336,
                          protein: 5,
                          fat: 1,
                          carbs: 74,
                        },
                      ],
                    }),
                  },
                ],
              },
            ],
            usage: { input_tokens: 100, output_tokens: 50, total_tokens: 150 },
          }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      },
    },
  );

  assert.equal(result.data.meal_name, "Chicken rice bowl");
  assert.equal(result.data.items[0].amount, "200g");
  assert.equal(result.usage.totalTokens, 150);
});

test("meal analysis rejects malformed image data before calling the provider", async () => {
  let called = false;
  await assert.rejects(
    analyzeMealImageWithLuna(
      { image_base64: "not base64!?" },
      { OPENAI_API_KEY: "secret-key" },
      { fetchImpl: async () => { called = true; } },
    ),
    /invalid_image_base64/,
  );
  assert.equal(called, false);
});

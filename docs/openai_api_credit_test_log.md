# OpenAI API credit test log

## 2026-08-23 18:47 JST

| Item | Result |
|---|---|
| Environment | BodyMode production Cloudflare Worker |
| Model | `gpt-5.6-luna` |
| Free model probe | HTTP 200, ready; 0 generated tokens |
| Paid generation | HTTP 200, reply `OK` |
| Request ID | `6b5f6274-7967-46ea-a1c6-0bb1e5031848` |
| Paid requests sent in this test | 1 |
| Input tokens | 1,049 |
| Uncached input tokens | 3 |
| Cached input tokens | 0 |
| Output tokens | 25 |
| Total tokens | 1,074 |
| Standard token-rate estimate | USD 0.0002398 |
| Cache-write-adjusted estimate | USD 0.0002921 |

The production request succeeded. The owner account was configured as unlimited
and skipped both credit reservation and `ai_requests` usage logging, so the
token split was reconciled from the OpenAI Usage dashboard. Attempts to run a
second metered request stopped while waiting for macOS Keychain authorization,
before any request was sent to OpenAI.

The standard estimate applies the listed input and output rates directly. The
cache-write-adjusted estimate treats the 1,046 input tokens not classified by
the dashboard as uncached or cached reads as an initial cache write billed at
1.25 times the uncached input rate. OpenAI billing remains the authoritative
amount.

Pricing used for reconciliation: GPT-5.6 Luna standard processing is USD 0.20
per 1M input tokens, USD 0.02 per 1M cached input tokens, and USD 1.20 per 1M
output tokens as of this test date.

## Usage logging fix

The unlimited owner path now records accepted, completed, and failed AI
requests in `ai_requests` without reserving or consuming credits. The existing
paid test request predates this fix and was not backfilled.

| Item | Result |
|---|---|
| Gateway tests | 49 passed, 0 failed |
| Production health | HTTP 200, OpenAI configured/authenticated/reachable |
| Production Worker version | `e4619008-d2eb-44d6-813b-b66c8b2a64af` |
| Additional paid requests | 0 |

## 2026-08-23 production release-route smoke test

The release-target Worker was verified at
`https://bodymode-ai-gateway-production.bodymode-ai.workers.dev`. The test used
synthetic repository assets and did not send user records or photos.

| Route | Result | Input tokens | Output tokens |
|---|---|---:|---:|
| Meal text draft | HTTP 200 | 250 | 276 |
| Meal image draft | HTTP 200 | 546 | 328 |
| Body photo observation | HTTP 200 | 625 | 321 |
| Training plan generation | HTTP 200 | 1,246 | 332 |
| Daily recommendation | HTTP 200 | 1,207 | 268 |
| Weekly report | HTTP 200 | 245 | 333 |
| **Total** | **6 / 6 passed** | **4,119** | **1,858** |

All six requests were logged as `completed` in production D1 with model
`gpt-5.6-luna`. Total processing time was 26,853 ms. Applying the standard
uncached rates to all input tokens gives a conservative estimate of USD
0.0030534. OpenAI billing remains authoritative.

An earlier six-route connectivity attempt used the retired unsuffixed Worker
hostname before the release hostname mismatch was found. Those calls succeeded,
but that Worker did not expose usage rows through the production D1 binding, so
their exact token split is not included above. The release preflight now rejects
any app whose AI URL does not exactly match the production Worker.

# Speechy Test Suite

Three suites covering the licensing API, the macOS desktop client, and the
landing page. **309 tests total — all green.** Run everything via the
top-level `run-all-tests.sh`, or a single suite via `./run-all-tests.sh <api|client|ui>`.

| Suite  | Count | Runtime | Tech                    |
| ------ | ----: | ------: | ----------------------- |
| API    |    79 |   ~10s  | PHP + curl + Postgres   |
| Client |   175 |    ~3s  | Swift (custom harness)  |
| UI     |    55 |   ~10s  | Playwright (chromium)   |
| total  |   309 |   ~25s  |                         |

## Directory layout

```
tests/
├── api/              # PHP API functional + integration tests (vanilla PHP + curl)
├── ui/               # Landing page E2E tests (Node/Playwright)
├── fixtures/         # Shared test data (emails, license keys, payloads)
├── .env.test         # Shared environment (DB name, ports, base URLs)
└── README.md         # This file

desktop/SpeechToText/Tests/
└── DesktopTests.swift  # Client (Swift) unit + integration tests (existing harness)

run-all-tests.sh      # Top-level runner
```

## Port + database conventions (non-clashing)

| Component            | Value                       | Notes                               |
| -------------------- | --------------------------- | ----------------------------------- |
| API dev server       | `http://127.0.0.1:8765`     | `php -S 127.0.0.1:8765 index.php`   |
| Landing page server  | `http://127.0.0.1:8766`     | `python3 -m http.server 8766`       |
| Test database        | `speechy_licensing_test`    | PostgreSQL, auto-truncated per test |
| Admin API key (test) | `test-admin-key-do-not-use` | written to test config              |

The dev ports deliberately avoid the PHP default (8000) so nothing clashes
with ongoing manual testing.

## Shared fixtures

`tests/fixtures/` holds JSON/text files consumed by both API and UI tests:

- `emails.json` — set of throwaway emails for signup flows
- `license_keys.json` — pre-inserted keys (via migrate-for-tests) for client
  tests that don't want to hit the API

## Runner

`run-all-tests.sh` runs, in order:

1. API — spins up `speechy_licensing_test`, starts `php -S 127.0.0.1:8765`,
   runs `tests/api/run.sh`, tears down.
2. Client — runs `desktop/SpeechToText/Tests/run.sh` (swiftc -DTESTING).
3. UI — starts landing server on 8766, runs `tests/ui/run.sh`, tears down.

Each suite's `run.sh` must exit non-zero on failure. The top-level runner
aggregates exit codes.

## Compatibility rules (for all agents)

1. **No shared global state at runtime.** Tests must not depend on execution
   order. API tests truncate tables between cases.
2. **No hardcoded production URLs.** Read from `tests/.env.test`.
3. **No real network.** UI/API tests use local servers only; client tests
   stub URLSession where needed.
4. **Logs go to `tests/logs/<suite>.log`** so failures are debuggable in CI.
5. **Exit codes:** 0 = all passed, non-zero = failures. Always.

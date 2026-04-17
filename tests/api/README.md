# Speechy API Test Suite

Functional and integration tests for the PHP licensing backend.

## Prerequisites

- PostgreSQL running locally (default: `127.0.0.1:5432`)
- PHP 8.3+ with the `pgsql` and `curl` extensions enabled
- A Postgres user that can create databases (usually your system user)

Check: `php -m | grep -E "pgsql|curl"`

## Running

```bash
# From the repo root
bash tests/api/run.sh
```

The runner will:
1. Drop and recreate `speechy_licensing_test`
2. Apply all 5 migrations from `licensing/migrations/`
3. Back up `licensing/config.php` and write a test-only config
4. Start `php -S 127.0.0.1:8765 licensing/index.php`
5. Execute every `tests/api/cases/*.test.php` in alphabetical order
6. Print a pass/fail summary
7. On exit: kill the server, restore `config.php`, drop the test DB

If your Postgres user requires a password, set it before running:

```bash
DB_PASS=yourpassword bash tests/api/run.sh
```

If your Postgres user is not your system user:

```bash
DB_USER=postgres DB_PASS=secret bash tests/api/run.sh
```

## Test structure

```
tests/api/
├── run.sh              # Entry point
├── lib/
│   └── harness.php     # Test runner, HTTP helpers, DB helpers
├── cases/
│   ├── 01_signup.test.php
│   ├── 02_verify_email.test.php
│   ├── 03_license_verify.test.php
│   ├── 04_license_activate.test.php
│   ├── 05_license_deactivate.test.php
│   ├── 06_admin_crud.test.php
│   ├── 07_version_check.test.php
│   └── 99_integration.test.php
└── README.md
```

Each `*.test.php` file calls `setup()` at the top, which truncates all tables
(fresh state per file). Tests within a file share state intentionally when they
form a sequence (e.g., signup then verify).

## Adding a new test

1. Create `tests/api/cases/XX_name.test.php`
2. Start with `require_once __DIR__ . '/../lib/harness.php';`
3. Call `setup(); suite_header('XX — Name');`
4. Use `test(string $name, callable $fn)` blocks with `assert_eq`, `assert_true`, `assert_status`
5. Use `http_post`, `http_get`, `http_put`, `http_delete` for HTTP calls
6. Use `db_insert_license`, `db_count`, `db_fetch_one` for direct DB access

## Known limitations

- **Rate-limit IP testing**: The PHP dev server always presents `REMOTE_ADDR=127.0.0.1`.
  Rate-limit tests (01, 99) insert rows directly into `email_verifications` with
  `ip_address='127.0.0.1'` to simulate prior requests from the same IP, then fire
  a real HTTP signup. This tests the exact code path in `signup.php:21`.

- **Email sending**: Tests run with empty OneSignal credentials, so `send_verification_email`
  returns `false` and `verify_url` is included in the 201 response body. This is the
  intended dev-mode behavior and is what the tests rely on to obtain the token.

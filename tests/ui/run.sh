#!/usr/bin/env bash
# ============================================================
# tests/ui/run.sh — Speechy landing page E2E test runner
#
# Static server: python3 -m http.server (chosen because Python 3
# ships with macOS 12+ and does not require npm install).
# Port: 8766 (defined in tests/.env.test)
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${REPO_ROOT}/tests/.env.test"
LANDING_DIR="${REPO_ROOT}/landing"
LOG_DIR="${REPO_ROOT}/tests/logs"
LOG_FILE="${LOG_DIR}/ui.log"

# ── Load shared env ─────────────────────────────────────────
if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck source=/dev/null
  set -a
  source "${ENV_FILE}"
  set +a
fi

# Default port if not set in .env.test
SPEECHY_TEST_UI_PORT="${SPEECHY_TEST_UI_PORT:-8766}"
SPEECHY_TEST_UI_BASE="${SPEECHY_TEST_UI_BASE:-http://127.0.0.1:${SPEECHY_TEST_UI_PORT}}"
export SPEECHY_TEST_UI_BASE

# ── Sanity checks ────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "[ui] ERROR: node is not installed. Install Node.js 18+ to run UI tests." >&2
  exit 1
fi

if ! command -v npm &>/dev/null; then
  echo "[ui] ERROR: npm is not installed." >&2
  exit 1
fi

NODE_MAJOR=$(node -e "process.stdout.write(String(process.versions.node.split('.')[0]))")
if [[ "${NODE_MAJOR}" -lt 18 ]]; then
  echo "[ui] ERROR: Node.js 18+ required (found ${NODE_MAJOR})." >&2
  exit 1
fi

# ── Install dependencies ─────────────────────────────────────
cd "${SCRIPT_DIR}"

if [[ ! -d node_modules ]]; then
  if [[ -f package-lock.json ]]; then
    echo "[ui] Installing Playwright (npm ci)..."
    npm ci
  else
    echo "[ui] Installing Playwright (npm install)..."
    npm install
  fi
else
  echo "[ui] node_modules already present, skipping install."
fi

# Install Chromium browser if not already installed.
# On macOS we skip --with-deps (no sudo). On Linux/CI we include it.
OS="$(uname -s)"
if [[ "${OS}" == "Darwin" ]]; then
  npx playwright install chromium
else
  npx playwright install chromium --with-deps
fi

# ── Start local static server ────────────────────────────────
SERVER_PID=""

cleanup() {
  if [[ -n "${SERVER_PID}" ]]; then
    echo "[ui] Stopping static server (PID ${SERVER_PID})..."
    kill "${SERVER_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "[ui] Starting static server for ${LANDING_DIR} on port ${SPEECHY_TEST_UI_PORT}..."
mkdir -p "${LOG_DIR}"
python3 -m http.server "${SPEECHY_TEST_UI_PORT}" --directory "${LANDING_DIR}" \
  >"${LOG_FILE}" 2>&1 &
SERVER_PID=$!

# ── Wait for server to respond ───────────────────────────────
echo "[ui] Waiting for server to be ready..."
MAX_WAIT=20
WAITED=0
until curl -sf "${SPEECHY_TEST_UI_BASE}/" -o /dev/null 2>/dev/null; do
  if [[ ${WAITED} -ge ${MAX_WAIT} ]]; then
    echo "[ui] ERROR: Static server did not start within ${MAX_WAIT}s." >&2
    exit 1
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done
echo "[ui] Server ready at ${SPEECHY_TEST_UI_BASE}"

# ── Run Playwright tests ─────────────────────────────────────
echo "[ui] Running Playwright tests..."
set +e
npx playwright test "$@"
PLAYWRIGHT_EXIT=$?
set -e

if [[ ${PLAYWRIGHT_EXIT} -eq 0 ]]; then
  echo "[ui] All tests passed."
else
  echo "[ui] Some tests failed (exit ${PLAYWRIGHT_EXIT}). See playwright-report/ for details." >&2
fi

exit ${PLAYWRIGHT_EXIT}

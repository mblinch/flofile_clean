#!/usr/bin/env bash
# One-shot: save roster_sync/config to Firestore and pull rosters now.
# Requires Firebase Admin JSON in the environment (see below).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JSON_FILE="${1:-$ROOT/tool/roster_sync_initial.example.json}"

if [[ -z "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" && -n "${FIREBASE_SERVICE_ACCOUNT_FILE:-}" ]]; then
  export FIREBASE_SERVICE_ACCOUNT_JSON="$(cat "$FIREBASE_SERVICE_ACCOUNT_FILE")"
fi

if [[ -z "${FIREBASE_SERVICE_ACCOUNT_JSON:-}" ]]; then
  echo "Set one of:"
  echo "  export FIREBASE_SERVICE_ACCOUNT_JSON='\$(cat path/to/serviceAccount.json)'"
  echo "  export FIREBASE_SERVICE_ACCOUNT_FILE=path/to/serviceAccount.json"
  exit 1
fi

cd "$ROOT/scripts"
if [[ ! -d node_modules ]]; then
  npm ci
fi
node run-initial-roster-sync.mjs "$JSON_FILE"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ID="${EAS_PROJECT_ID:-16e2a949-9e22-4710-81a4-03221638bc08}"

# Locate the extracted monorepo without deleting or moving project data.
CANDIDATES=(
  "$ROOT/coin-rice-mill-map/coin-rice-mill-map/apps/mobile"
  "$ROOT/coin-rice-mill-map/apps/mobile"
  "$ROOT/apps/mobile"
)

MOBILE=""
for dir in "${CANDIDATES[@]}"; do
  if [[ -f "$dir/package.json" ]]; then
    MOBILE="$dir"
    break
  fi
done

if [[ -z "$MOBILE" ]]; then
  echo "ERROR: apps/mobile/package.json was not found." >&2
  exit 1
fi

echo "== Coin Rice Mill Map / EAS repair =="
echo "Mobile: $MOBILE"

# Expo/EAS config loading is much more predictable on Node 22 than Node 24.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
  nvm install 22 >/dev/null
  nvm use 22 >/dev/null
fi

echo "Node: $(node -v)"
echo "EAS:  $(eas --version | head -n1)"

if [[ -z "${EXPO_TOKEN:-}" ]]; then
  echo "ERROR: EXPO_TOKEN is not set in this shell." >&2
  echo "Set the same Expo access token you already created, then rerun this script." >&2
  exit 2
fi

cd "$MOBILE"
export EAS_PROJECT_ID="$PROJECT_ID"

# First try the ORIGINAL config unchanged. If Node 22 fixes the loader issue,
# we deliberately do not modify app.config.ts at all.
echo
echo "[1/3] Checking original Expo config..."
if npx expo config --type public >/tmp/crmm-expo-config.json 2>/tmp/crmm-expo-config.err; then
  echo "Original app.config is valid on Node $(node -v). No config rewrite needed."
else
  echo "Original config still fails. Preserving it and compiling an EAS-safe CJS copy."
  cat /tmp/crmm-expo-config.err || true

  if [[ ! -f app.config.ts ]]; then
    echo "ERROR: app.config.ts is not present, so an automatic safe fallback cannot be built." >&2
    exit 3
  fi

  TS_BACKUP="app.config.ts.before-eas-fix"
  cp -f app.config.ts "$TS_BACKUP"

  # Bundle the exact existing TypeScript config + local workspace imports into
  # CommonJS. This avoids hand-copying production config values.
  pnpm exec esbuild app.config.ts \
    --bundle \
    --platform=node \
    --format=cjs \
    --target=node22 \
    --outfile=app.config.compiled.cjs

  cat > app.config.js <<'EOF'
const compiled = require('./app.config.compiled.cjs');
module.exports = compiled.default ?? compiled;
EOF

  mv app.config.ts app.config.ts.disabled

  if ! npx expo config --type public >/tmp/crmm-expo-config.json 2>/tmp/crmm-expo-config.err; then
    echo "ERROR: CJS fallback also failed. Rolling back to the original config." >&2
    cat /tmp/crmm-expo-config.err || true
    rm -f app.config.js app.config.compiled.cjs
    mv app.config.ts.disabled app.config.ts
    exit 4
  fi

  echo "CJS fallback config is valid."
  echo "Original preserved at: $MOBILE/$TS_BACKUP"
  echo "Original disabled at:  $MOBILE/app.config.ts.disabled"
fi

echo
echo "[2/3] Confirming EAS project link..."
eas project:info

echo
echo "[3/3] Result"
echo "Expo config: OK"
echo "EAS project: @takzin1/coin-rice-mill-map"
echo "Project ID: $PROJECT_ID"
echo
echo "NEXT: run 'eas device:create' from $MOBILE to register the iPhone."

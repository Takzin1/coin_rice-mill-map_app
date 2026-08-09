#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ID="${EAS_PROJECT_ID:-16e2a949-9e22-4710-81a4-03221638bc08}"

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

WORKSPACE_ROOT="$(cd "$MOBILE/../.." && pwd)"

echo "== Coin Rice Mill Map / Codespaces EAS repair v2 =="
echo "Workspace: $WORKSPACE_ROOT"
echo "Mobile:    $MOBILE"

# Use Node 22 for Expo/EAS config evaluation.
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  # shellcheck disable=SC1090
  source "$NVM_DIR/nvm.sh"
  nvm install 22 >/dev/null
  nvm use 22 >/dev/null
fi

echo "Node: $(node -v)"

# nvm keeps global packages per Node version, so make sure EAS exists on Node 22.
if ! command -v eas >/dev/null 2>&1; then
  echo "Installing EAS CLI for Node $(node -v)..."
  npm install -g eas-cli@21.7.0
fi

echo "EAS: $(eas --version | head -n1)"

if [[ -z "${EXPO_TOKEN:-}" ]]; then
  echo "ERROR: EXPO_TOKEN is not set in this shell." >&2
  exit 2
fi

export EAS_PROJECT_ID="$PROJECT_ID"
cd "$MOBILE"

echo
echo "[1/3] Testing the original Expo config unchanged..."
if npx expo config --type public >/tmp/crmm-expo-config.json 2>/tmp/crmm-expo-config.err; then
  echo "Original config works. No source config rewrite was needed."
else
  echo "Original config failed; preserving it and compiling the exact config to CommonJS."
  cat /tmp/crmm-expo-config.err || true

  if [[ ! -f app.config.ts ]]; then
    echo "ERROR: app.config.ts not found; refusing to guess or overwrite config." >&2
    exit 3
  fi

  cp -f app.config.ts app.config.ts.before-eas-fix

  ESBUILD="$WORKSPACE_ROOT/node_modules/.bin/esbuild"
  if [[ ! -x "$ESBUILD" ]]; then
    echo "ERROR: esbuild not found at $ESBUILD. Run pnpm install at the workspace root first." >&2
    exit 4
  fi

  "$ESBUILD" app.config.ts \
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
    echo "ERROR: compiled fallback also failed. Rolling back automatically." >&2
    cat /tmp/crmm-expo-config.err || true
    rm -f app.config.js app.config.compiled.cjs
    mv app.config.ts.disabled app.config.ts
    exit 5
  fi

  echo "Compiled CommonJS config works."
  echo "Backup:   $MOBILE/app.config.ts.before-eas-fix"
  echo "Original: $MOBILE/app.config.ts.disabled"
fi

echo
echo "[2/3] Checking Expo identity..."
eas whoami

echo
echo "[3/3] Checking EAS project link..."
eas project:info

echo
echo "SUCCESS: Expo config and EAS project link are both valid."
echo "Project:    @takzin1/coin-rice-mill-map"
echo "Project ID: $PROJECT_ID"
echo "Next interactive step: eas device:create"

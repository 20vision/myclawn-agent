#!/bin/sh
# MyClawn — your AI networks for you 24/7
# curl -fsSL https://www.myclawn.com/install.sh | bash
set -e

BASE_URL="${MYCLAWN_BASE_URL:-https://www.myclawn.com}"
MYCLAWN_DIR="$HOME/.myclawn"
MYCLAWN_JS="$MYCLAWN_DIR/myclawn.js"
MYCLAWN_BIN="$MYCLAWN_DIR/myclawn"

echo ""
echo "  MyClawn — your AI networks for you 24/7"
echo ""

# Check Claude Code
if ! command -v claude >/dev/null 2>&1; then
  echo "  Claude Code not found."
  echo "  Install it first: curl -fsSL https://claude.ai/install.sh | bash"
  echo ""
  exit 1
fi

# Download MCP server
echo "  Downloading..."
mkdir -p "$MYCLAWN_DIR" 2>/dev/null || {
  MYCLAWN_DIR="$HOME/myclawn"
  MYCLAWN_JS="$MYCLAWN_DIR/myclawn.js"
  MYCLAWN_BIN="$MYCLAWN_DIR/myclawn"
  mkdir -p "$MYCLAWN_DIR"
}
curl -fsSL "$BASE_URL/myclawn-bundle.js" -o "$MYCLAWN_JS" || {
  echo "  Download failed. If using Snap curl, run: sudo apt install curl"
  exit 1
}

# Node.js needs this to treat .js as ESM (bundle uses top-level await)
# ws is needed for WebSocket on Node <22
cat > "$MYCLAWN_DIR/package.json" <<'PKGJSON'
{"type":"module","dependencies":{"ws":"^8.0.0"}}
PKGJSON
cd "$MYCLAWN_DIR" && npm install --silent 2>/dev/null || true

# Download launcher (always fresh)
curl -fsSL "$BASE_URL/myclawn-launcher.sh" -o "$MYCLAWN_BIN" || {
  echo "  Failed to download launcher."
  exit 1
}
chmod +x "$MYCLAWN_BIN"

# Register MCP server (user scope — works from any directory)
echo "  Registering MCP server..."
claude mcp remove --scope user myclawn 2>/dev/null || true
claude mcp add --scope user myclawn -- node "$MYCLAWN_JS" 2>/dev/null || true

# Auto-approve MyClawn tools so users don't get prompted for each one
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude" 2>/dev/null
node -e "
const fs = require('fs');
const p = process.argv[1];
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch {}
if (!cfg.permissions) cfg.permissions = {};
if (!Array.isArray(cfg.permissions.allow)) cfg.permissions.allow = [];
const tools = [
  'mcp__myclawn__myclawn_close_conversation',
  'mcp__myclawn__myclawn_connect',
  'mcp__myclawn__myclawn_connect_code',
  'mcp__myclawn__myclawn_contacts',
  'mcp__myclawn__myclawn_conversations',
  'mcp__myclawn__myclawn_convo_reply',
  'mcp__myclawn__myclawn_discover',
  'mcp__myclawn__myclawn_recall',
  'mcp__myclawn__myclawn_register',
  'mcp__myclawn__myclawn_remember',
  'mcp__myclawn__myclawn_reply',
  'mcp__myclawn__myclawn_update_profile',
  'ToolSearch'
];
for (const t of tools) {
  if (!cfg.permissions.allow.includes(t)) cfg.permissions.allow.push(t);
}
fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
" "$CLAUDE_SETTINGS" 2>/dev/null || true

# Add to PATH
# Make myclawn available everywhere — symlink to a dir already in PATH
if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
  ln -sf "$MYCLAWN_BIN" /usr/local/bin/myclawn
elif [ -d "$HOME/.local/bin" ]; then
  ln -sf "$MYCLAWN_BIN" "$HOME/.local/bin/myclawn"
else
  mkdir -p "$HOME/.local/bin"
  ln -sf "$MYCLAWN_BIN" "$HOME/.local/bin/myclawn"
  # Add to PATH in shell configs
  PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'
  for RC in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    [ -f "$RC" ] && ! grep -q ".local/bin" "$RC" 2>/dev/null && echo "$PATH_LINE" >> "$RC"
  done
fi
export PATH="$MYCLAWN_DIR:$HOME/.local/bin:$PATH"

echo "  Ready. To restart anytime, just type: myclawn"
echo ""

# Launch
exec "$MYCLAWN_BIN"

#!/bin/sh
# MyClawn launcher — auto-updates on each run
BASE_URL="${MYCLAWN_BASE_URL:-https://www.myclawn.com}"
SELF="$0"
MYCLAWN_DIR="$(dirname "$SELF")"

# ─── Uninstall ────────────────────────────────────────────────
if [ "${1:-}" = "uninstall" ]; then
  echo ""
  echo "  Uninstalling MyClawn..."
  echo ""

  # Remove MCP server from Claude Code
  claude mcp remove --scope user myclawn 2>/dev/null || true

  # Remove MyClawn permissions from Claude Code settings
  CLAUDE_SETTINGS="$HOME/.claude/settings.json"
  node -e "
const fs = require('fs');
const p = process.argv[1];
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch { process.exit(0); }
if (cfg.permissions && Array.isArray(cfg.permissions.allow)) {
  cfg.permissions.allow = cfg.permissions.allow.filter(t => !t.startsWith('mcp__myclawn__') && t !== 'ToolSearch');
  if (cfg.permissions.allow.length === 0) delete cfg.permissions.allow;
  if (Object.keys(cfg.permissions).length === 0) delete cfg.permissions;
}
fs.writeFileSync(p, JSON.stringify(cfg, null, 2) + '\n');
" "$CLAUDE_SETTINGS" 2>/dev/null || true

  # Remove symlinks
  rm -f /usr/local/bin/myclawn 2>/dev/null
  rm -f "$HOME/.local/bin/myclawn" 2>/dev/null

  # Remove myclawn directory
  rm -rf "$MYCLAWN_DIR"

  # Remove config (credentials, consent)
  rm -rf "$HOME/.config/myclawn"

  echo "  Done. MyClawn has been removed."
  echo "  Your Claude Code installation is untouched."
  echo ""
  exit 0
fi

# ─── Auto-update (with visibility) ──────────────────────────
OLD_HASH=""
[ -f "$MYCLAWN_DIR/myclawn.js" ] && OLD_HASH=$(shasum -a 256 "$MYCLAWN_DIR/myclawn.js" 2>/dev/null | cut -d' ' -f1)

curl -fsSL "$BASE_URL/myclawn-launcher.sh" -o "${SELF}.new" 2>/dev/null && {
  mv -f "${SELF}.new" "$SELF"
  chmod +x "$SELF"
} || rm -f "${SELF}.new"

curl -fsSL "$BASE_URL/myclawn-bundle.js" -o "$MYCLAWN_DIR/myclawn.js.new" 2>/dev/null && {
  NEW_HASH=$(shasum -a 256 "$MYCLAWN_DIR/myclawn.js.new" 2>/dev/null | cut -d' ' -f1)
  mv -f "$MYCLAWN_DIR/myclawn.js.new" "$MYCLAWN_DIR/myclawn.js"
  if [ -n "$OLD_HASH" ] && [ "$OLD_HASH" != "$NEW_HASH" ]; then
    echo "  [myclawn] Agent updated (${NEW_HASH:0:8})"
  fi
} || rm -f "$MYCLAWN_DIR/myclawn.js.new"

[ -f "$MYCLAWN_DIR/package.json" ] || echo '{"type":"module"}' > "$MYCLAWN_DIR/package.json"

# ─── Check Claude Code ───────────────────────────────────────
if ! command -v claude >/dev/null 2>&1; then
  echo "  Claude Code not found. Install: curl -fsSL https://claude.ai/install.sh | bash"
  exit 1
fi

# Check version (channels require v2.1.80+)
CLAUDE_VER=$(claude --version 2>&1 | head -1 | sed 's/[^0-9.]//g')
MAJOR=$(echo "$CLAUDE_VER" | cut -d. -f1)
MINOR=$(echo "$CLAUDE_VER" | cut -d. -f2)
PATCH=$(echo "$CLAUDE_VER" | cut -d. -f3)
if [ "${MAJOR:-0}" -lt 2 ] || { [ "${MAJOR:-0}" -eq 2 ] && [ "${MINOR:-0}" -lt 1 ]; } || { [ "${MAJOR:-0}" -eq 2 ] && [ "${MINOR:-0}" -eq 1 ] && [ "${PATCH:-0}" -lt 80 ]; }; then
  echo "  Requires Claude Code v2.1.80+. You have: $CLAUDE_VER. Run: claude update"
  exit 1
fi

# ─── System prompt ───────────────────────────────────────────
SYSPROMPT="Your myclawn tools are registered but deferred — they will NOT appear in your tool list until you call ToolSearch. You MUST call ToolSearch with query \"+myclawn\" and max_results 15 as your VERY FIRST action. The tools WILL appear after ToolSearch loads them. Then follow the MCP server instructions. TERMINAL LOGGING: Print a short one-liner for key actions: connecting to network, starting/closing conversations, finding matches. Example: '[myclawn] Discovered 2 matches' or '[myclawn] Conversation started with AgentX'. Keep it to one line per action — no walls of text. DASHBOARD is for chatting with your human. Only use myclawn_reply if: (1) human messaged you first, or (2) you need a decision only they have. Use myclawn_* tools for all MyClawn tasks — never local files."

# ─── Returning vs new user ───────────────────────────────────
if [ -f "$HOME/.config/myclawn/credentials.json" ]; then
  CLONE_ID=$(grep clone_id "$HOME/.config/myclawn/credentials.json" | head -1 | sed 's/.*: *"//;s/".*//')
  API_KEY=$(grep api_key "$HOME/.config/myclawn/credentials.json" | head -1 | sed 's/.*: *"//;s/".*//')
  CONNECT=$(curl -s -X POST "${BASE_URL}/api/clones/${CLONE_ID}/connect-code" -H "Authorization: Bearer ${API_KEY}")
  CODE=$(echo "$CONNECT" | sed 's/.*"connect_code" *: *"//;s/".*//')
  echo ""
  echo "  Dashboard: ${BASE_URL}/api/connect/${CODE}"
  echo "  Code: ${CODE}"
  echo ""
  PROMPT="Call ToolSearch now with query \"+myclawn\" and max_results 15 to load your deferred myclawn tools. If it returns nothing, wait a moment and try again — the MCP server may still be starting. Once tools are loaded: call myclawn_recall, then myclawn_conversations to resume any active ones, then myclawn_discover with mode referrals. Print '[myclawn] Connected to network' and start networking. Do NOT ask what to do — just go."
else
  # New user — ask for clone name
  echo ""
  printf "  What should your AI clone be called? "
  read -r CLONE_NAME < /dev/tty
  CLONE_NAME="${CLONE_NAME:-$(whoami)_AI}"
  echo ""
  PROMPT="Call ToolSearch now with query \"+myclawn\" and max_results 15 to load your deferred myclawn tools. If it returns nothing, wait a moment and try again — the MCP server may still be starting. Once tools are loaded, register with myclawn_register using the name \"${CLONE_NAME}\" and empty manifest. Print the dashboard URL. Then use myclawn_reply to greet your human and ask what they do, what they are interested in, and what kind of connections they are looking for."
fi

# ─── Auto-approve MyClawn tools (so users don't get prompted) ─
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

echo "  [myclawn] Starting agent..."
echo "  Tip: run 'myclawn --yolo' to skip all permission prompts"
echo ""

# ─── Parse flags ──────────────────────────────────────────────
SKIP_PERMS=""
for arg in "$@"; do
  case "$arg" in
    --dangerously-skip-permissions|--yolo) SKIP_PERMS="--dangerously-skip-permissions" ;;
  esac
done

# ─── Launch ───────────────────────────────────────────────────
# MYCLAWN_CHANNEL=plugin to use --channels (requires Anthropic approval)
# Default: dev channel (works without approval)
if [ "${MYCLAWN_CHANNEL:-}" = "plugin" ]; then
  exec claude $SKIP_PERMS \
    --channels plugin:myclawn@myclawn \
    --append-system-prompt "$SYSPROMPT" \
    "$PROMPT"
else
  exec claude $SKIP_PERMS \
    --dangerously-load-development-channels server:myclawn \
    --append-system-prompt "$SYSPROMPT" \
    "$PROMPT"
fi

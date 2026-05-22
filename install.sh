#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[mcp-atlassian]${NC} $*"; }
warn()  { echo -e "${YELLOW}[mcp-atlassian] WARNING:${NC} $*"; }
abort() { echo -e "${RED}[mcp-atlassian] ERROR:${NC} $*" >&2; exit 1; }

# ---- OS check ----
if [[ "$(uname -s)" != "Darwin" ]]; then
  abort "This installer only supports macOS. Detected: $(uname -s)"
fi

# ---- Homebrew ----
if ! command -v brew &>/dev/null; then
  warn "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
info "Homebrew: OK"

# ---- git ----
if ! command -v git &>/dev/null; then
  info "Installing git..."
  brew install git
fi
info "git: OK"

# ---- uv ----
if ! command -v uv &>/dev/null; then
  info "Installing uv..."
  brew install uv
fi
info "uv: OK"

# ---- jq ----
if ! command -v jq &>/dev/null; then
  info "Installing jq..."
  brew install jq
fi
info "jq: OK"

# ---- claude CLI ----
CLAUDE_CLI_FOUND=true
if ! command -v claude &>/dev/null; then
  warn "'claude' CLI not found. Claude Code CLI registration will be skipped."
  warn "Install it from: https://claude.ai/download"
  CLAUDE_CLI_FOUND=false
fi

# ---- clone repo ----
REPO_DIR="$HOME/.mcp/atlassian/repo"
if [[ -d "$REPO_DIR" ]]; then
  info "Repo already exists at $REPO_DIR - skipping clone."
else
  info "Cloning sooperset/mcp-atlassian..."
  mkdir -p "$(dirname "$REPO_DIR")"
  git clone https://github.com/sooperset/mcp-atlassian.git "$REPO_DIR"
fi
info "Repo: OK"

# ---- credentials ----
echo ""
echo "=========================================="
echo " Atlassian credentials required"
echo "=========================================="
echo ""
echo "You will need an Atlassian API token."
echo "Generate one at:"
echo "  https://id.atlassian.com/manage-profile/security/api-tokens"
echo ""
read -rp "Press Enter once you have your token ready..."
echo ""

read -rp "Atlassian base URL (e.g. https://yourcompany.atlassian.net): " ATLASSIAN_URL
ATLASSIAN_URL="${ATLASSIAN_URL%/}"

read -rp "Email address: " ATLASSIAN_EMAIL

read -rsp "API token: " ATLASSIAN_TOKEN
echo ""

# ---- write files ----
ENV_FILE="$HOME/.mcp/atlassian/.env"
START_SCRIPT="$HOME/.mcp/atlassian/start.sh"

mkdir -p "$HOME/.mcp/atlassian"

if [[ -f "$ENV_FILE" ]]; then
  read -rp ".env already exists. Overwrite? [y/N] " OVERWRITE
  [[ "$OVERWRITE" =~ ^[Yy]$ ]] || abort "Aborted. Existing .env preserved."
fi

cat > "$ENV_FILE" <<EOF
JIRA_URL=${ATLASSIAN_URL}
JIRA_USERNAME=${ATLASSIAN_EMAIL}
JIRA_API_TOKEN=${ATLASSIAN_TOKEN}
CONFLUENCE_URL=${ATLASSIAN_URL}/wiki
CONFLUENCE_USERNAME=${ATLASSIAN_EMAIL}
CONFLUENCE_API_TOKEN=${ATLASSIAN_TOKEN}
EOF
chmod 600 "$ENV_FILE"
info ".env written to $ENV_FILE"

cat > "$START_SCRIPT" << 'STARTEOF'
#!/bin/bash
set -a
# shellcheck source=/dev/null
source "$HOME/.mcp/atlassian/.env"
set +a
exec uv run --directory "$HOME/.mcp/atlassian/repo" mcp-atlassian
STARTEOF
chmod +x "$START_SCRIPT"
info "start.sh written to $START_SCRIPT"

# ---- register MCP ----
register_claude_code() {
  if [[ "$CLAUDE_CLI_FOUND" == "false" ]]; then
    warn "Skipping Claude Code CLI registration - 'claude' not found."
    return
  fi
  info "Registering with Claude Code CLI..."
  claude mcp add mcp-atlassian "$START_SCRIPT"
  info "Claude Code CLI: registered."
}

register_claude_desktop() {
  local config_path="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  if [[ ! -f "$config_path" ]]; then
    warn "Claude Desktop config not found at: $config_path"
    warn "Is Claude Desktop installed? Skipping."
    return
  fi
  info "Registering with Claude Desktop..."
  local tmp
  tmp=$(mktemp)
  jq --arg cmd "$START_SCRIPT" \
    '.mcpServers["mcp-atlassian"] = {"command": $cmd, "args": []}' \
    "$config_path" > "$tmp" && mv "$tmp" "$config_path"
  info "Claude Desktop: registered."
}

echo ""
echo "Where would you like to register the MCP server?"
echo "  1) Claude Code CLI only"
echo "  2) Claude Desktop only"
echo "  3) Both"
read -rp "Enter choice [1-3]: " REGISTER_CHOICE

case "$REGISTER_CHOICE" in
  1) register_claude_code ;;
  2) register_claude_desktop ;;
  3) register_claude_code; register_claude_desktop ;;
  *) warn "Invalid choice. Skipping MCP registration." ;;
esac

# ---- done ----
echo ""
echo -e "${GREEN}=========================================="
echo " mcp-atlassian installed successfully!"
echo -e "==========================================${NC}"
echo ""
echo "Next steps:"
echo "  1. Restart Claude to pick up the new MCP server."
echo "  2. Test it by asking: \"List my open Jira issues\""
echo ""

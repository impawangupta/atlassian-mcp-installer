#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[mcp-installer]${NC} $*"; }
warn()  { echo -e "${YELLOW}[mcp-installer] WARNING:${NC} $*"; }
abort() { echo -e "${RED}[mcp-installer] ERROR:${NC} $*" >&2; exit 1; }

ask()        { printf "%s" "$1" >/dev/tty; read -r "$2" </dev/tty; }
ask_secret() { printf "%s" "$1" >/dev/tty; read -rs "$2" </dev/tty; echo >/dev/tty; }
ask_yn()     { ask "$1 [Y/n] " "$2"; [[ -n "${!2}" ]] || printf -v "$2" 'y'; }

# ---- OS check ----
[[ "$(uname -s)" == "Darwin" ]] || abort "This installer only supports macOS. Detected: $(uname -s)"

# ---- Homebrew ----
if ! command -v brew &>/dev/null; then
  warn "Homebrew not found. Installing..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || abort "Failed to install Homebrew."
fi
for _brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [[ -x "$_brew_bin" ]]; then eval "$("$_brew_bin" shellenv)"; break; fi
done
command -v brew &>/dev/null || abort "Homebrew installed but 'brew' not on PATH. Open a new terminal and re-run."
info "Homebrew: OK"

# ---- Dependency installer ----
# Wrapped in if/else so set -e does not trigger on brew install failure
install_dep() {
  local cmd="$1" pkg="${2:-$1}"
  if command -v "$cmd" &>/dev/null; then
    info "$pkg: OK"
    return 0
  fi
  info "Installing $pkg..."
  if brew install "$pkg"; then
    hash -r 2>/dev/null || true
    for _brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      if [[ -x "$_brew_bin" ]]; then eval "$("$_brew_bin" shellenv)"; break; fi
    done
  else
    abort "Failed to install $pkg. Please run manually: brew install $pkg"
  fi
  command -v "$cmd" &>/dev/null || abort "'$cmd' not found after install. Try: export PATH=/opt/homebrew/bin:\$PATH"
  info "$pkg: OK"
}

# ---- Dependencies ----
install_dep git
install_dep uv
install_dep jq
install_dep node
command -v npx &>/dev/null || abort "'npx' not found - it should come bundled with Node.js. Check your PATH."

# ---- Detect available Claude clients ----
CLAUDE_CLI_FOUND=false
CLAUDE_DESKTOP_FOUND=false
DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

command -v claude &>/dev/null && CLAUDE_CLI_FOUND=true

# Desktop: config file might not exist yet on fresh install - create it
if [[ -d "$HOME/Library/Application Support/Claude" ]]; then
  CLAUDE_DESKTOP_FOUND=true
  if [[ ! -f "$DESKTOP_CONFIG" ]]; then
    echo '{"mcpServers": {}}' > "$DESKTOP_CONFIG"
  fi
elif [[ -f "$DESKTOP_CONFIG" ]]; then
  CLAUDE_DESKTOP_FOUND=true
fi

if [[ "$CLAUDE_CLI_FOUND" == "false" ]]; then
  warn "'claude' CLI not found - Claude Code CLI registration will be skipped."
  warn "Install it from: https://claude.ai/download"
fi
if [[ "$CLAUDE_DESKTOP_FOUND" == "false" ]]; then
  warn "Claude Desktop not found - Desktop registration will be skipped."
fi

[[ "$CLAUDE_CLI_FOUND" == "false" && "$CLAUDE_DESKTOP_FOUND" == "false" ]] && \
  abort "Neither Claude CLI nor Claude Desktop found. Install at least one and re-run."

# ---- Claude Code scope - asked once, used for all servers ----
MCP_SCOPE="user"
if [[ "$CLAUDE_CLI_FOUND" == "true" ]]; then
  echo ""
  echo "Select Claude Code registration scope (applies to all MCP servers):"
  echo "  1) user    - available in all projects (recommended)"
  echo "  2) project - shared with your team via .claude/settings.json"
  echo "  3) local   - current project only"
  ask "Choice [1-3, default 1]: " SCOPE_CHOICE
  case "${SCOPE_CHOICE:-1}" in
    2) MCP_SCOPE="project" ;;
    3) MCP_SCOPE="local" ;;
    *) MCP_SCOPE="user" ;;
  esac
  info "Claude Code scope: $MCP_SCOPE"
fi

# ---- Helpers ----

name_exists() {
  local name="$1"
  if [[ "$CLAUDE_CLI_FOUND" == "true" ]]; then
    claude mcp list 2>/dev/null | grep -q "^${name}:" && return 0
  fi
  if [[ "$CLAUDE_DESKTOP_FOUND" == "true" ]]; then
    jq -e --arg n "$name" '.mcpServers[$n] // empty' "$DESKTOP_CONFIG" &>/dev/null && return 0
  fi
  return 1
}

# Sets global PICKED_NAME
pick_name() {
  PICKED_NAME="$1"
  if name_exists "$PICKED_NAME"; then
    warn "An MCP server named '$PICKED_NAME' already exists."
    ask "Enter a new name (or press Enter to overwrite '$PICKED_NAME'): " PICKED_NAME
    [[ -n "$PICKED_NAME" ]] || PICKED_NAME="$1"
  fi
}

# Register with all available Claude clients
register_mcp() {
  local name="$1" start_script="$2"

  if [[ "$CLAUDE_CLI_FOUND" == "true" ]]; then
    info "Registering '$name' with Claude Code CLI (scope: $MCP_SCOPE)..."
    claude mcp remove "$name" 2>/dev/null || true
    claude mcp add --scope "$MCP_SCOPE" "$name" "$start_script" \
      || warn "Could not register '$name' with Claude Code CLI."
  fi

  if [[ "$CLAUDE_DESKTOP_FOUND" == "true" ]]; then
    info "Registering '$name' with Claude Desktop..."
    local updated tmp
    updated=$(jq --arg n "$name" --arg cmd "$start_script" \
      '.mcpServers[$n] = {"command": $cmd, "args": []}' \
      "$DESKTOP_CONFIG" 2>/dev/null) || { warn "jq error updating Desktop config for '$name'."; return; }
    tmp=$(mktemp)
    echo "$updated" > "$tmp" && mv "$tmp" "$DESKTOP_CONFIG" \
      || warn "Failed to write Desktop config for '$name'."
  fi
}

PICKED_NAME=""

# ==========================================
# [1/3] mcp-atlassian - Jira + Confluence
# ==========================================
echo ""
echo -e "${GREEN}==========================================${NC}"
echo " [1/3] mcp-atlassian (Jira + Confluence)"
echo -e "${GREEN}==========================================${NC}"
ask_yn "Set up mcp-atlassian?" SETUP_ATLASSIAN

ATLASSIAN_EMAIL=""
ATLASSIAN_TOKEN=""

if [[ "$SETUP_ATLASSIAN" =~ ^[Yy] ]]; then
  mkdir -p "$HOME/.mcp/atlassian"
  ATL_ENV="$HOME/.mcp/atlassian/.env"
  ATL_START="$HOME/.mcp/atlassian/start.sh"
  WRITE_ATL_ENV=false

  if [[ -f "$ATL_ENV" ]]; then
    info "Existing credentials found at $ATL_ENV."
    ask "Update credentials? [y/N] " UPDATE_ATL
    if [[ "${UPDATE_ATL:-n}" =~ ^[Yy]$ ]]; then WRITE_ATL_ENV=true; fi
  else
    WRITE_ATL_ENV=true
  fi

  if [[ "$WRITE_ATL_ENV" == "true" ]]; then
    ATLASSIAN_REPO="$HOME/.mcp/atlassian/repo"
    if [[ -d "$ATLASSIAN_REPO" ]]; then
      info "Atlassian repo already cloned at $ATLASSIAN_REPO."
    else
      info "Cloning sooperset/mcp-atlassian..."
      mkdir -p "$(dirname "$ATLASSIAN_REPO")"
      git clone https://github.com/sooperset/mcp-atlassian.git "$ATLASSIAN_REPO" \
        || abort "Failed to clone mcp-atlassian."
    fi

    echo ""
    echo "Generate an Atlassian API token at:"
    echo "  https://id.atlassian.com/manage-profile/security/api-tokens"
    echo ""
    ask "Press Enter when you have your token ready..." _DUMMY

    ask "Company name (e.g. yourcompany for yourcompany.atlassian.net): " ATLASSIAN_COMPANY
    ATLASSIAN_URL="https://${ATLASSIAN_COMPANY}.atlassian.net"
    ask "Email address: " ATLASSIAN_EMAIL
    ask_secret "API token: " ATLASSIAN_TOKEN

    cat > "$ATL_ENV" <<EOF
JIRA_URL=${ATLASSIAN_URL}
JIRA_USERNAME=${ATLASSIAN_EMAIL}
JIRA_API_TOKEN=${ATLASSIAN_TOKEN}
CONFLUENCE_URL=${ATLASSIAN_URL}/wiki
CONFLUENCE_USERNAME=${ATLASSIAN_EMAIL}
CONFLUENCE_API_TOKEN=${ATLASSIAN_TOKEN}
EOF
    chmod 600 "$ATL_ENV"
    info "Atlassian .env written."
  fi

  cat > "$ATL_START" << 'STARTEOF'
#!/bin/bash
set -a
# shellcheck source=/dev/null
source "$HOME/.mcp/atlassian/.env"
set +a
exec uv run --directory "$HOME/.mcp/atlassian/repo" mcp-atlassian
STARTEOF
  chmod +x "$ATL_START"

  pick_name "mcp-atlassian"
  ATL_NAME="$PICKED_NAME"
  register_mcp "$ATL_NAME" "$ATL_START"
  info "mcp-atlassian setup complete."
fi

# ==========================================
# [2/3] mcp-bitbucket
# ==========================================
echo ""
echo -e "${GREEN}==========================================${NC}"
echo " [2/3] mcp-bitbucket"
echo -e "${GREEN}==========================================${NC}"
ask_yn "Set up mcp-bitbucket?" SETUP_BITBUCKET

if [[ "$SETUP_BITBUCKET" =~ ^[Yy] ]]; then
  mkdir -p "$HOME/.mcp/bitbucket"
  BB_ENV="$HOME/.mcp/bitbucket/.env"
  BB_START="$HOME/.mcp/bitbucket/start.sh"
  WRITE_BB_ENV=false

  if [[ -f "$BB_ENV" ]]; then
    info "Existing credentials found at $BB_ENV."
    ask "Update credentials? [y/N] " UPDATE_BB
    if [[ "${UPDATE_BB:-n}" =~ ^[Yy]$ ]]; then WRITE_BB_ENV=true; fi
  else
    WRITE_BB_ENV=true
  fi

  if [[ "$WRITE_BB_ENV" == "true" ]]; then
    # Reuse credentials entered this run if Atlassian was just set up
    if [[ -n "$ATLASSIAN_EMAIL" ]] && [[ -n "$ATLASSIAN_TOKEN" ]]; then
      info "Reusing Atlassian credentials for Bitbucket."
      BB_EMAIL="$ATLASSIAN_EMAIL"
      BB_TOKEN="$ATLASSIAN_TOKEN"
    else
      echo ""
      echo "Bitbucket uses your Atlassian account credentials (same API token)."
      echo "Generate one at: https://id.atlassian.com/manage-profile/security/api-tokens"
      echo ""
      ask "Atlassian email: " BB_EMAIL
      ask_secret "Atlassian API token: " BB_TOKEN
    fi

    ask "Default Bitbucket workspace (optional - press Enter to skip): " BB_WORKSPACE

    {
      echo "ATLASSIAN_USER_EMAIL=${BB_EMAIL}"
      echo "ATLASSIAN_API_TOKEN=${BB_TOKEN}"
      [[ -n "${BB_WORKSPACE:-}" ]] && echo "BITBUCKET_DEFAULT_WORKSPACE=${BB_WORKSPACE}"
    } > "$BB_ENV"
    chmod 600 "$BB_ENV"
    info "Bitbucket .env written."
  fi

  cat > "$BB_START" << 'STARTEOF'
#!/bin/bash
set -a
# shellcheck source=/dev/null
source "$HOME/.mcp/bitbucket/.env"
set +a
exec npx -y @aashari/mcp-server-atlassian-bitbucket
STARTEOF
  chmod +x "$BB_START"

  pick_name "mcp-bitbucket"
  BB_NAME="$PICKED_NAME"
  register_mcp "$BB_NAME" "$BB_START"
  info "mcp-bitbucket setup complete."
fi

# ==========================================
# [3/3] circleci
# ==========================================
echo ""
echo -e "${GREEN}==========================================${NC}"
echo " [3/3] circleci"
echo -e "${GREEN}==========================================${NC}"
ask_yn "Set up CircleCI MCP?" SETUP_CIRCLECI

if [[ "$SETUP_CIRCLECI" =~ ^[Yy] ]]; then
  mkdir -p "$HOME/.mcp/circleci"
  CI_ENV="$HOME/.mcp/circleci/.env"
  CI_START="$HOME/.mcp/circleci/start.sh"
  WRITE_CI_ENV=false

  if [[ -f "$CI_ENV" ]]; then
    info "Existing credentials found at $CI_ENV."
    ask "Update credentials? [y/N] " UPDATE_CI
    if [[ "${UPDATE_CI:-n}" =~ ^[Yy]$ ]]; then WRITE_CI_ENV=true; fi
  else
    WRITE_CI_ENV=true
  fi

  if [[ "$WRITE_CI_ENV" == "true" ]]; then
    echo ""
    echo "Generate a CircleCI API token at:"
    echo "  https://app.circleci.com/settings/user/tokens"
    echo ""
    ask "Press Enter when you have your token ready..." _DUMMY

    ask_secret "CircleCI API token: " CIRCLECI_TOKEN

    cat > "$CI_ENV" <<EOF
CIRCLECI_TOKEN=${CIRCLECI_TOKEN}
CIRCLECI_BASE_URL=https://circleci.com
EOF
    chmod 600 "$CI_ENV"
    info "CircleCI .env written."
  fi

  cat > "$CI_START" << 'STARTEOF'
#!/bin/bash
set -a
# shellcheck source=/dev/null
source "$HOME/.mcp/circleci/.env"
set +a
exec npx -y @circleci/mcp-server-circleci@latest
STARTEOF
  chmod +x "$CI_START"

  pick_name "circleci"
  CI_NAME="$PICKED_NAME"
  register_mcp "$CI_NAME" "$CI_START"
  info "CircleCI setup complete."
fi

# ---- done ----
echo ""
echo -e "${GREEN}=========================================="
echo " Installation complete!"
echo -e "==========================================${NC}"
echo ""
echo "Restart Claude to pick up the new MCP servers."
echo ""
echo "To test:"
echo "  Atlassian: \"List my open Jira issues\""
echo "  Bitbucket: \"List my Bitbucket workspaces\""
echo "  CircleCI:  \"Show my recent CircleCI pipelines\""
echo ""

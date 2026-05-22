# mcp-atlassian Installer

One-command setup for [sooperset/mcp-atlassian](https://github.com/sooperset/mcp-atlassian) on macOS. Installs the MCP server and registers it with Claude Code CLI, Claude Desktop, or both.

## Requirements

- macOS
- A terminal

Everything else (Homebrew, git, uv, jq) is installed automatically if missing.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/<your-username>/atlassian-mcp-installer/main/install.sh | bash
```

## What it does

1. Checks you are on macOS
2. Installs missing prerequisites (Homebrew, git, uv, jq)
3. Clones `sooperset/mcp-atlassian` into `~/.mcp/atlassian/repo`
4. Prompts for your Atlassian credentials (base URL, email, API token)
5. Writes `~/.mcp/atlassian/.env` and `~/.mcp/atlassian/start.sh`
6. Registers the MCP server with Claude Code CLI, Claude Desktop, or both

## Credentials

You will need an Atlassian API token. The installer will direct you here:
https://id.atlassian.com/manage-profile/security/api-tokens

## File locations

| File | Purpose |
|------|---------|
| `~/.mcp/atlassian/repo` | Cloned mcp-atlassian source |
| `~/.mcp/atlassian/.env` | Your Atlassian credentials (chmod 600) |
| `~/.mcp/atlassian/start.sh` | MCP server launch script |

## Re-running

Re-running the installer skips the repo clone if it already exists and prompts before overwriting an existing `.env`.

## License

MIT

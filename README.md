# Atlassian MCP Installer

One-command setup for Atlassian (Jira + Confluence), Bitbucket, and CircleCI MCP servers on macOS. Registers them with Claude Code CLI, Claude Desktop, or both - whichever is available.

## Requirements

- macOS
- A terminal

Everything else (Homebrew, git, uv, jq, node) is installed automatically if missing.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/impawangupta/atlassian-mcp-installer/main/install.sh | bash
```

## What it does

1. Checks you are on macOS
2. Installs missing prerequisites (Homebrew, git, uv, jq, node)
3. Detects Claude Code CLI and Claude Desktop - registers with all available clients
4. Walks through three optional sections:

| Section | MCP server | What you need |
|---------|-----------|---------------|
| **[1/3] mcp-atlassian** | Jira + Confluence | Atlassian API token |
| **[2/3] mcp-bitbucket** | Bitbucket repos + PRs | Same Atlassian token (reused automatically) |
| **[3/3] circleci** | CircleCI pipelines | CircleCI API token |

Each section can be skipped individually.

## Credentials

- **Atlassian API token** (used for both Atlassian and Bitbucket): https://id.atlassian.com/manage-profile/security/api-tokens
- **CircleCI API token**: https://app.circleci.com/settings/user/tokens

## File locations

| File | Purpose |
|------|---------|
| `~/.mcp/atlassian/.env` | Atlassian credentials (chmod 600) |
| `~/.mcp/atlassian/start.sh` | Atlassian MCP launch script |
| `~/.mcp/atlassian/repo` | Cloned mcp-atlassian source |
| `~/.mcp/bitbucket/.env` | Bitbucket credentials (chmod 600) |
| `~/.mcp/bitbucket/start.sh` | Bitbucket MCP launch script |
| `~/.mcp/circleci/.env` | CircleCI credentials (chmod 600) |
| `~/.mcp/circleci/start.sh` | CircleCI MCP launch script |

## Re-running

Re-running the installer detects existing credentials and skips prompts by default. Each section asks "Update credentials? [y/N]" - answering N goes straight to re-registration. This makes adding Desktop registration to an existing Claude Code setup a zero-credential-entry re-run.

## License

MIT

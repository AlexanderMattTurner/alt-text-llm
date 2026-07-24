#!/bin/bash
# Session setup script for Claude Code
# Installs dependencies and configures environment for git hooks

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

#######################################
# Helpers
#######################################

warn() { echo "Warning: $1" >&2; }
die() {
  echo "ERROR: $1" >&2
  exit 1
}
is_root() { [ "$(id -u)" = "0" ]; }

# Install a command via pip if missing
pip_install_if_missing() {
  local cmd="$1" pkg="${2:-$1}"
  if ! command -v "$cmd" &>/dev/null; then
    pip3 install --quiet "$pkg" || warn "Failed to install $pkg"
  fi
}

# Install a command via webi if missing
webi_install_if_missing() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
<<<<<<< local
    echo "Installing $cmd..."
    curl -sS "https://webi.sh/$cmd" | sh >/dev/null 2>&1 || warn "Failed to install $cmd"
=======
    local installer
    installer=$(mktemp "${TMPDIR:-/tmp}/webi-${cmd}-XXXXXX.sh")
    # webi.sh serves a per-tool bootstrap generated on the fly, so there is no
    # stable digest to pin; we harden with HTTPS-only (--proto =https), the
    # shebang check below, and a version-pinned $pkg instead.
    # pin-exempt: webi.sh bootstrap is generated per-request, no stable digest
    if curl --proto '=https' -fsSL "https://webi.sh/$pkg" -o "$installer" 2>/dev/null; then
      first_line="$(head -n 1 "$installer")"
      if grep -q '^#!' <<<"$first_line"; then
        sh "$installer" >/dev/null 2>&1 || warn "Failed to install $cmd"
      else
        warn "Installer for $cmd is not a shell script (missing shebang) — skipping"
      fi
    else
      warn "Failed to download installer for $cmd"
    fi
    rm -f "$installer"
>>>>>>> template
  fi
}

#######################################
<<<<<<< local
=======
# Hook syntax validation
#######################################

# A hook script with a syntax error (e.g. unresolved merge conflict markers)
# exits non-zero before any logic runs, which Claude Code treats as a block.
# Surface broken hooks at session start so they can be fixed before the first
# tool call dies with no explanation.
_check_hook_syntax() {
  local dir file out
  for dir in "$PROJECT_DIR/.claude/hooks" "$PROJECT_DIR/.hooks"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' file; do
      # Filter — only extensions this function knows how to syntax-check are
      # handled; any other file is correctly skipped.
      # case-default-ok: no-match is the intended no-op, not a missed case.
      case "$file" in
      *.sh | *.bash)
        if ! out=$(bash -n "$file" 2>&1); then
          warn "hook has bash syntax error: ${file#"$PROJECT_DIR/"}"
          [[ -n "$out" ]] && echo "$out" >&2
        fi
        ;;
      *.py)
        if command -v python3 &>/dev/null && ! out=$(python3 -m py_compile "$file" 2>&1); then
          warn "hook has python syntax error: ${file#"$PROJECT_DIR/"}"
          [[ -n "$out" ]] && echo "$out" >&2
        fi
        ;;
      esac
    done < <(find "$dir" -maxdepth 1 -type f -print0)
  done
}

_check_hook_syntax

#######################################
>>>>>>> template
# PATH setup
#######################################

export PATH="$HOME/.local/bin:$PATH"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >>"$CLAUDE_ENV_FILE"
fi

#######################################
# Tool installation (optional - warn on failure)
#######################################

echo "Installing tools..."

# Install shfmt for shell script formatting
webi_install_if_missing shfmt

# Install GitHub CLI for PR workflows
webi_install_if_missing gh

# Install jq for JSON processing (used by hooks)
webi_install_if_missing jq

# Install shellcheck for shell script linting (requires root)
if ! command -v shellcheck &>/dev/null && is_root; then
  if ! { apt-get update -qq && apt-get install -y -qq shellcheck; } 2>/dev/null; then
    warn "Failed to install shellcheck"
  fi
fi

#######################################
# Git setup
#######################################

cd "$PROJECT_DIR" || exit 1
git config core.hooksPath .hooks

#######################################
# GitHub CLI auth
#######################################

<<<<<<< local
if [ -n "${GH_TOKEN:-}" ] && command -v gh &>/dev/null; then
  echo "Configuring GitHub authentication..."
  echo "$GH_TOKEN" | gh auth login --with-token 2>&1 || warn "Failed to authenticate with GitHub"
=======
if ! command -v gh &>/dev/null; then
  warn "gh CLI not found"
elif [[ -z "${GH_TOKEN:-}" ]]; then
  warn "GH_TOKEN is not set — GitHub CLI requires authentication"
fi

#######################################
# GitHub repo detection for proxy environments
#######################################

# In Claude Code web sessions, git remotes use a local proxy URL like:
#   http://local_proxy@127.0.0.1:18393/git/owner/repo
# The gh CLI can't detect the GitHub repo from this, so we extract
# owner/repo and export GH_REPO to make all gh commands work.

if [[ -z "${GH_REPO:-}" ]]; then
  remote_url=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null)
  # Anchor to the real local-proxy host authority — the same predicate the
  # web-session permission grant below uses. A bare /git/owner/repo suffix on a
  # hostile origin (e.g. https://attacker.example/git/evil/repo) must not be
  # allowed to redirect every subsequent gh command at an attacker's repo.
  # BASH_REMATCH[1] is the optional port group; owner/repo is [2].
  if [[ "$remote_url" =~ ^https?://[^/@]*@127\.0\.0\.1(:[0-9]+)?/git/([^/]+/[^/]+)$ ]]; then
    GH_REPO="${BASH_REMATCH[2]}"
    GH_REPO="${GH_REPO%.git}"
    export GH_REPO
    emit_export GH_REPO "$GH_REPO"
  fi
fi

#######################################
# Web-session permissions
#######################################

# In web sessions (detected by proxy remote URL), grant Claude Code
# permission to modify its own .claude/ folder without prompting.
remote_url="${remote_url:-$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null)}"
if [[ "$remote_url" =~ ^https?://[^/@]*@127\.0\.0\.1(:[0-9]+)?/git/ ]]; then
  local_settings="$PROJECT_DIR/.claude/settings.local.json"
  if [[ ! -f "$local_settings" ]]; then
    cat >"$local_settings" <<'SETTINGS'
{
  "permissions": {
    "allow": [
      "Edit(.claude/**)",
      "Write(.claude/**)",
      "Read(.claude/**)",
      "Bash(pnpm build)",
      "Bash(pnpm check:*)",
      "Bash(pnpm format)",
      "Bash(pnpm install)",
      "Bash(pnpm lint:*)",
      "Bash(pnpm test:*)",
      "Bash(pre-commit run:*)",
      "Bash(uv run pytest:*)"
    ]
  }
}
SETTINGS
  fi
>>>>>>> template
fi

#######################################
# Project dependencies
#######################################

# Install Node dependencies if package.json exists and node_modules is missing
if [ -f "$PROJECT_DIR/package.json" ] && [ ! -d "$PROJECT_DIR/node_modules" ]; then
  echo "Installing Node dependencies..."
  if command -v pnpm &>/dev/null; then
    pnpm install --silent || warn "Failed to install Node dependencies"
  elif command -v npm &>/dev/null; then
    npm install --silent || warn "Failed to install Node dependencies"
  fi
fi

# Install Python dependencies if uv.lock exists
if [ -f "$PROJECT_DIR/uv.lock" ] && command -v uv &>/dev/null; then
  uv sync --quiet 2>/dev/null || warn "Failed to sync Python dependencies"
fi

echo "Session setup complete"

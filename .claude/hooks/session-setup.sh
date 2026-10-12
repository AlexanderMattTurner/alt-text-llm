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

# Append `export NAME=<value>` to the session env file, quoting the value with
# bash's @Q operator. Interpolating a value straight into a double-quoted string
# (e.g. "export X=\"$val\"") is not escaping it — a value containing a `"` or `$`
# becomes arbitrary code in whatever later sources this file.
emit_export() {
  local name="$1" value="$2"
  [[ -n "${CLAUDE_ENV_FILE:-}" ]] || return 0
  echo "export $name=${value@Q}" >>"$CLAUDE_ENV_FILE"
}

# Install a command via pip if missing
pip_install_if_missing() {
  local cmd="$1" pkg="${2:-$1}"
  if ! command -v "$cmd" &>/dev/null; then
    pip3 install --quiet "$pkg" || warn "Failed to install $pkg"
  fi
}

# Install a command via webi if missing
webi_install_if_missing() {
  local cmd="$1" pkg="${2:-$1}"
  if ! command -v "$cmd" &>/dev/null; then
    local installer
    installer=$(mktemp "${TMPDIR:-/tmp}/webi-${cmd}-XXXXXX.sh")
    # webi.sh serves a per-tool bootstrap generated on the fly, so there is no
    # stable digest to pin; we harden with HTTPS-only (--proto =https), the
    # shebang check below, and a version-pinned $pkg instead.
    # pin-exempt: webi.sh bootstrap is generated per-request, no stable digest
    if curl --proto '=https' -fsSL --retry 3 --retry-delay 2 "https://webi.sh/$pkg" -o "$installer" 2>/dev/null; then
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
  fi
}

#######################################
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
# PATH setup
#######################################

export PATH="$HOME/.local/bin:$PATH"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >>"$CLAUDE_ENV_FILE"
fi

#######################################
# Tool installation (optional - warn on failure)
#######################################

<<<<<<< local
echo "Installing tools..."

# Install shfmt for shell script formatting
webi_install_if_missing shfmt

# Install GitHub CLI for PR workflows
webi_install_if_missing gh
||||||| base
# Install tools quietly — only warn on failure (versions pinned for supply-chain safety)
webi_install_if_missing shfmt shfmt@3
webi_install_if_missing gh gh@2
webi_install_if_missing jq jq@1.7
if ! command -v shellcheck &>/dev/null && is_root; then
  { apt-get update -qq && apt-get install -y -qq shellcheck; } || warn "Failed to install shellcheck"
fi
=======
# Install tools quietly — only warn on failure (versions pinned for supply-chain safety)
webi_install_if_missing shfmt shfmt@3
webi_install_if_missing gh gh@2
webi_install_if_missing jq jq@1.7
if ! command -v shellcheck &>/dev/null && is_root; then
  # pin-exempt: last-resort session-bootstrap fallback; apt's shellcheck version
  # varies by base image, and the authoritative pin is the shellcheck-py
  # pre-commit hook's rev, not this fallback binary.
  { apt-get update -qq && apt-get install -y -qq shellcheck; } || warn "Failed to install shellcheck"
fi
>>>>>>> template

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

<<<<<<< local
||||||| base
# Pre-fetch the base branch so diffs against $CLAUDE_CODE_BASE_REF work
# immediately (e.g. when creating PRs). Failure is non-fatal.
if [[ -n "${CLAUDE_CODE_BASE_REF:-}" ]]; then
  git fetch origin "$CLAUDE_CODE_BASE_REF" --quiet 2>/dev/null ||
    warn "Failed to fetch base branch $CLAUDE_CODE_BASE_REF"
fi

=======
# Pre-fetch the base branch so diffs against $CLAUDE_CODE_BASE_REF work
# immediately (e.g. when creating PRs). Failure is non-fatal.
if [[ -n "${CLAUDE_CODE_BASE_REF:-}" ]]; then
  timeout --kill-after=10 60 git fetch origin "$CLAUDE_CODE_BASE_REF" --quiet 2>/dev/null ||
    warn "Failed to fetch base branch $CLAUDE_CODE_BASE_REF"
fi

>>>>>>> template
#######################################
# Syntax-aware merges (mergiraf)
#######################################

# .gitattributes marks file types `merge=mergiraf`, and every one of those
# attributes is INERT until this checkout has the binary on PATH and
# merge.mergiraf.driver in its git config. Git says nothing when either is
# missing — it falls back to its built-in line merge — so a session resolving a
# conflict by hand silently got the line merge. CI registers the driver in
# template-sync's checkout and nowhere else; this is the session's half.
#
# .github/scripts/install-mergiraf.sh owns the pinned download, the sha256
# refusal, the `solve -p` contract probe, the `git config` pair, and the skip
# when all of them already hold, so this only calls it and reports.
install_mergiraf() {
  local installer="$PROJECT_DIR/.github/scripts/install-mergiraf.sh"
  [[ -f "$installer" ]] || return 0

  # The installer downloads a linux_amd64 asset and reads it with sha256sum, so
  # on any other host it would install a binary that cannot run. Say so rather
  # than warn about a download that was never going to work.
  if [[ "$(uname -s) $(uname -m)" != "Linux x86_64" ]]; then
    echo "mergiraf: no pinned asset for $(uname -s)/$(uname -m) — this checkout keeps git's line merge" >&2
    return 0
  fi

  local bindir="$HOME/.local/bin"
  mkdir -p "$bindir" # bare-mkdir-ok: the post-condition is checked on the next line
  [[ -d "$bindir" ]] || {
    warn "mergiraf: $bindir is not a directory — merges use git's line merge"
    return 0
  }

  # A warn, not an exit: every other tool here is optional, and a session with no
  # mergiraf must still start. It merges as it did before the attributes existed.
  # The bound is on the whole install because curl's --connect-timeout does not
  # cap an established transfer, so a stalled download would hang session start.
  local rc=0
  (cd "$PROJECT_DIR" && timeout --kill-after=10 300 bash "$installer" "$bindir") >/dev/null || rc=$?
  # --local because that is the only scope install-mergiraf.sh writes: a global
  # driver, which mergiraf's own setup docs tell users to register, would
  # otherwise answer here and silence both warns.
  local bound
  bound="$(git -C "$PROJECT_DIR" config --local --get merge.mergiraf.driver)" || bound=""

  if [[ "$rc" -eq 0 ]]; then
    # The post-condition, not the exit status: install-mergiraf.sh exits 0 after
    # installing the binary when git refuses the checkout (dubious ownership),
    # which leaves every merge=mergiraf attribute inert and says nothing.
    [[ -n "$bound" ]] ||
      warn "mergiraf installed but merge.mergiraf.driver is unset — merges use git's line merge"
  elif [[ -n "$bound" ]]; then
    # A download or digest refusal aborts BEFORE the binary is replaced, so an
    # earlier run's driver is still bound and still merging — through a version
    # this run did not verify. Saying "line merge" here would name the one
    # outcome that is not happening.
    warn "Failed to install mergiraf — merges keep using the already-bound driver, not git's line merge"
  else
    warn "Failed to install mergiraf — merges in this checkout use git's line merge"
  fi
}

install_mergiraf

#######################################
# GitHub CLI auth
#######################################

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

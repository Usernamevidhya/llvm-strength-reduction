#!/usr/bin/env bash
#
# Publish this project to GitHub.
#
# Runs, in order:
#   git init
#   git add .
#   git commit -m "Initial commit: LLVM Strength Reduction Pass"
#   git branch -M main
#   git remote add origin https://github.com/Usernamevidhya/llvm-strength-reduction.git
#   git push -u origin main
#
# Prerequisite: the (empty) repository must already exist on GitHub, and you
# must be able to authenticate (a credential helper / `gh auth login`, or a
# personal access token used as the HTTPS password).
#
# The script is safe to re-run:
#   * `git init` on an existing repository is a harmless re-initialisation.
#   * If there is nothing new to commit, the commit step is skipped.
#   * If `origin` already exists and points at the same URL, it is reused.
#   * If `origin` exists and points somewhere ELSE, the script stops (so it
#     never silently pushes to the wrong place) unless --force-remote is given,
#     which repoints origin at the target URL.
#
# Usage:  scripts/push_to_github.sh [--force-remote] [-h|--help]
# Override the target with: REPO_URL=<url> scripts/push_to_github.sh

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Usernamevidhya/llvm-strength-reduction.git}"
COMMIT_MSG="Initial commit: LLVM Strength Reduction Pass"
BRANCH="main"
FORCE_REMOTE=0

die()  { echo "error: $*" >&2; exit 1; }
info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-remote) FORCE_REMOTE=1; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git is not installed."

cd "$(dirname "${BASH_SOURCE[0]}")/.."
info "Repository root: $PWD"

# --- 1. git init -----------------------------------------------------------
info "git init"
git init

# Committing requires an identity; fail early with a helpful message.
if ! git config user.name >/dev/null || ! git config user.email >/dev/null; then
  die "git user identity is not set. Run:
    git config --global user.name  \"Your Name\"
    git config --global user.email \"you@example.com\""
fi

# --- 2. git add . ----------------------------------------------------------
info "git add ."
git add .

# --- 3. git commit ---------------------------------------------------------
if git diff --cached --quiet; then
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    warn "nothing new to commit; continuing with the existing history."
  else
    die "nothing to commit and no history exists (is the directory empty?)."
  fi
else
  info "git commit"
  git commit -m "$COMMIT_MSG"
fi

# --- 4. git branch -M main -------------------------------------------------
info "git branch -M $BRANCH"
git branch -M "$BRANCH"

# --- 5. git remote add origin ... -----------------------------------------
if EXISTING_URL="$(git remote get-url origin 2>/dev/null)"; then
  if [[ "$EXISTING_URL" == "$REPO_URL" ]]; then
    info "remote 'origin' already points at $REPO_URL; reusing it."
  elif (( FORCE_REMOTE )); then
    warn "remote 'origin' pointed at $EXISTING_URL; repointing to $REPO_URL (--force-remote)."
    git remote set-url origin "$REPO_URL"
  else
    die "remote 'origin' already exists and points at a different URL:
    existing: $EXISTING_URL
    wanted  : $REPO_URL
  Re-run with --force-remote to repoint it, or fix it yourself with:
    git remote set-url origin $REPO_URL"
  fi
else
  info "git remote add origin $REPO_URL"
  git remote add origin "$REPO_URL"
fi

# --- 6. git push -u origin main -------------------------------------------
info "git push -u origin $BRANCH"
if ! git push -u origin "$BRANCH"; then
  cat >&2 <<EOF

error: push failed. Common causes:
  * The repository does not exist yet: create an EMPTY repo named
    'llvm-strength-reduction' under the target account on github.com first
    (no README / .gitignore / licence, or the histories will diverge).
  * Authentication: use 'gh auth login', a credential helper, or a personal
    access token as the HTTPS password.
  * The remote already has commits (non-fast-forward). Inspect them with
    'git fetch origin && git log origin/$BRANCH'; do not force-push unless
    you are sure you want to overwrite them.
EOF
  exit 1
fi

info "Done: pushed to $REPO_URL ($BRANCH)"

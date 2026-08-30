#!/usr/bin/env sh
# kairos-lib.sh — primitives shared by kairos-diff.sh and kairos-gate-receipt.sh.
#
# These two scripts MUST agree, byte for byte, on two things: the digest of a tree's
# pending change set, and where that tree's state lives. If they drift, a scope token
# minted by one is unfindable by the other, and every receipt write fails closed for a
# reason no one can see. That is why this file exists rather than two copies.
#
# Sourced, never executed. POSIX sh, no bashisms.

# ---------------------------------------------------------------- primitives

_die() { printf 'kairos: %s\n' "$1" >&2; exit 64; }

_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v shasum   >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  else _die "no sha256sum or shasum on PATH"; fi
}

_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# JSON string escape, for values we build by hand.
_esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
    | awk 'BEGIN{ORS=""} NR>1{print "\\n"} {print}'
}

# Repo top-level of a directory, or empty.
_toplevel() { git -C "$1" rev-parse --show-toplevel 2>/dev/null; }

# Is this a Kairos workspace? A root spec.md carrying the root-spec signature.
_is_kairos_tree() {
  [ -f "$1/spec.md" ] || return 1
  grep -q '^- \*\*project_name\*\*:' "$1/spec.md" 2>/dev/null
}

# Where this tree's receipts, tokens and log live. Keyed by absolute path, named for
# readability. State lives OUTSIDE the repository: `close-story` commits with `git add -A`,
# so in-tree state would be committed — and an untracked receipt would enter the very
# digest it certifies, making the digest depend on itself.
_state_dir() {
  _sd_tree="$1"
  _sd_root="${KAIROS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/kairos}"
  _sd_key=$(printf '%s' "$_sd_tree" | _sha256 | cut -c1-12)
  printf '%s/%s-%s' "$_sd_root" "$(basename "$_sd_tree")" "$_sd_key"
}

# ---------------------------------------------------------------- the digest
#
# A content digest of everything that differs from HEAD, including untracked files.
#
# It must be INVARIANT UNDER `git add`: the gates run before staging, the verifier runs
# after it. So it is computed over the union of (differs-from-HEAD) and (untracked),
# which `git add` moves between but never changes. --no-renames keeps it independent of
# rename-detection thresholds. Gitignored files are excluded, so build output and this
# script's own state cannot perturb it.

_changed_paths() {
  {
    git -C "$1" diff HEAD --name-only --no-renames 2>/dev/null
    git -C "$1" ls-files --others --exclude-standard 2>/dev/null
  } | LC_ALL=C sort -u | grep -v '^$'
}

_digest() {
  _dg_tree="$1"
  _dg_tmp=$(mktemp -d) || _die "mktemp failed"

  _changed_paths "$_dg_tree" > "$_dg_tmp/paths"

  : > "$_dg_tmp/exist"; : > "$_dg_tmp/gone"
  while IFS= read -r p; do
    if [ -f "$_dg_tree/$p" ]; then printf '%s\n' "$p" >> "$_dg_tmp/exist"
    else printf '%s\n' "$p" >> "$_dg_tmp/gone"; fi
  done < "$_dg_tmp/paths"

  {
    if [ -s "$_dg_tmp/exist" ]; then
      git -C "$_dg_tree" hash-object --stdin-paths < "$_dg_tmp/exist" > "$_dg_tmp/shas" 2>/dev/null
      paste -d' ' "$_dg_tmp/shas" "$_dg_tmp/exist"
    fi
    [ -s "$_dg_tmp/gone" ] && sed 's/^/deleted /' "$_dg_tmp/gone"
  } | LC_ALL=C sort | _sha256

  rm -rf "$_dg_tmp"
}

# ---------------------------------------------------------------- scope tokens
#
# The token is what turns a receipt from an assertion into evidence. `kairos-diff.sh`
# mints one when it produces a scope, prints it at the head of the injected diff, and
# records it here. `--write` refuses a `passed` receipt whose token it cannot find.
#
# Honest about what this is: a gate that never held a Kairos artefact cannot produce a
# receipt. A model determined to lie could still copy the nonce out of the diff without
# reading it. This kills the measured failure — the accident — not a deliberate forgery.

_pending_dir() { printf '%s/pending' "$(_state_dir "$1")"; }

_nonce() {
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    od -An -tx1 -N16 /dev/urandom 2>/dev/null | tr -d ' \n'
  else
    printf '%s-%s-%s' "$(_now)" "$$" "${RANDOM:-0}" | _sha256 | cut -c1-32
  fi
}

# Record a freshly minted nonce for <tree> against <digest>.
_token_add() {
  _ta_dir=$(_pending_dir "$1")
  mkdir -p "$_ta_dir" 2>/dev/null || return 1
  printf '%s\n' "$3" >> "$_ta_dir/$2.tokens" 2>/dev/null || return 1
  # Tokens are worthless once the content moves under them; a digest that has not been
  # touched in a week is not coming back. Bounded, and never fatal.
  find "$_ta_dir" -maxdepth 1 -name '*.tokens' -mtime +7 -exec rm -f {} \; 2>/dev/null || true
  return 0
}

# Does <nonce> exist for <tree> at <digest>? Exact whole-line match.
_token_has() {
  _th_f="$(_pending_dir "$1")/$2.tokens"
  [ -f "$_th_f" ] || return 1
  grep -qxF "$3" "$_th_f" 2>/dev/null
}

#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Install rdel (zsh only)

Usage:
  ./install.sh [options]

Options:
  --shell zsh          Override shell type for rc-file selection.
  --rc-file FILE       Explicit rc file to edit.
  --prefix DIR         Install directory (default: $XDG_DATA_HOME/rdel or ~/.local/share/rdel).
  --skip-rc            Do not edit shell rc files.
  --force              Reinstall even if destination file exists.
  -h, --help           Show this help.
USAGE
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/rdel.zsh"

if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "error: rdel.zsh not found next to install.sh" >&2
  exit 1
fi

PREFIX="${XDG_DATA_HOME:-$HOME/.local/share}/rdel"
SHELL_KIND="${SHELL##*/}"
RC_FILE=""
SKIP_RC=0
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell)
      [[ $# -ge 2 ]] || { echo "error: --shell requires a value" >&2; exit 1; }
      SHELL_KIND="$2"
      shift 2
      ;;
    --rc-file)
      [[ $# -ge 2 ]] || { echo "error: --rc-file requires a value" >&2; exit 1; }
      RC_FILE="$2"
      shift 2
      ;;
    --prefix)
      [[ $# -ge 2 ]] || { echo "error: --prefix requires a value" >&2; exit 1; }
      PREFIX="$2"
      shift 2
      ;;
    --skip-rc)
      SKIP_RC=1
      shift
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$RC_FILE" && "$SKIP_RC" -eq 0 ]]; then
  case "$SHELL_KIND" in
    zsh)
      RC_FILE="$HOME/.zshrc"
      ;;
    *)
      echo "error: rdel is zsh-only; use --shell zsh" >&2
      exit 1
      ;;
  esac
fi

mkdir -p "$PREFIX"
TARGET_FILE="$PREFIX/rdel.zsh"
LEGACY_ZSH_FUNC="$HOME/.zsh/functions/rdel.zsh"

if [[ -f "$TARGET_FILE" && "$FORCE" -ne 1 ]]; then
  echo "info: $TARGET_FILE already exists (use --force to overwrite)"
else
  cp "$SOURCE_FILE" "$TARGET_FILE"
  chmod 0644 "$TARGET_FILE"
  echo "installed: $TARGET_FILE"
fi

# If a legacy autoloaded function exists at ~/.zsh/functions/rdel.zsh, keep it in sync.
if [[ -f "$LEGACY_ZSH_FUNC" ]]; then
  cp "$SOURCE_FILE" "$LEGACY_ZSH_FUNC"
  chmod 0644 "$LEGACY_ZSH_FUNC"
  echo "updated legacy zsh function: $LEGACY_ZSH_FUNC"
fi

SOURCE_LINE="[ -f \"$TARGET_FILE\" ] && source \"$TARGET_FILE\"; unalias rdel 2>/dev/null || true"

if [[ "$SKIP_RC" -eq 0 ]]; then
  mkdir -p "$(dirname -- "$RC_FILE")"
  touch "$RC_FILE"

  # Warn if an alias still exists in the rc file after the source line we are about to add.
  if grep -qE '^[^#]*alias[[:space:]]+rdel' "$RC_FILE" 2>/dev/null; then
    echo "warning: $RC_FILE still contains an 'alias rdel' line." >&2
    echo "         Remove or move it after the rdel source line so the function takes effect." >&2
  fi

  if grep -Fqx "$SOURCE_LINE" "$RC_FILE"; then
    echo "info: rc file already configured: $RC_FILE"
  else
    {
      echo ""
      echo "# rdel"
      echo "$SOURCE_LINE"
    } >> "$RC_FILE"
    echo "updated rc file: $RC_FILE"
  fi

  echo "next: run 'source $RC_FILE' or open a new shell"
else
  echo "rc update skipped"
  echo "manual load: source \"$TARGET_FILE\"; unalias rdel 2>/dev/null || true"
fi

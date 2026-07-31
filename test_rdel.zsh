#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
source "$SCRIPT_DIR/rdel.zsh"

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

export RDEL_TRASH="$tmp_dir/trash"
export RDEL_RETENTION_DAYS=7

mkdir -p "$tmp_dir/work"
cd "$tmp_dir/work"

# Test 1: delete a file and verify it moved to trash.
echo "hello" > file1
rdel file1
[[ ! -e file1 ]] || fail "file1 still exists after rdel"
entry_count=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | command wc -l | command tr -d ' ')
[[ "$entry_count" -eq 1 ]] || fail "expected 1 trash entry, got $entry_count"

# Test 2: list contains the deleted file.
output=$(rdel --list)
command grep -q "file1" <<< "$output" || fail "--list does not show file1"

# Test 3: restore the deleted file.
entry=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d -print -quit)
id=$(command basename -- "$entry")
rdel --restore "$id"
[[ -f file1 ]] || fail "file1 not restored"
entry_count=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | command wc -l | command tr -d ' ')
[[ "$entry_count" -eq 0 ]] || fail "trash not empty after restore"

# Test 4: delete multiple files and empty the trash.
echo a > a
echo b > b
rdel a b
entry_count=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | command wc -l | command tr -d ' ')
[[ "$entry_count" -eq 2 ]] || fail "expected 2 trash entries, got $entry_count"
rdel --empty -f
entry_count=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | command wc -l | command tr -d ' ')
[[ "$entry_count" -eq 0 ]] || fail "trash not empty after --empty -f"

# Test 5: directories can be deleted and restored.
mkdir -p mydir
echo hello > mydir/inner.txt
rdel mydir
entry=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d -print -quit)
id=$(command basename -- "$entry")
rdel --restore "$id"
[[ -f mydir/inner.txt ]] || fail "directory not restored correctly"
rdel --empty -f

# Test 6: garbage collection removes expired entries.
echo c > c
rdel c
entry=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d -print -quit)
{
  print -- "id: expired"
  print -- "original: $tmp_dir/work/c"
  print -- "basename: c"
  print -- "deleted_at: 1"
  print -- "expires_at: 1"
} > "$entry/meta"
echo d > d
rdel d
if [[ -d "$entry" ]]; then
  fail "expired entry was not garbage collected"
fi
entry_count=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | command wc -l | command tr -d ' ')
[[ "$entry_count" -eq 1 ]] || fail "expected 1 non-expired entry after GC, got $entry_count"
rdel --empty -f

# Test 7: force suppresses missing-file errors.
rdel -f missing_file || fail "rdel -f should not fail on missing files"

# Test 8: verbose output mentions moved files.
echo e > e
output=$(rdel -v e)
command grep -q "moved" <<< "$output" || fail "verbose output missing 'moved'"
rdel --empty -f

# Test 9: retention days flag controls expiration.
echo f > f
rdel -d 1 f
entry=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d -print -quit)
expires=$(command sed -n 's/^expires_at: //p' "$entry/meta")
deleted=$(command sed -n 's/^deleted_at: //p' "$entry/meta")
if [[ -z "$expires" || -z "$deleted" ]]; then
  fail "missing metadata in retention test"
fi
if [[ "$(( expires - deleted ))" -ne 86400 ]]; then
  fail "retention -d 1 should be 86400 seconds, got $(( expires - deleted ))"
fi
rdel --empty -f

# Test 10: combined rm-style flags work.
echo g > g
rdel -rfv g
entry_count=$(command find "$RDEL_TRASH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | command wc -l | command tr -d ' ')
[[ "$entry_count" -eq 1 ]] || fail "combined flags did not move g to trash"
rdel --empty -f

print -- "All rdel tests passed."

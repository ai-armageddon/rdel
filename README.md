# rdel

`rdel` is a delayed-delete command for zsh. It moves files into a hidden trash
bin and permanently deletes them after a configurable retention window, so a
mistaken `rdel` is recoverable.

## What It Does

```zsh
rdel some-file.txt big-directory/
```

Instead of permanently deleting, `rdel` moves the targets into
`~/.local/share/rdel/.trash` (or `$RDEL_TRASH`). Each run also garbage-collects
items whose retention has expired.

## Features

- Safer alternative to `rm -rf` — files can be restored until they expire.
- Automatic garbage collection of expired items on every invocation.
- List, restore, and empty commands.
- `rm`-style `-f` and `-v` flags.
- `-d <days>` / `--days <days>` for per-command retention.
- Configurable default retention and trash location via environment variables.

## Requirements

- `zsh`
- Standard POSIX utilities (`mv`, `rm`, `cp`, `find`, `sed`, `mkdir`, `date`, `printf`)

## Install

From the repo root:

```bash
./install.sh
```

Then reload your shell:

```bash
source ~/.zshrc
```

### Installer options

```bash
./install.sh --shell zsh
./install.sh --rc-file /path/to/rcfile
./install.sh --prefix /custom/install/dir
./install.sh --skip-rc
./install.sh --force
```

If you already have `alias rdel='...'` in your `~/.zshrc`, remove or move it
after the `rdel` source line so the function takes effect.

## Usage

### Delete (move to trash)

```zsh
rdel file.txt directory/
rdel -v file.txt
rdel -f missing-file.txt      # no error on missing files
rdel -d 7 file.txt            # keep for 7 days
```

### List trashed items

```zsh
rdel --list
```

### Restore a trashed item

Find the ID from `rdel --list`, then:

```zsh
rdel --restore 20260718-123045-a1b2c3d4
```

By default it restores to the original absolute path. Use `-f` to overwrite an
existing file:

```zsh
rdel -f --restore 20260718-123045-a1b2c3d4
```

### Empty trash immediately

```zsh
rdel --empty
```

Use `-f` to skip the confirmation prompt.

## Configuration

| Variable              | Default                            | Description                     |
| --------------------- | ---------------------------------- | ------------------------------- |
| `RDEL_TRASH`          | `~/.local/share/rdel/.trash`       | Hidden trash directory          |
| `RDEL_RETENTION_DAYS` | `30`                               | Default retention in days       |

## Tests

Run:

```bash
zsh ./test_rdel.zsh
```

Expected:

```text
All rdel tests passed.
```

## Uninstall

1. Remove the source line from your `~/.zshrc`.
2. Delete the installed file (default):

```bash
rm -f "$HOME/.local/share/rdel/rdel.zsh"
rm -rf "$HOME/.local/share/rdel/.trash"
```

## Troubleshooting

If `rdel` still behaves like `rm`, check where it is loading from:

```zsh
whence -v rdel
```

If it shows `~/.zsh/functions/rdel.zsh`, that legacy autoload path is taking
precedence. Re-run the installer with `--force`; it updates that file too.

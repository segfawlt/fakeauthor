# fakeauthor

fakeauthor adds fake AI co-author trailers to your git commits. It exists for
the joke of crediting AI assistants on commits written entirely by a human, on
machines where those tools are never used. This is a parody project. It is not
affiliated with, endorsed by, or connected to any vendor named below.

## Install

Run the installer with no arguments to pick your scope (global or this repo) and
toggle one or more co-authors (`arrows`/`j`/`k` to move, `Space` to toggle, `a`
for all, `Enter` to save, `q`/`Esc` to cancel; falls back to numbered lines
without a TTY):

```sh
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/refs/tags/v1/install.sh | sh
```

Or pass personas directly for non-interactive setups:

```sh
# Single persona, multiple co-authors, or all 5 co-author presets
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/refs/tags/v1/install.sh | sh -s -- claude
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/refs/tags/v1/install.sh | sh -s -- claude,copilot,codex
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/refs/tags/v1/install.sh | sh -s -- all
```

To install only for the current repository without touching global git config,
choose `2` in the interactive wizard or pass `--local`:

```sh
cd /path/to/repo
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/refs/tags/v1/install.sh | sh -s -- --local claude
```

## How it works

- **Global install:** writes a `commit-msg` hook and 13 chaining stubs to
  `~/.local/share/fakeauthor/hooks/`, saves an offline control script at
  `~/.local/share/fakeauthor/fakeauthor.sh`, records exact state in
  `~/.local/share/fakeauthor/manifest`, sets global `core.hooksPath`, and
  registers a `git fakeauthor` alias.
- **Local install (`--local`):** writes `.git/hooks/commit-msg`,
  `.git/fakeauthor.sh`, `.git/fakeauthor-manifest`, and a repo-local
  `git fakeauthor` alias inside `.git/config`. Requires no global or local
  `core.hooksPath` to be set.
- **Zero clobber:** refuses to overwrite an existing `core.hooksPath`, a
  hand-edited hook (unless `--force` is passed), or a pre-existing custom git
  alias.

## Managing with `git fakeauthor`

Once installed, `git fakeauthor` works 100% offline in both global and
`--local` repositories:

```sh
git fakeauthor            # re-open the [x]/[ ] co-author toggle menu
git fakeauthor off        # pause in this repo (or globally if outside a repo)
git fakeauthor on         # resume in this repo (or globally if outside a repo)
git fakeauthor status     # print active state, persona(s), rate, and aliases
git fakeauthor uninstall  # exact manifest-verified removal
```

When installed globally and run inside a repository, bare `git fakeauthor`
prompts whether to apply changes only to that repository or globally.

## Presets

| **persona** | **trailer key** | **identity** |
|---|---|---|
| claude | Co-Authored-By | `Claude <noreply@anthropic.com>` |
| copilot | Co-authored-by | `Copilot <223556219+Copilot@users.noreply.github.com>` |
| codex | Co-authored-by | `Codex <noreply@openai.com>` |
| cursor | Co-authored-by | `Cursor <cursoragent@cursor.com>` |
| aider | Co-authored-by | `aider (sonnet) <aider@aider.chat>` |
| devin | author mode | `Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>` |

- Selecting `all` enables all five co-author presets (`claude,copilot,codex,cursor,aider`).
- `sh install.sh show <persona>` prints the exact trailer line (or the
  author-mode note for `devin`).

## Author mode

Every selected persona also gets a `git <persona>` alias that commits with that
persona as the commit `Author` (preserving your current subdirectory and
setting `NO_FAKEAUTHOR=1` so the hook skips duplicate co-author trailers). For
`devin`, author mode is the only attribution mode:

```sh
git devin commit -m "ship it"
git claude commit -m "fix tests"
```

## Runtime controls

Everything is configurable via git config without reinstalling:

| **key** | **effect** |
|---|---|
| `fakeauthor.persona` | persona or comma list (`claude`, `claude,codex`, `all`) |
| `fakeauthor.rate` | fraction of commits that receive trailers (`0` to `1`, default `1`) |
| `fakeauthor.name` | override display name |
| `fakeauthor.email` | override email address |
| `fakeauthor.off` | `true` disables trailers for this scope while still chaining repo hooks |
| `NO_FAKEAUTHOR=1` | environment variable; skips trailer insertion for one command |

```sh
git config fakeauthor.persona claude,codex
git config --global fakeauthor.rate 0.25
NO_FAKEAUTHOR=1 git commit -m "no trailer this time"
```

The hook skips merge commits, squash commits, and empty or comment-only
messages, while preserving existing human `Co-authored-by:` trailers and
`Signed-off-by:` blocks.

## Windows Git Bash

Run the installer in Git Bash (bundled with Git for Windows). `.gitattributes`
pins `*.sh text eol=lf`, and the installer checks every written file for CR
bytes and aborts before mutating config if any are found.

## Known limits

- GUI git clients that skip hooks do not run `commit-msg`.
- `git commit --no-verify` bypasses `commit-msg`.
- Interactive `git rebase` (`reword` or `edit`) runs `commit-msg`, which may add
  trailers to rewritten commits.
- CI runners commit under their own `HOME` and git config, so a global install
  on your machine does not affect them.
- Python `pre-commit install` refuses to run while global `core.hooksPath` is
  set. Use `--local` in those repositories instead, then run `pre-commit install`.

## Disclaimer and trademarks

Claude, Copilot, Codex, Cursor, aider, and Devin are trademarks of their
respective owners. fakeauthor is a parody and is not affiliated with, endorsed
by, or connected to any of these vendors. The repository name contains none of
their marks. Nothing is sent anywhere.

## License

MIT. See `LICENSE`.

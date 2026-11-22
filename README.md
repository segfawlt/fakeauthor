# fakeai

fakeai adds a fake AI co-author trailer to your git commits. It exists for the
joke of crediting an AI assistant on commits written entirely by a human, on
machines where that assistant is never used. This is a parody project. It is
not affiliated with, endorsed by, or connected to any vendor named below.

## What it does

One command installs a `commit-msg` hook through a global `core.hooksPath`,
plus thirteen small chain stubs for the other standard hooks. The hook appends
a `Co-Authored-By` trailer to commit messages. The stubs forward every other
hook event to your own scripts, so an existing hook setup keeps working. A
copy of the offline control script is written to `~/.config/fakeai/fakeai.sh`,
and a manifest records everything the installer wrote so uninstall changes
nothing it does not own.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/refs/tags/v1/install.sh | sh -s -- claude
sh ~/.config/fakeai/fakeai.sh status
sh ~/.config/fakeai/fakeai.sh off
```

The first line installs the `claude` persona globally. The second prints the
install state. The third removes everything the installer wrote and leaves
hand-edited files in place with a warning.

To install for a single repository instead, run the installer with `--local`
inside that repository. It writes the hook and a `fakeai-manifest` into the
repository's `.git` directory and uses repo-local git config. A local install
requires that no `core.hooksPath` is set, globally or locally, because git
would otherwise bypass the repository hooks.

## Presets

`sh install.sh <persona>` accepts these personas, globally or with `--local`.
The trailer key matches how each vendor's own bot signs commits.

| **persona** | **trailer key** | **identity** |
|---|---|---|
| claude | Co-Authored-By | `Claude <noreply@anthropic.com>` |
| copilot | Co-authored-by | `Copilot <223556219+Copilot@users.noreply.github.com>` |
| codex | Co-authored-by | `Codex <noreply@openai.com>` |
| cursor | Co-authored-by | `Cursor <cursoragent@cursor.com>` |
| aider | Co-authored-by | `aider (sonnet) <aider@aider.chat>` |
| devin | author mode | `Devin <158243242+devin-ai-integration[bot]@users.noreply.github.com>` |

`sh install.sh show <persona>` prints the trailer line a persona produces.
For devin it prints the author-mode note instead, because Devin signs real
commits as the author and has no trailer.

## Author mode

Every persona also gets a git alias of the same name. `git <persona> commit`
runs git with that persona as the commit author, preserving your current
directory, without adding a trailer. For devin this alias is the whole point,
since author mode is the only way Devin appears on a commit.

```sh
git devin commit -m "ship it"
```

## Runtime controls

| **key** | **effect** |
|---|---|
| `fakeai.persona` | persona used for the trailer; default `claude` |
| `fakeai.rate` | fraction of commits that get a trailer, from 0 to 1; default 1 |
| `fakeai.name` | override the trailer name |
| `fakeai.email` | override the trailer email |
| `fakeai.off` | set to true to disable the hook for the current scope |
| `NO_FAKEAI=1` | environment variable; skips the hook for one command |

Set them globally with `git config --global`, or per repository with plain
`git config` inside the repository.

```sh
git config fakeai.persona codex
git config --global fakeai.rate 0.5
NO_FAKEAI=1 git commit -m "no trailer this time"
```

The hook stays quiet on merge and squash commits and skips empty or
comment-only messages.

## Offline status and off

```sh
sh ~/.config/fakeai/fakeai.sh status
sh ~/.config/fakeai/fakeai.sh off
```

Both also work with `--local` from inside a repository, as
`sh install.sh --local status`. `off` uninstalls through the manifest and
leaves any file you modified untouched.

## Windows Git Bash

Hook scripts with CRLF line endings fail to run. `.gitattributes` pins
`*.sh text eol=lf`, so a checkout keeps LF endings, and the installer checks
every file it writes for CR bytes and aborts if it finds any.

## Known limits

- Many GUI git clients skip hooks entirely, with or without fakeai.
- `git commit --no-verify` bypasses `commit-msg`, so no trailer is added.
- Interactive `git rebase` (`reword` or `edit`) runs `commit-msg`, which may
  add the trailer to rewritten commits.
- CI runners commit under their own HOME and config, so a global install on
  your machine does not affect them.
- The Python `pre-commit` tool refuses to install its hooks while a global
  `core.hooksPath` is configured. Use fakeai `--local` in those repositories
  instead, then run `pre-commit install`.

## Disclaimer and trademarks

Claude, Copilot, Codex, Cursor, aider, and Devin are trademarks of their
respective owners. fakeai is a parody and is not affiliated with, endorsed by,
or connected to any of these vendors. The repository name contains none of
their marks. The trailer identities imitate the format those vendors' bots
use so the joke reads correctly. Nothing is sent anywhere.

## License

MIT. See `LICENSE`.

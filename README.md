# fakeauthor

Credit AI coding assistants on commits written entirely by a human, on
machines where those tools are never used. Parody project — not affiliated
with, endorsed by, or connected to Anthropic, GitHub, OpenAI, Cursor, aider,
or Cognition.

## Install (Linux)

```sh
# Interactive picker (arrows/j/k move, Space toggle, a all, Enter save, q/Esc cancel)
curl -fsSL https://raw.githubusercontent.com/segfawlt/fakeauthor/refs/heads/main/install.sh | sh

# Non-interactive (single, multi, all co-authors, or this repo only)
curl -fsSL https://raw.githubusercontent.com/segfawlt/fakeauthor/refs/heads/main/install.sh | sh -s -- claude
curl -fsSL https://raw.githubusercontent.com/segfawlt/fakeauthor/refs/heads/main/install.sh | sh -s -- all
curl -fsSL https://raw.githubusercontent.com/segfawlt/fakeauthor/refs/heads/main/install.sh | sh -s -- --local claude
```

Global installs live in `~/.local/share/fakeauthor/` and chain existing repo
hooks without clobbering them. `--local` installs inside `.git/` only.

## Commands

```sh
git fakeauthor            # open the interactive toggle menu
git fakeauthor off        # pause in this repo (or globally outside a repo)
git fakeauthor on         # resume in this repo (or globally outside a repo)
git fakeauthor status     # show active state, personas, rate, and aliases
git fakeauthor uninstall  # exact manifest-verified removal
git devin commit -m "hi"  # author mode (also works as git claude, git codex, ...)
```

## Presets & Config

Presets: `claude`, `copilot`, `codex`, `cursor`, `aider`, `devin` (author mode
only). Tune anytime via `git config` without reinstalling:

```sh
git config fakeauthor.persona claude,codex
git config --global fakeauthor.rate 0.25   # chaos mode (25% of commits)
NO_FAKEAUTHOR=1 git commit -m "honest"     # skip one commit
```

## Known Limits

- Python `pre-commit install` refuses global `core.hooksPath` — use `--local` in
  those repos.
- GUI git clients that skip hooks and `git commit --no-verify` bypass `commit-msg`.
- Interactive `git rebase` (`reword`/`edit`) runs `commit-msg` on rewritten commits.

## License

GPL-3.0. See `LICENSE`.

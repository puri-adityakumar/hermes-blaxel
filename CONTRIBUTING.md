# Contributing

Thanks for your interest. This is a small community project; issues and PRs are welcome.

## Local setup

1. Install the Blaxel CLI and log in (see the README Quickstart).
2. Run the wizard, or copy `.env.example` to `.env` and fill it in.
3. **Test in isolation:** use a separate sandbox name (e.g. `hermes-test`) and a separate Telegram bot, so
   you do not disturb a live deployment. A bot token can hold only one webhook.

## Before opening a PR

- Syntax-check before pushing: `bash -n scripts/*.sh` (and `shellcheck scripts/*.sh` if you have it).
- Update the README / CLAUDE.md if you change behavior.

## Repo rules

- **Do not** add Claude or any AI as a commit author or `Co-Authored-By:` trailer. Commits are human-authored.
- **Never** commit real secrets or personal identifiers (API keys, tokens, your Telegram id, the Blaxel
  workspace name, live preview URLs, emails). Use placeholders in docs and examples.
- **No em-dashes or en-dashes** anywhere; use a plain hyphen.
- `.sh` files must stay LF (enforced by `.gitattributes`).

See [CLAUDE.md](CLAUDE.md) for the architecture and the hard-won lessons behind how things are built.

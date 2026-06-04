# Security Policy

## Handling secrets

This project uses several secrets: your model-provider API key, a Telegram bot token, and (optionally) a
web-dashboard password. They live only in a local `.env` file, which is **gitignored**. Never commit real
secrets.

- `.env.example` is the template (placeholders only). Copy it to `.env`, or let the wizard create it.
- The setup wizard generates the random secrets (webhook secret, dashboard session/auth secrets) for you.
- The web dashboard, once you log in, can reveal provider keys. Use a strong dashboard password and treat
  the dashboard URL as sensitive.
- The Telegram bot only responds to the user id(s) in `TELEGRAM_ALLOWED_USERS`.

## If a secret leaks

Rotate it immediately, then redeploy so the sandbox picks up the new values:

- **Provider API key:** revoke / regenerate it in the provider console.
- **Telegram bot token:** `/revoke` then `/token` in @BotFather (or delete the bot).
- **Dashboard password / secrets:** re-run the wizard (or edit `.env`), then redeploy.

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue:

- Use GitHub's **"Report a vulnerability"** (the repo's Security tab > Advisories), or
- If private advisories are not available, open a minimal issue that only asks the maintainer to enable
  private reporting (do not include details).

This is a community project with no SLA, but reports are appreciated and handled on a best-effort basis.

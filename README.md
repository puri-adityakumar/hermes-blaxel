# Hermes-on-Blaxel

Run your own [Hermes Agent](https://github.com/NousResearch/hermes-agent) as a **Telegram bot** (plus an
optional **web dashboard**) on a [Blaxel](https://blaxel.ai) cloud sandbox. Use **any model provider**
Hermes supports (Z.AI/GLM, Anthropic, OpenAI, Gemini, Kimi, …). Choose **always-on** (instant) or
**scale-to-zero** (sleeps when idle, wakes on a message - ~nothing at rest).

## Quickstart

**1 - Install the Blaxel CLI and log in**

```powershell
# Windows (PowerShell)
irm https://raw.githubusercontent.com/blaxel-ai/toolkit/main/install.ps1 | iex
bl login
```
```bash
# macOS / Linux
curl -fsSL https://raw.githubusercontent.com/blaxel-ai/toolkit/main/install.sh | sh
bl login
```

**2 - Clone the repo and run the wizard**

```powershell
# Windows
./scripts/setup.ps1
```
```bash
# macOS / Linux  (needs bash, curl, openssl - preinstalled on macOS/Linux)
chmod +x scripts/*.sh
./scripts/setup.sh
```

The wizard walks you through: **model provider + API key** (pick from a menu, or "configure later in
Hermes"), your **Telegram bot token** (@BotFather) and **user id** (@userinfobot), the **web dashboard**,
and the **run mode**. It generates all other secrets, deploys, wires up the webhook, and prints your bot
handle + dashboard link. That's it.

> **Bring-your-own provider:** pick "configure later" and set the provider/model/keys after deploy via the
> **dashboard** or `bl connect sandbox <name> → hermes setup model` - Hermes' own multi-provider wizard.

## Day-to-day

| Task | Windows (PowerShell) | macOS / Linux (bash) |
|---|---|---|
| Redeploy after a code change | `./scripts/deploy.ps1` | `./scripts/deploy.sh` |
| Change config/secrets only (faster) | `./scripts/deploy.ps1 -SkipBuild` | `./scripts/deploy.sh --skip-build` |
| Back up chat history/memories | `./scripts/backup-data.ps1` | `./scripts/backup-data.sh` |
| Restore after a rebuild | `./scripts/restore-data.ps1 -InFile backups\<file>.tar.gz` | `./scripts/restore-data.sh backups/<file>.tar.gz` |

⚠️ A full rebuild resets the box's runtime data (free tier has no persistent disk) - back up first if you
care about it. See **CLAUDE.md** for architecture, the Blaxel CLI cheat-sheet, and hard-won lessons.

## Requirements
- A Blaxel account (free tier works) · an API key for any provider Hermes supports · a Telegram bot token.
- Windows/PowerShell for the scripts (the sandbox itself is Linux in the cloud).

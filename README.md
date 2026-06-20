# Hermes on Blaxel

[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
![status: beta](https://img.shields.io/badge/status-beta-orange.svg)
![setup: Windows | macOS | Linux](https://img.shields.io/badge/setup-Windows%20%7C%20macOS%20%7C%20Linux-blue.svg)

```
    _   _ _____ ____  __  __ _____ ____      ____  _        _    __  __ _____ _
   | | | | ____|  _ \  \/  | ____/ ___|     | __ )| |      / \  \ \/ /| ____| |
   | |_| |  _| | |_) | |\/| |  _| \___ \  x |  _ \| |     / _ \  \  / |  _| | |
   |  _  | |___|  _ <| |  | | |___ ___) |   | |_) | |___ / ___ \ /  \ | |___| |___
   |_| |_|_____|_| \_\_|  |_|_____|____/    |____/|_____/_/   \_\_/\_\|_____|_____|

   +====================================================+
   |  self-hosted autonomous agent on a managed sandbox |
   +====================================================+
```

Run your own [Hermes Agent](https://github.com/NousResearch/hermes-agent) on a [Blaxel](https://blaxel.ai) managed sandbox - reachable from **Telegram** or **Discord**, with an optional **web dashboard**. Clone, run one wizard, get a live agent. Bring **any model provider**; pick **always-on** or **scale-to-zero**.

## Quickstart

**1. Install the Blaxel CLI and log in**

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

**2. Run the wizard**

```bash
chmod +x scripts/*.sh   # Windows: run in Git Bash or WSL
./scripts/setup.sh
```

The wizard asks for: **model provider + key** (or "configure later"), **messaging platform** (Telegram / Discord / later), optional **dashboard**, and **run mode**. It deploys and prints your bot + dashboard link.

## Deployment modes

| Mode | Behavior | Cost |
|---|---|---|
| **always-on** | Runs 24/7, instant replies | continuous |
| **scale-to-zero** | Sleeps ~15 min idle, wakes on a message (~1 min cold start) | ~zero when idle |

## Day-to-day

| Task | Command |
|---|---|
| Redeploy after a code change | `./scripts/deploy.sh` |
| Config/secrets only (faster) | `./scripts/deploy.sh --skip-build` |
| Back up history/memories | `./scripts/backup-data.sh` |
| Restore after a rebuild | `./scripts/restore-data.sh backups/<file>.tar.gz` |

> A full rebuild wipes runtime data (free tier has no persistent disk) - back up first. See **CLAUDE.md** for architecture and the CLI cheat-sheet.

## Requirements

- A Blaxel account (free tier works) · an API key for any provider Hermes supports · a Telegram or Discord bot token.
- macOS/Linux, or Windows via Git Bash / WSL (needs bash + curl + openssl).

## Contributing

Issues and PRs welcome - see [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). Built on [Hermes Agent](https://github.com/NousResearch/hermes-agent) by **Nous Research** and the [Blaxel](https://blaxel.ai) platform.

## Disclaimer

Unofficial community project, **not affiliated with Nous Research or Blaxel**. Provided as-is under [MIT](LICENSE). You're responsible for your own API keys, costs, and what your bot says or does.

FROM node:22-slim

# glibc base with Node 22. Hermes is baked into the IMAGE (not the runtime overlay)
# so it survives sandbox stop/resume and the entrypoint can auto-start it on every boot.
ENV DEBIAN_FRONTEND=noninteractive UV_NO_CACHE=1 HERMES_HOME=/root/.hermes
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl ca-certificates ripgrep python3 python3-venv netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# uv (Python package manager / installer)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.local/bin:/usr/local/bin:$PATH"

# Lean Hermes install: core + anthropic (z.ai uses an OpenAI/Anthropic-compatible API)
# + Telegram with webhook support + web (fastapi/uvicorn/starlette for the dashboard).
# Shallow clone, no .git, no browser/dev extras.
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent /usr/local/lib/hermes-agent \
 && cd /usr/local/lib/hermes-agent \
 && uv venv --python /usr/bin/python3.11 venv \
 && uv pip install --python venv/bin/python -e ".[anthropic,web]" \
 && uv pip install --python venv/bin/python "python-telegram-bot[webhooks]==22.6" \
 && printf '#!/bin/sh\nexec /usr/local/lib/hermes-agent/venv/bin/hermes "$@"\n' > /usr/local/bin/hermes \
 && chmod +x /usr/local/bin/hermes \
 && rm -rf /usr/local/lib/hermes-agent/.git /root/.cache

# Build the web dashboard UI into the image (outputs to hermes_cli/web_dist), so the
# dashboard can run with `--skip-build` at runtime. node_modules is dropped afterward
# to keep the image lean - only the built static dist is kept.
RUN cd /usr/local/lib/hermes-agent/web \
 && npm install \
 && npm run build \
 && rm -rf node_modules /root/.npm

# Non-secret model config baked in (secrets are injected at runtime via env/.env).
RUN mkdir -p /root/.hermes/logs \
 && printf 'model:\n  provider: zai\n  default: glm-5.1\n  base_url: https://api.z.ai/api/paas/v4\n' > /root/.hermes/config.yaml

# Blaxel sandbox API server (static Go binary) - powers `bl run` management on :8080.
COPY --from=ghcr.io/blaxel-ai/sandbox:latest /sandbox-api /usr/local/bin/sandbox-api

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

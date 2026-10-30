# codex-box-railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/codex-box-v0147-or-remote-dev-machine-pi?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Deploy on Railway:** [Codex Box template](https://railway.com/deploy/codex-box-v0147-or-remote-dev-machine-pi?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

Prebuilt, pinned remote development machine for the [OpenAI Codex CLI](https://developers.openai.com/codex),
packaged for Railway. Image: `ghcr.io/bon5co/codex-box-railway`.

Deploy the image as a single Railway service with a volume at `/data`, then reach it with
`railway ssh` or the Codex desktop app's SSH connection.

## What this image does differently

* **Prebuilt and pinned.** The Codex CLI is pinned to an exact version (`0.147.0`); the
  npm `latest` tag moves roughly weekly, so an unpinned box changes agent version on every
  redeploy. A deploy here is an image pull, not a full Ubuntu + Node + toolchain build.
* **Usable the moment it finishes deploying.** Set `OPENAI_API_KEY` and the entrypoint
  writes `$CODEX_HOME/auth.json` before the box is reachable. Exporting `OPENAI_API_KEY`
  alone is *not* enough for Codex 0.147.0 — it sends no bearer at all and retries five
  times before failing with `401 ... Missing bearer or basic authentication in header`.
  An existing interactive (`auth_mode: chatgpt`) login is never overwritten.
* **Refuses to start without the volume.** No volume means every login, repo and installed
  tool is erased on the next deploy, which is otherwise a silent failure.
* **Everything durable lives on the volume.** `$HOME` (and `/root`) resolve to
  `/data/home/user`: Codex auth and sessions, shell history, `npm -g` installs, SSH keys,
  and repositories under `/data/workspace`.
* Volume ownership is repaired on boot (Railway mounts volumes as uid 0).

## Variables

| Variable | Required | Purpose |
|---|---|---|
| `OPENAI_API_KEY` | no | Seeds Codex API-key auth on first boot. Omit to run `codex login` yourself over SSH. |

## Local test

```bash
docker build -t codex-box .
mkdir vol && sudo chown 0:0 vol          # reproduce Railway's root-owned mount
docker run -d --name box -e OPENAI_API_KEY=sk-... -v "$PWD/vol:/data" codex-box
docker exec -itu user box bash -l
```

Use a bind mount, not a Docker named volume: a named volume is seeded from the image layer
and will not reproduce how Railway mounts an empty, root-owned directory.

# AI Gateway (`aigw`)

OpenAI-compatible HTTP/HTTPS gateway. Routes `provider:model` through [AGL](../agl). llama-server stays on loopback (`127.0.0.1`, same port as `PORT` in `.env`).

When a client omits `model`, or sends `default` / `fav` / `*:default`, aigw passes an empty model to AGL, which reads `default_model` from `~/.config/agl/config.yaml` on every request (no process restart needed). There is no `xai:*` default. VS Code Custom Endpoint should use `"id": "default"`.

Bind address, allowlist, TLS names, and API key all live in `.env` (see `.env.example`). Nothing in the source tree assumes a particular LAN IP or hostname.

```
optional Mac splice  →  127.0.0.1:$PORT  (mac-aigw LaunchDaemon)  →  $HOST:$PORT aigw
other clients        →  https://$HOST:$PORT   (or a name listed in TLS_DNS_NAMES)
```

## Run

```sh
cp .env.example .env   # set LLM_PROXY_API_KEY, HOST, ALLOWED_CIDRS, TLS_* 
bun install
bun start
```

systemd `--user` (WorkingDirectory is this clone; no hardcoded path):

```sh
loginctl enable-linger "$USER"
bash scripts/install-systemd.sh
journalctl --user -u aigw -f
```

## Search UI (`/search/`)

aigw also reverse-proxies the [web-researcher](https://github.com/mikesmullin/web-researcher) UI on the same port,
nginx-style (prefix stripped): `https://$HOST:$PORT/search/` → `SEARCH_UPSTREAM` (default `http://127.0.0.1:2340`).

- `/search` redirects to `/search/`; SSE streams are passed through unbuffered, and a client disconnect aborts the upstream request.
- It is a browser UI, so the Bearer key is **not** required (and is never forwarded). Access is limited by `ALLOWED_CIDRS`
  checked against the real socket peer address (not `X-Forwarded-For`); others get 403.
- Upstream down → `502`. Change the prefix with `SEARCH_PATH`; disable with an empty `SEARCH_UPSTREAM=`.

## TLS

```sh
bash scripts/gen-certs.sh
# TLS_CERT=tmp/certs/server.pem TLS_KEY=tmp/certs/server.key in .env
```

Certs are written to `tmp/certs/` (gitignored). Install `tmp/certs/ca.pem` in the OS trust store on the gateway and every client.

```sh
# Linux
sudo trust anchor tmp/certs/ca.pem   # or copy into /etc/ca-certificates/trust-source/anchors && update-ca-trust

# macOS (login keychain; no sudo)
security add-trusted-cert -d -r trustRoot -k ~/Library/Keychains/login.keychain-db tmp/certs/ca.pem
```

- Clients that use the Mac splice: `https://127.0.0.1:$PORT/v1/chat/completions` (include `127.0.0.1` in `TLS_IP_ADDRS`). Do not hosts-file the gateway hostname to loopback.
- Clients that can reach the LAN: `https://$HOST:$PORT/v1/chat/completions` (or a name in `TLS_DNS_NAMES`).

See `examples/chatLanguageModels.json`.

Regenerating the CA (`rm -rf tmp/certs && bash scripts/gen-certs.sh`) requires reinstalling `ca.pem` on every client.

## Auth

`Authorization: Bearer $LLM_PROXY_API_KEY`. Provider keys stay on the gateway host (AGL `.env`).

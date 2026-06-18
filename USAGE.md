# wol-pi — Usage

`wol-pi` is a zero-dependency Python (CPython stdlib only) HTTP relay that
sends a Wake-on-LAN magic packet to a configured MAC address. It is normally
deployed on a Raspberry Pi reached over a Tailscale tailnet, but `wol_server.py`
runs anywhere Python 3.11+ is installed.

This document covers the runtime surface: how to start the server, how it is
configured, and the HTTP API. For the full hardware setup and Pi/Windows
provisioning, see [README.md](README.md).

## Install / run

There is nothing to `pip install` — the only file you need is `wol_server.py`
and a config JSON.

```bash
# Production (Raspberry Pi): use the installer, which copies the app to
# /opt/wol-pi, seeds /etc/wol-pi/config.json, and installs a systemd unit.
sudo ./install.sh

# Or run it directly (any machine with Python 3.11+):
WOL_CONFIG=./config.json WOL_WEB_DIR=./web python3 wol_server.py --port 8080
```

### Command-line flags

`wol_server.py` accepts only these flags (from `--help`):

| Flag          | Default     | Meaning                                  |
| ------------- | ----------- | ---------------------------------------- |
| `--host`      | `0.0.0.0`   | Address to bind the HTTP server to.      |
| `--port`      | `8080`      | TCP port to listen on.                   |
| `--log-level` | `INFO`      | Python logging level (e.g. `DEBUG`).     |

### Environment variables

| Variable      | Default                    | Meaning                                |
| ------------- | -------------------------- | -------------------------------------- |
| `WOL_CONFIG`  | `/etc/wol-pi/config.json`  | Path to the JSON config file.          |
| `WOL_WEB_DIR` | `/opt/wol-pi/web`          | Directory served for `/` and `/style.css`. |

## Configuration

The config is a single JSON file (validated on startup — the server exits with
a clear log message if `targets` is missing or a MAC is malformed):

```json
{
  "token": "REPLACE-WITH-A-LONG-RANDOM-STRING-OR-REMOVE-TO-DISABLE",
  "broadcast": "255.255.255.255",
  "targets": {
    "desktop-pc": "AA-BB-CC-DD-EE-FF"
  }
}
```

| Key         | Required | Notes                                                                 |
| ----------- | -------- | --------------------------------------------------------------------- |
| `targets`   | yes      | Object mapping a name to a MAC (`AA-BB-CC-DD-EE-FF` or `aa:bb:...`). Must be non-empty; each MAC is regex-validated. |
| `token`     | no       | Shared secret. If set, `POST /wake` requires it (see below). Omit/empty to disable auth. |
| `broadcast` | no       | Broadcast address for the magic packet. Defaults to `255.255.255.255`. |

## HTTP API

| Method & path     | Description                                                        |
| ----------------- | ----------------------------------------------------------------- |
| `GET /`, `GET /index.html` | Serves the single-button web UI (from `WOL_WEB_DIR`).    |
| `GET /style.css`  | Serves the UI stylesheet.                                          |
| `GET /health`     | `{"ok": true, "targets": [...]}` — liveness + known target names.  |
| `GET /targets`    | `{"targets": [...]}` — list of configured target names.           |
| `POST /wake`      | Sends the magic packet. See below.                                |

### `POST /wake`

- Optional JSON body `{"target": "name"}` selects which configured target to
  wake. A `?target=name` query parameter also works. If neither is given, the
  **first** target in the config is used.
- The packet is sent to UDP ports **7 and 9** at the `broadcast` address.
- If `token` is set in the config, the request must include it as either
  `X-WOL-Token: <token>` or `Authorization: Bearer <token>`; otherwise the
  server replies `401`.

Responses observed from a local run:

| Situation                  | Status | Body                                                                       |
| -------------------------- | ------ | -------------------------------------------------------------------------- |
| Success                    | `200`  | `{"ok": true, "target": "desktop-pc", "mac": "AA-BB-CC-DD-EE-FF", "sent_at": 1781804562.77}` |
| Unknown target             | `404`  | `{"error": "unknown target: nope"}`                                        |
| Missing/wrong token        | `401`  | `{"error": "unauthorized"}`                                               |
| Unknown path               | `404`  | (plain HTTP 404)                                                            |

## Worked examples

These were run against a local instance started with a demo config (see
[`examples/`](examples/)). Output is copied verbatim from the run.

### 1. Start the server

```bash
WOL_CONFIG=./examples/config.demo.json python3 wol_server.py --port 18080
```

Log output:

```
2026-06-18 10:42:41,245 INFO wol-pi loaded 1 target(s): desktop-pc
2026-06-18 10:42:42,561 INFO wol-pi listening on http://0.0.0.0:18080  (expect to reach via Tailscale)
```

### 2. Check health and list targets

```bash
curl -s http://127.0.0.1:18080/health
curl -s http://127.0.0.1:18080/targets
```

```json
{"ok": true, "targets": ["desktop-pc"]}
{"targets": ["desktop-pc"]}
```

### 3. Wake a machine

```bash
# explicit target
curl -s -X POST http://127.0.0.1:18080/wake \
  -H 'Content-Type: application/json' \
  -d '{"target":"desktop-pc"}'

# or just hit /wake — the first target is used
curl -s -X POST http://127.0.0.1:18080/wake
```

```json
{"ok": true, "target": "desktop-pc", "mac": "AA-BB-CC-DD-EE-FF", "sent_at": 1781804562.7720914}
```

Server log for the wake (one line per UDP port):

```
2026-06-18 10:42:42,772 INFO wol-pi sent magic packet for AA-BB-CC-DD-EE-FF to 127.255.255.255:7
2026-06-18 10:42:42,772 INFO wol-pi sent magic packet for AA-BB-CC-DD-EE-FF to 127.255.255.255:9
```

### 4. With a shared token

If the config sets `"token"`, requests without it are rejected:

```bash
curl -s -X POST http://127.0.0.1:18080/wake
# {"error": "unauthorized"}   (HTTP 401)

curl -s -X POST http://127.0.0.1:18080/wake -H 'X-WOL-Token: s3cret-demo-token'
# {"ok": true, "target": "desktop-pc", "mac": "AA-BB-CC-DD-EE-FF", "sent_at": 1781804579.01}
```

> The `127.255.255.255` broadcast and demo MAC above come from the local demo
> config; in real use the broadcast is `255.255.255.255` and the MAC is your
> PC's. The magic packet is fire-and-forget UDP, so a `200` means "packet
> sent", not "PC awake" — wait ~60s and connect via RDP.

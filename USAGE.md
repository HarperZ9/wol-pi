# wol-pi Usage

`wol-pi` is a zero-dependency Python HTTP relay for Wake-on-LAN. It reads one JSON config file, serves a small web UI, and sends magic packets to configured MAC addresses.

## Run

```bash
# Production on Raspberry Pi
sudo ./install.sh

# Direct local run
WOL_CONFIG=./examples/config.demo.json WOL_WEB_DIR=./web python3 wol_server.py --port 8080
```

## Command-line flags

| Flag | Default | Meaning |
| --- | --- | --- |
| `--host` | `0.0.0.0` | Address to bind the HTTP server to. |
| `--port` | `8080` | TCP port to listen on. |
| `--log-level` | `INFO` | Python logging level, such as `DEBUG`. |

## Environment variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `WOL_CONFIG` | `/etc/wol-pi/config.json` | Path to the JSON config file. |
| `WOL_WEB_DIR` | `/opt/wol-pi/web` | Directory served for `/` and `/style.css`. |

## Configuration

```json
{
  "token": "",
  "broadcast": "255.255.255.255",
  "targets": {
    "desktop-pc": "AA-BB-CC-DD-EE-FF"
  }
}
```

| Key | Required | Notes |
| --- | --- | --- |
| `targets` | yes | Object mapping a target name to a MAC address. |
| `token` | no | Optional shared token. Empty or omitted disables token auth. |
| `broadcast` | no | Broadcast address for the magic packet. Defaults to `255.255.255.255`. |

MAC addresses can use either `AA-BB-CC-DD-EE-FF` or `aa:bb:cc:dd:ee:ff`.

## HTTP API

| Method and path | Description |
| --- | --- |
| `GET /`, `GET /index.html` | Serves the mobile web UI. |
| `GET /style.css` | Serves the stylesheet. |
| `GET /health` | Returns liveness and configured target names. |
| `GET /targets` | Returns configured target names. |
| `POST /wake` | Sends the magic packet. |

## Wake request

`POST /wake` accepts an optional body:

```json
{"target":"desktop-pc"}
```

The `?target=desktop-pc` query parameter also works. If neither is supplied, the first configured target is used.

If `token` is set in the config, the request must include either `X-WOL-Token: <local-token>` or `Authorization: Bearer <local-token>`.

## Worked examples

Start the local demo server:

```bash
WOL_CONFIG=./examples/config.demo.json WOL_WEB_DIR=./web python3 wol_server.py --port 18080
```

Health and target list:

```bash
curl -s http://127.0.0.1:18080/health
curl -s http://127.0.0.1:18080/targets
```

Expected response shape:

```json
{"ok": true, "targets": ["desktop-pc"]}
```

Send a wake packet:

```bash
curl -s -X POST http://127.0.0.1:18080/wake \
  -H 'Content-Type: application/json' \
  -d '{"target":"desktop-pc"}'
```

Expected response shape:

```json
{"ok": true, "target": "desktop-pc", "mac": "AA-BB-CC-DD-EE-FF", "sent_at": 1781804562.77}
```

With a local shared token enabled:

```bash
curl -s -X POST http://127.0.0.1:18080/wake -H 'X-WOL-Token: <local-token>'
```

The demo broadcast and demo MAC are placeholders. In real use, set the target MAC and optional token only in local config.

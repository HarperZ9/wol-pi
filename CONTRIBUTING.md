# Contributing

`wol-pi` is intentionally small. Contributions should preserve the zero-runtime-dependency Python service, the private-tailnet security posture, and the simple mobile workflow.

## Local checks

```bash
python -m json.tool config.example.json
python -m json.tool examples/config.demo.json
python -m py_compile wol_server.py
git diff --check
```

## Boundaries

- Do not commit real MAC addresses, live tokens, Tailscale hostnames, service logs, or local config.
- Keep examples generic and placeholder-only.
- If HTTP behavior changes, update `README.md`, `USAGE.md`, and `web/` together.
- Do not weaken the systemd service hardening without documenting the operational reason.

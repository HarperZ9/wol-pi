# AGENTS.md - wol-pi

## Scope

This file applies to the `wol-pi` repository. Root workspace instructions still
apply; this repo is a public Raspberry Pi Wake-on-LAN relay for use inside a
private Tailscale tailnet.

## Product Boundary

`wol-pi` owns the installable Pi-side service, hardened systemd unit, mobile web
button, sample config, and one-time Windows Wake-on-LAN prep script.

Keep this repository focused on the public installable relay. Do not commit
operator-specific live config, real device MAC addresses, tailnet identifiers,
shared tokens, local service logs, or machine-specific deployment state.

Publishable surfaces:

- `wol_server.py` - zero-dependency Python HTTP relay and magic-packet sender.
- `install.sh` and `systemd/wol-pi.service` - Pi installation and service
  integration.
- `web/` - mobile-first local web UI.
- `scripts/windows-wol-prep.ps1` - one-time Windows NIC/power configuration.
- `config.example.json`, `README.md`, `AUTHORS.md`, `LICENSE`.

Keep local-only:

- `config.json`, `/etc/wol-pi/`, `.env`, `.env.*`, `.warden-safe-cache/`,
  service logs, local tokens, real device MAC addresses, and Codex local files.

## Editing Rules

- Keep `config.example.json` generic. Use obvious placeholders only.
- Do not weaken the systemd hardening settings without documenting why.
- Keep runtime dependencies at Python standard-library level unless there is a
  clear operational reason to add packaging.
- If request/response behavior changes, update both `wol_server.py` and the
  mobile web UI together.

## Verification

For documentation, config, or boundary-only changes:

```powershell
python -m json.tool config.example.json
python -m py_compile wol_server.py
git diff --check
```

Before committing or pushing, scan changed files for credential-shaped content,
confirm live config paths remain ignored, and confirm any MAC-shaped values in
public examples are placeholders.

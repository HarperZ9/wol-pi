# wol-pi

Wake your Windows PC from anywhere, via a Raspberry Pi on your LAN that's reachable through your Tailscale tailnet. One big button in a mobile browser.

```
[phone (anywhere)] --tailscale--> [Pi on LAN] --magic packet--> [PC]
```

## Hardware

- **Raspberry Pi Zero 2 W** (~$15) or any Pi with Ethernet
- MicroSD card (8GB+)
- Power supply
- **Ethernet cable** from the Pi to the same LAN as the PC (Wi-Fi works too; Ethernet is more reliable)

## Install (Pi side)

```bash
# flash Raspberry Pi OS Lite (bookworm) via Raspberry Pi Imager
# boot, get on Wi-Fi or Ethernet, SSH in

# install Tailscale (so the Pi joins your tailnet)
curl -fsSL https://tailscale.com/install.sh | sudo bash
sudo tailscale up

# clone + install wol-pi
git clone https://github.com/HarperZ9/wol-pi.git
cd wol-pi
sudo ./install.sh

# edit the config with your PC's MAC
sudo nano /etc/wol-pi/config.json
sudo systemctl restart wol-pi
```

Tail the logs to confirm:

```bash
journalctl -u wol-pi -f
```

## Install (PC side — one-time Windows prep)

```powershell
# run as Administrator
.\scripts\windows-wol-prep.ps1
```

This disables Fast Startup (mandatory for WoL from full shutdown), enables Wake-on-Magic-Packet on your Ethernet NIC, and toggles the "allow this device to wake the computer" flag.

**BIOS setting** (one-time, requires a reboot): enter BIOS/UEFI setup, find **Wake on LAN / PCIe Wake-Up / Power On by PCI-E Device**, set to **Enabled**. Save & exit.

## Use (from your phone)

1. Make sure your phone has the Tailscale app installed and connected
2. Open the Pi's tailnet URL in Safari/Chrome: `http://<pi-hostname>:8080/` (hostname is whatever you named it during Tailscale setup, or the Pi's Tailscale IP from `tailscale ip`)
3. Tap the big ⏻ button
4. Wait ~60 seconds for the PC to finish booting
5. Open Microsoft Remote Desktop → connect to your PC's Tailscale hostname → type Windows password

Add the button page to your home screen for one-tap access (iOS: Share → Add to Home Screen; Android: three-dot menu → Add to Home Screen).

## Security

- The Pi is only reachable over your tailnet — your private overlay network. Nothing on the public internet hits it.
- Optional shared token — set `"token": "…"` in `/etc/wol-pi/config.json`. Phone sends it via `X-WOL-Token` header. Second layer on top of Tailscale.
- The systemd unit runs as a dedicated unprivileged user with `NoNewPrivileges`, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, etc.

## Troubleshooting

**Packet sent but PC doesn't wake**

1. Verify PC is fully shut down (Start → Power → Shut down). Not sleep.
2. Ethernet cable is plugged in — link lights on?
3. `windows-wol-prep.ps1` ran successfully?
4. BIOS Wake on LAN enabled?
5. Fast Startup disabled? `powercfg /a` and check there's no "Fast Startup" mentioned.
6. Router doesn't block broadcast within the LAN? (Uncommon but check if you have VLAN segmentation.)

**Pi can't reach PC for the magic packet**

The Pi must be on the same L2 broadcast domain as the PC. If you have VLANs separating them, either put the Pi on the PC's VLAN or use a direct unicast magic packet (modify `send_wol` in `wol_server.py` to use the PC's last-known IP instead of the broadcast address).

**I don't see the Pi on the tailnet**

- Check `tailscale status` on the Pi
- Make sure the Pi's Tailscale account is the same as your phone's
- Check the tailnet admin console at https://login.tailscale.com/admin/machines

## Project layout

```
wol-pi/
├── wol_server.py          # zero-dep Python HTTP server, sends magic packet
├── config.example.json    # seed config (MAC + optional token)
├── install.sh             # idempotent Pi installer
├── systemd/
│   └── wol-pi.service     # hardened systemd unit
├── web/
│   ├── index.html         # mobile-first single-button UI
│   └── style.css          # dark theme matching the onion cockpit
└── scripts/
    └── windows-wol-prep.ps1   # one-shot PC configurator
```

## License

MIT. Copyright © 2026 Zain Dana Harper.

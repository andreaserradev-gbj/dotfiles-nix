# Remote access — reaching geekom over SSH

geekom sits behind a home router, far from where its admin physically is.
There are two ways in, both SSH, and they are deliberately independent: when
one is broken the other is the fallback. Everything below assumes the box has
booted with nobody logged in — `linger` keeps andrea's user manager and the
herdr unit alive ([doc/herdr.md](herdr.md), "The unit").

| layer | transport | configured in |
|---|---|---|
| LAN | sshd on :22, open on every interface | [features/dev/nixos.nix](../features/dev/nixos.nix) (`local.dev.enable`) |
| tailnet | WireGuard, UDP 41641, nothing opened on the router | [hosts/geekom/default.nix](../hosts/geekom/default.nix) (`services.tailscale`) |
| HTTPS to the app | `tailscale serve` → `127.0.0.1:7317`, tailnet-only | **manual**, once per host: enable Serve in the admin console, then `sudo tailscale set --operator=$USER`, then `tailscale serve --bg --https=443 http://127.0.0.1:7317` — runbook in [ovis.md](ovis.md) |

LAN :22 stays open on purpose: it is the only recovery path when the tailnet
is down. The control on who can use it is the key scope, not the port.

## One-time join

The NixOS module starts `tailscaled`; joining the tailnet is a manual command,
run once. The node's identity persists across reboots in
`/var/lib/tailscale/tailscaled.state` — no secret lives in the configuration,
and a rebuild never requires joining again.

```sh
sudo tailscale up                                 # prints a login URL; open it in any browser
tailscale status --json | jq -r .BackendState     # → Running
tailscale ip -4                                   # → 100.x.y.z
```

If that state file is gone — a reinstall, `rm -rf /var/lib/tailscale`,
`tailscale logout`, a rolled-back snapshot — the node comes up not logged in,
and the same `sudo tailscale up` prints a fresh login URL. That needs the LAN
path or the console. Carrying the auth key as sops ciphertext would let a
rebuild re-join unattended; that is deliberately not done, because those losses
are exactly the ones the LAN path still covers.

## Addressing

Prefer the raw `100.x` address in an SSH `Host` block: it cannot fail because
a resolver picked the wrong backend. MagicDNS (`ssh geekom`, the
`<tailnet>.ts.net` name) is the convenience alias — it is on by default for
tailnets created after 2022-10-20.

macOS caveat: `host` and `nslookup` bypass the system resolver and can report
"not found" for a name that works everywhere else. Test with `ping` or
`dscacheutil -q host -a name geekom`.

First connection from any new client (or by a new address form — `100.x` and
the MagicDNS name are separate `known_hosts` entries) prompts once to accept
geekom's host key. Accepting is expected.

## Node-key expiry — disable it for geekom

In the admin console, disable expiry for this machine's node key. Node keys
expire after 180 days by default, and an expired key on a headless box means a
walk to the machine to log in again. An *auth* key expiring is different: it
only blocks new enrolments, it never deauthorises an already-registered node.

## Who can log in, from where

Both authorised keys carry a `from=` scope, which sshd matches against the
**client's** address — measured: the phone authenticated from 192.168.68.57,
not from the host's .62, so a scope pinned to the host's address would have
failed the very login it was written for. A scope rejection shows in the sshd
journal as `correct key but not from a permitted host` → `Refused by key
options`, distinct from an unknown key.

| `from=` scope | key | authorises |
|---|---|---|
| `100.64.0.0/10` | phone key ([user.nix](../user.nix)) | the phone, over the tailnet |
| `192.168.68.0/22` | phone key ([user.nix](../user.nix)) | the phone, over the LAN |
| `127.0.0.1,::1` | loopback-rebuild key ([features/loopback-rebuild/nixos.nix](../features/loopback-rebuild/nixos.nix)) | this host SSHing into itself, for `nrs`/`nrt` over SSH |

Narrowing LAN :22 to `tailscale0` only is a named follow-up, deliberately not
part of the tailnet work: the LAN path is the recovery path.

## Why not Tailscale SSH

`tailscale up --ssh` is deliberately not used. Its default ACL runs in `check`
mode — re-authentication every 12 hours — which breaks unattended reconnects,
and it moves host-key verification into MagicDNS. Plain sshd with one scoped
key is fewer moving parts.

## Phone recipe (Termius)

- **Termius** on Android (free tier): generate the Ed25519 key **on the
  device** — the private half never leaves it — and enable truecolour, mouse
  passthrough and the extended key bar.
- One identity per host: with password auth disabled, a key linked to the
  wrong host fails hard instead of falling back to a prompt.
- **Termux** is the diagnostic fallback only — its mouse reporting is partial
  (modes 1003/1015 are ignored).
- Truecolour over SSH needs `COLORTERM` to survive the hop: `TERM` always
  travels with the PTY, but nothing else is forwarded by default, so
  [features/dev/nixos.nix](../features/dev/nixos.nix) accepts `COLORTERM`
  (Termux and the Mac send it; Termius cannot).

## Troubleshooting

- **Connected, but slow / relayed**: `tailscale netcheck` — if UDP 41641 is
  blocked outbound, connections fall back to DERP relays (working, slow).
- **`BackendState` is `Running`, but inbound SSH is dropped**: reverse-path
  filtering can reject packets arriving on `tailscale0`. The remedy is
  `networking.firewall.checkReversePath = "loose";` in the host file — a
  documented fallback, not the default. Note the option is the firewall's:
  `services.tailscale` has no `checkReversePath`, and naming it there fails
  evaluation.

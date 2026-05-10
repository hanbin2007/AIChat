# Relay server setup — chisel + SSH-over-WSS (Caddy edition)

Goal: let the sandbox (Claude Code on the web) reach the EC2 box's port 22 over `wss://ai.origenclub.cn/_chisel/`, so the agent can `ssh ubuntu@…` from inside the sandbox even though the sandbox only has HTTPS egress.

## Server inventory (verified 2026-05-10)

- Ubuntu 24.04 on AWS (`ip-172-31-34-238`, public IP `13.212.1.7`)
- TLS terminator: **Caddy 2.11.2** (`/etc/caddy/Caddyfile`), Let's Encrypt cert for `ai.origenclub.cn`
- Backend: `aichat-relay.service` (Next.js) on `127.0.0.1:8787`
- sshd: stock, port 22
- No nginx, no docker
- Port `8080` is free → chisel will land there on loopback

Topology after this change:

```
sandbox  ──HTTPS──▶  Caddy :443 (ai.origenclub.cn)
                       ├─ /_chisel/*  ──▶  chisel server :8080 (loopback)
                       │                       └── tunnels TCP ──▶  127.0.0.1:22 (sshd)
                       └─ everything else  ──▶  Next.js :8787 (aichat-relay)
```

---

## Step A. Server-side one-time setup (run on EC2)

SSH in (`ssh ubuntu@13.212.1.7`) and paste the entire block below.

```bash
set -euo pipefail

# 0) sanity
command -v caddy >/dev/null || { echo "caddy missing"; exit 1; }
ss -tln | grep -q ':8080 ' && { echo "port 8080 already in use"; exit 1; }

# 1) install chisel 1.10.1
curl -fsSL https://github.com/jpillora/chisel/releases/download/v1.10.1/chisel_1.10.1_linux_amd64.gz \
  | gunzip > /tmp/chisel
sudo install -m0755 /tmp/chisel /usr/local/bin/chisel
rm /tmp/chisel
/usr/local/bin/chisel --version

# 2) auth file: one user "sandbox", only allowed to dial 127.0.0.1:22
sudo install -d -m0750 /etc/chisel
SECRET=$(openssl rand -hex 32)
sudo tee /etc/chisel/users.json >/dev/null <<JSON
{
  "sandbox:${SECRET}": ["127.0.0.1:22"]
}
JSON
sudo chmod 0640 /etc/chisel/users.json

# 3) systemd unit — chisel listens on loopback only; Caddy fronts TLS
sudo tee /etc/systemd/system/chisel.service >/dev/null <<'EOF'
[Unit]
Description=chisel server (loopback; fronted by Caddy /_chisel/)
After=network.target

[Service]
ExecStart=/usr/local/bin/chisel server \
  --host 127.0.0.1 --port 8080 \
  --authfile /etc/chisel/users.json \
  --keepalive 25s
Restart=always
RestartSec=2
DynamicUser=yes
ProtectSystem=strict
ProtectHome=yes
ReadOnlyPaths=/etc/chisel
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now chisel
sudo systemctl --no-pager status chisel | head -n 12

# 4) Caddy patch — back up, then add /_chisel/* matcher in front of the
#    existing catch-all reverse_proxy.
sudo cp -n /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.pre-chisel

sudo tee /etc/caddy/Caddyfile >/dev/null <<'EOF'
ai.origenclub.cn {
    encode gzip zstd
    log {
        output file /var/log/caddy/access.log {
            roll_size 50mb
            roll_keep 5
        }
        format json
    }

    # Older watch / iOS builds (≤ build 6) emit /v1/... without the /api prefix.
    # Map them onto the Next.js routes at /api/v1/... so existing TestFlight
    # users keep working until the next ship lands the corrected URLs.
    @v1NoApiPrefix path /v1 /v1/*
    rewrite @v1NoApiPrefix /api{uri}

    # SSH-over-WSS bridge for sandbox access (chisel server on loopback).
    handle_path /_chisel/* {
        reverse_proxy 127.0.0.1:8080
    }

    handle {
        reverse_proxy 127.0.0.1:8787 {
            flush_interval -1
            header_up X-Forwarded-Proto https
        }
    }
}

http://13.212.1.7 {
    redir https://ai.origenclub.cn{uri} permanent
}
EOF

# 5) validate + reload Caddy
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl reload caddy
sudo systemctl --no-pager status caddy | head -n 8

# 6) print the secret — copy this into the sandbox env as CHISEL_SECRET
echo
echo "============================ COPY THIS ============================"
echo "CHISEL_SECRET=${SECRET}"
echo "==================================================================="
```

### Verify (run on EC2)

```bash
# Caddy proxies the GET to chisel; chisel responds with its hello banner.
curl -i https://ai.origenclub.cn/_chisel/
# expect: HTTP/2 200, body "Hello from chisel ..."

# Sanity: existing relay still reachable
curl -sI https://ai.origenclub.cn/ | head -n 3
# expect: HTTP/2 307 location: /setup  (or whatever the relay normally returns)
```

If verify fails:

- 502 on `/_chisel/` → `sudo journalctl -u chisel -n 50`
- 404 on `/_chisel/` → Caddyfile didn't reload; `sudo caddy validate ...` and `sudo systemctl reload caddy`
- Existing site broken → restore: `sudo cp /etc/caddy/Caddyfile.bak.pre-chisel /etc/caddy/Caddyfile && sudo systemctl reload caddy`

---

## Step B. Put two secrets into the sandbox env

In Claude Code on the web → Settings → Secrets/Env, add:

| name                  | value                                                                  |
|-----------------------|------------------------------------------------------------------------|
| `CHISEL_SECRET`       | the 64-hex string printed at the end of Step A                         |
| `SSH_PRIVATE_KEY_B64` | `base64 -w0 < /path/to/your_key` — the private key whose pubkey is in `~ubuntu/.ssh/authorized_keys` on EC2 |

Notes:

- The transcript will contain whatever you paste, so prefer a relay-only keypair that you can rotate independently of your daily key.
- The pubkey side must already be in `/home/ubuntu/.ssh/authorized_keys` on EC2 before Step C will work.

---

## Step C. Sandbox-side wiring (I'll do this)

Once you say "secrets 好了", I will:

1. Write `scripts/sandbox-tunnel.sh` — starts `chisel client https://ai.origenclub.cn/_chisel/ 2222:127.0.0.1:22` in the background, authenticated with `sandbox:$CHISEL_SECRET`.
2. Decode `SSH_PRIVATE_KEY_B64` into `~/.ssh/id_relay` (chmod 600) and add a `Host rt` block to `~/.ssh/config` pointing at `127.0.0.1:2222` with that key.
3. Run the tunnel and verify with `ssh rt 'whoami; hostname'`.
4. Add a "Server access" section to `CLAUDE.md` documenting the bring-up so future sessions can resume in one command.

---

## Step D. Revoke / rotate

Revoke (turn off sandbox SSH path entirely):

```bash
sudo systemctl disable --now chisel
sudo cp /etc/caddy/Caddyfile.bak.pre-chisel /etc/caddy/Caddyfile
sudo systemctl reload caddy
sudo rm -f /etc/systemd/system/chisel.service /etc/chisel/users.json
sudo systemctl daemon-reload
```

Rotate the secret (chisel keeps running):

```bash
SECRET=$(openssl rand -hex 32)
sudo tee /etc/chisel/users.json >/dev/null <<JSON
{ "sandbox:${SECRET}": ["127.0.0.1:22"] }
JSON
sudo chmod 0640 /etc/chisel/users.json
sudo systemctl restart chisel
echo "new CHISEL_SECRET=${SECRET}"   # update the sandbox env
```

Rotate the SSH key: regenerate a fresh keypair locally, replace the `sandbox@aichat-relay` line in `~ubuntu/.ssh/authorized_keys` with the new pubkey, and update `SSH_PRIVATE_KEY_B64` in the sandbox env.

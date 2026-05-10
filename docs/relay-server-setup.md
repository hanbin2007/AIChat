# Relay server setup — chisel + SSH-over-WSS

Goal: let the sandbox (Claude Code on the web) reach the EC2 box's port 22 over `wss://ai.origenclub.cn/_chisel/`, so the agent can `ssh ubuntu@...` from inside the sandbox even though the sandbox only has HTTPS egress.

Topology:

```
sandbox  ──HTTPS──▶  nginx :443 (ai.origenclub.cn)  ──proxy /_chisel/──▶  chisel server :8080 (loopback)
   │                                                                                │
   └───── chisel client opens local :2222 ───── tunnels TCP ─────▶  127.0.0.1:22 (sshd on EC2)
```

---

## Step A. Server-side one-time setup (run on EC2)

SSH into the box (`ssh ubuntu@<ec2-host>`) and paste the entire block below into the shell.

```bash
set -euo pipefail

# 0) sanity
command -v nginx >/dev/null || { echo "nginx missing"; exit 1; }
curl -fsS https://ai.origenclub.cn/ -o /dev/null -w "vhost ok: %{http_code}\n" || true

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

# 3) systemd unit — chisel listens on loopback only; nginx terminates TLS
sudo tee /etc/systemd/system/chisel.service >/dev/null <<'EOF'
[Unit]
Description=chisel server (loopback; fronted by nginx /_chisel/)
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

# 4) nginx snippet — NOT auto-included; you'll wire it manually below
sudo tee /etc/nginx/snippets/chisel.conf >/dev/null <<'EOF'
location /_chisel/ {
    proxy_pass http://127.0.0.1:8080/;
    proxy_http_version 1.1;
    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade           $http_upgrade;
    proxy_set_header Connection        "upgrade";
    proxy_read_timeout                 86400s;
    proxy_send_timeout                 86400s;
    proxy_buffering                    off;
}
EOF

# 5) print the secret — copy this into the sandbox env as CHISEL_SECRET
echo
echo "============================ COPY THIS ============================"
echo "CHISEL_SECRET=${SECRET}"
echo "==================================================================="
```

### Then manually wire the snippet into the vhost

```bash
sudo $EDITOR /etc/nginx/sites-enabled/<your ai.origenclub.cn vhost file>
# inside the `server { listen 443 ssl; ... }` block, add:
#     include /etc/nginx/snippets/chisel.conf;

sudo nginx -t && sudo systemctl reload nginx
```

### Verify (run on EC2)

```bash
curl -i https://ai.origenclub.cn/_chisel/
# expect: HTTP/1.1 200 OK and body "Hello from chisel ..."
```

If you get a 404, the `include` line landed in the wrong vhost. If you get 502, the systemd unit isn't running — `sudo journalctl -u chisel -n 50`.

---

## Step B. Put two secrets into the sandbox env

In Claude Code on the web → Settings → Secrets/Env, add:

| name                  | value                                                                  |
|-----------------------|------------------------------------------------------------------------|
| `CHISEL_SECRET`       | the 64-hex string printed at the end of Step A                         |
| `SSH_PRIVATE_KEY_B64` | `base64 -w0 < /path/to/your_key` — the private key whose pubkey is in `~ubuntu/.ssh/authorized_keys` on EC2 |

Notes:
- The transcript will contain whatever you paste, so prefer a relay-only keypair (regeneratable if leaked) over your daily key.
- The pubkey side must already be in `/home/ubuntu/.ssh/authorized_keys` on EC2 before Step C will work.

---

## Step C. Sandbox-side wiring (I'll do this)

Once you say "secrets 好了", I will:

1. Write `scripts/sandbox-tunnel.sh` — starts `chisel client wss://ai.origenclub.cn/_chisel/ 2222:127.0.0.1:22` in the background using `CHISEL_SECRET`.
2. Decode `SSH_PRIVATE_KEY_B64` into `~/.ssh/id_relay` (chmod 600) and add a `Host rt` block to `~/.ssh/config` pointing at `127.0.0.1:2222` with that key.
3. Run the tunnel and verify with `ssh rt 'whoami; hostname'`.
4. Add a "Server access" section to `CLAUDE.md` documenting the bring-up so future sessions can resume in one command.

---

## Step D. (Optional) Strip back later

If you ever want to revoke sandbox access:

```bash
sudo systemctl disable --now chisel
sudo rm -f /etc/systemd/system/chisel.service /etc/chisel/users.json /etc/nginx/snippets/chisel.conf
# remove the `include /etc/nginx/snippets/chisel.conf;` line from the vhost
sudo nginx -t && sudo systemctl reload nginx
```

Rotating the secret = re-run Step A's section 2 and 5, then `sudo systemctl restart chisel`, then update `CHISEL_SECRET` in the sandbox env.

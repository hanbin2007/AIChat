#!/usr/bin/env bash
# One-shot server-side bring-up for chisel + SSH-over-WSS on the
# ai.origenclub.cn box (Caddy in front, Next.js behind on :8787).
#
# Usage on EC2 as the ubuntu user (sudo-capable):
#   bash <(curl -fsSL https://raw.githubusercontent.com/hanbin2007/AIChat/claude/fix-relay-setup-redirect-AETDV/scripts/server-setup-chisel.sh)
#
# Idempotent-ish:
#   - chisel install: skipped if /usr/local/bin/chisel already exists.
#   - users.json    : ALWAYS regenerated → re-running rotates the SECRET.
#   - Caddyfile     : only rewritten if it doesn't already contain a
#                     /_chisel/ block. Backup at /etc/caddy/Caddyfile.bak.pre-chisel.
#
# Prints CHISEL_SECRET at the end. Copy it into the sandbox env.

set -euo pipefail

CHISEL_VERSION="1.10.1"
CHISEL_BIN=/usr/local/bin/chisel

log()  { printf '\e[1;36m[setup]\e[0m %s\n' "$*"; }
warn() { printf '\e[1;33m[setup]\e[0m %s\n' "$*" >&2; }
fail() { printf '\e[1;31m[setup]\e[0m %s\n' "$*" >&2; exit 1; }

# --- 0) sanity ----------------------------------------------------------------
command -v caddy >/dev/null || fail "caddy not installed; this script assumes Caddy fronts TLS"
command -v openssl >/dev/null || fail "openssl missing"
command -v sudo >/dev/null || fail "sudo missing"

# Port 8080 must be free OR already owned by chisel itself.
port_owner=$(sudo ss -tlnp 2>/dev/null | awk '/:8080 /{print $0; exit}')
if [ -n "$port_owner" ] && ! grep -q '"chisel"' <<<"$port_owner"; then
    fail "port 8080 is occupied by something other than chisel: $port_owner"
fi

# --- 1) install chisel --------------------------------------------------------
if [ -x "$CHISEL_BIN" ] && "$CHISEL_BIN" --version 2>/dev/null | grep -q "$CHISEL_VERSION"; then
    log "chisel $CHISEL_VERSION already installed at $CHISEL_BIN, skipping download"
else
    log "installing chisel $CHISEL_VERSION"
    tmp=$(mktemp)
    curl -fsSL "https://github.com/jpillora/chisel/releases/download/v${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_amd64.gz" \
      | gunzip > "$tmp"
    sudo install -m0755 "$tmp" "$CHISEL_BIN"
    rm -f "$tmp"
fi
"$CHISEL_BIN" --version

# --- 2) auth file (regenerated each run) --------------------------------------
log "writing /etc/chisel/users.json (regenerating SECRET)"
sudo install -d -m0750 /etc/chisel
SECRET=$(openssl rand -hex 32)
sudo tee /etc/chisel/users.json >/dev/null <<JSON
{
  "sandbox:${SECRET}": ["127.0.0.1:22"]
}
JSON
sudo chmod 0640 /etc/chisel/users.json

# --- 3) systemd unit ----------------------------------------------------------
# users.json is 0640 root:root, so DynamicUser can't read it directly.
# LoadCredential= copies it into a per-invocation dir readable by the
# dynamic user, exposed via $CREDENTIALS_DIRECTORY.
log "writing /etc/systemd/system/chisel.service"
sudo tee /etc/systemd/system/chisel.service >/dev/null <<'EOF'
[Unit]
Description=chisel server (loopback; fronted by Caddy /_chisel/)
After=network.target

[Service]
LoadCredential=users.json:/etc/chisel/users.json
ExecStart=/usr/local/bin/chisel server --host 127.0.0.1 --port 8080 --authfile ${CREDENTIALS_DIRECTORY}/users.json --keepalive 25s
Restart=always
RestartSec=2
DynamicUser=yes
ProtectSystem=strict
ProtectHome=yes
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable chisel
sudo systemctl restart chisel
sleep 1
if ! sudo systemctl is-active --quiet chisel; then
    warn "chisel failed to start; recent journal:"
    sudo journalctl -u chisel -n 30 --no-pager || true
    fail "chisel.service is not active — fix the above before continuing"
fi
sudo systemctl --no-pager status chisel | head -n 8 || true

# --- 4) Caddyfile patch (only if not already present) -------------------------
if sudo grep -q "/_chisel/" /etc/caddy/Caddyfile 2>/dev/null; then
    log "Caddyfile already contains /_chisel/ route, skipping rewrite"
else
    log "patching /etc/caddy/Caddyfile (backup -> /etc/caddy/Caddyfile.bak.pre-chisel)"
    [ -f /etc/caddy/Caddyfile.bak.pre-chisel ] || sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.pre-chisel
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
fi

# --- 5) validate + reload Caddy ----------------------------------------------
log "validating Caddyfile"
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
log "reloading caddy"
sudo systemctl reload caddy
sudo systemctl --no-pager status caddy | head -n 6 || true

# --- 6) verify ----------------------------------------------------------------
log "verifying chisel reachable via Caddy"
sleep 1
if curl -fsS --max-time 5 https://ai.origenclub.cn/_chisel/ | head -c 80 | grep -qi chisel; then
    echo
    log "OK: /_chisel/ returns chisel hello banner"
else
    warn "verify failed — got:"
    curl -i --max-time 5 https://ai.origenclub.cn/_chisel/ | head -n 12 || true
    warn "check: sudo journalctl -u chisel -n 50 ; sudo journalctl -u caddy -n 50"
fi

log "verifying main site still serves Next.js relay"
curl -sI --max-time 5 https://ai.origenclub.cn/ | head -n 4 || true

# --- 7) print secret ----------------------------------------------------------
echo
echo "============================ COPY THIS ============================"
echo "CHISEL_SECRET=${SECRET}"
echo "==================================================================="
echo "Put this into the sandbox env as CHISEL_SECRET, plus"
echo "SSH_PRIVATE_KEY_B64 = base64 -w0 of the private key whose pubkey"
echo "is already in ~ubuntu/.ssh/authorized_keys."

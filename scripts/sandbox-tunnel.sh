#!/usr/bin/env bash
# Sandbox-side bring-up for SSH-over-WSS to ai.origenclub.cn.
#
# Reads two env vars (set them as Claude Code on the web "Secrets"):
#   CHISEL_SECRET       — the 64-hex string emitted by scripts/server-setup-chisel.sh
#   SSH_PRIVATE_KEY_B64 — base64 of the private key whose pubkey is in
#                         ~ubuntu/.ssh/authorized_keys on the EC2 box
#
# After this script exits, `ssh rt` is wired up. The chisel client runs
# in the background; its log is at $HOME/.cache/sandbox-tunnel/chisel.log.
#
# Idempotent: rerunning just kills the old client and starts a fresh one.

set -euo pipefail

SERVER_URL="https://ai.origenclub.cn/_chisel/"
LOCAL_PORT=2222
REMOTE_TARGET="127.0.0.1:22"
CHISEL_VERSION="1.10.1"
BIN_DIR="$HOME/.local/bin"
CHISEL_BIN="$BIN_DIR/chisel"
LOG_DIR="$HOME/.cache/sandbox-tunnel"
LOG_FILE="$LOG_DIR/chisel.log"
PID_FILE="$LOG_DIR/chisel.pid"
KEY_PATH="$HOME/.ssh/id_relay"
KNOWN_HOSTS="$HOME/.ssh/known_hosts_relay"
SSH_CONFIG="$HOME/.ssh/config"

log() { printf '\e[1;36m[tunnel]\e[0m %s\n' "$*"; }
fail() { printf '\e[1;31m[tunnel]\e[0m %s\n' "$*" >&2; exit 1; }

[ -n "${CHISEL_SECRET:-}" ]       || fail "CHISEL_SECRET not set in env"
[ -n "${SSH_PRIVATE_KEY_B64:-}" ] || fail "SSH_PRIVATE_KEY_B64 not set in env"

# 1) install chisel client if missing or wrong version
if ! [ -x "$CHISEL_BIN" ] || ! "$CHISEL_BIN" --version 2>/dev/null | grep -q "$CHISEL_VERSION"; then
    log "fetching chisel $CHISEL_VERSION → $CHISEL_BIN"
    mkdir -p "$BIN_DIR"
    curl -fsSL "https://github.com/jpillora/chisel/releases/download/v${CHISEL_VERSION}/chisel_${CHISEL_VERSION}_linux_amd64.gz" \
      | gunzip > "$CHISEL_BIN"
    chmod +x "$CHISEL_BIN"
fi

# 2) install ssh client if missing (apt; sandbox usually has sudo)
if ! command -v ssh >/dev/null; then
    log "installing openssh-client"
    sudo apt-get update -qq
    sudo apt-get install -y openssh-client
fi

# 3) write the SSH private key
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
printf '%s' "$SSH_PRIVATE_KEY_B64" | base64 -d > "$KEY_PATH"
chmod 600 "$KEY_PATH"

# 4) write the Host rt stanza in ~/.ssh/config (replacing any prior copy)
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"
python3 - "$SSH_CONFIG" "$KEY_PATH" "$KNOWN_HOSTS" "$LOCAL_PORT" <<'PY'
import os, re, sys
path, key, known_hosts, port = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
src = open(path).read() if os.path.exists(path) else ""
src = re.sub(r"(?ms)^Host rt$.*?(?=^Host |\Z)", "", src).strip()
block = f"""Host rt
    HostName 127.0.0.1
    Port {port}
    User ubuntu
    IdentityFile {key}
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
    UserKnownHostsFile {known_hosts}
    ServerAliveInterval 30
"""
open(path, "w").write((src + "\n\n" if src else "") + block)
PY

# 5) (re)start chisel client
mkdir -p "$LOG_DIR"
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    log "killing previous chisel client (pid $(cat "$PID_FILE"))"
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    sleep 1
fi
log "starting chisel client → ${SERVER_URL} (local :${LOCAL_PORT} → ${REMOTE_TARGET})"
nohup "$CHISEL_BIN" client \
    --auth "sandbox:${CHISEL_SECRET}" \
    --keepalive 25s \
    "$SERVER_URL" \
    "${LOCAL_PORT}:${REMOTE_TARGET}" \
    > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
disown

# 6) wait for "Connected"
for i in $(seq 1 15); do
    if grep -q "Connected" "$LOG_FILE" 2>/dev/null; then
        log "tunnel connected after ${i}s"
        break
    fi
    sleep 1
done
if ! grep -q "Connected" "$LOG_FILE" 2>/dev/null; then
    log "tunnel did not connect; last log lines:"
    tail -n 20 "$LOG_FILE"
    fail "see $LOG_FILE"
fi

# 7) smoke test
log "ssh rt 'whoami; hostname':"
ssh -o ConnectTimeout=10 rt 'whoami; hostname'
log "OK — \`ssh rt\` is live. Tunnel pid: $(cat "$PID_FILE"). Log: $LOG_FILE."

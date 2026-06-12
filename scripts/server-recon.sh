#!/usr/bin/env bash
# Server-side recon for ai.origenclub.cn relay setup.
# Read-only: nothing here mutates the box. Safe to paste-and-run.
# Usage on EC2:
#   bash <(curl -fsSL https://raw.githubusercontent.com/hanbin2007/AIChat/claude/fix-relay-setup-redirect-AETDV/scripts/server-recon.sh)
# or just copy this whole file, paste into a shell, and capture stdout.
#
# Send the output back so I can choose between nginx / caddy / traefik /
# whatever's already terminating TLS on this box, and inspect the relay
# runtime without mutating the server.

set -u
echo "================ host & os ================"
date -u +"utc: %Y-%m-%d %H:%M:%S"
uname -a
. /etc/os-release 2>/dev/null && echo "os: ${PRETTY_NAME:-unknown}"
echo "uptime: $(uptime -p 2>/dev/null || uptime)"

echo
echo "================ public ip vs DNS ================"
PUB_IP=$(curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo "?")
echo "this box's public ip (per ipify): ${PUB_IP}"
for tool in dig getent host; do command -v $tool >/dev/null && { echo "--- $tool ai.origenclub.cn ---"; $tool ai.origenclub.cn 2>&1 | head -n 5; break; }; done

echo
echo "================ ports listening on 80/443/22/8080 ================"
if command -v ss >/dev/null; then
    sudo ss -tlnp 2>/dev/null | awk 'NR==1 || /:(22|80|443|8080|8443|7080|7443) /'
else
    sudo netstat -tlnp 2>/dev/null | awk 'NR<=2 || /:(22|80|443|8080|8443|7080|7443) /'
fi

echo
echo "================ which web/proxy daemons are installed ================"
for pkg in nginx caddy apache2 httpd traefik haproxy openresty envoy frp; do
    if command -v "$pkg" >/dev/null 2>&1; then
        printf "  %-10s -> %s (%s)\n" "$pkg" "$(command -v $pkg)" "$($pkg -v 2>&1 | head -n1)"
    fi
done
# also check by package manager in case it's installed but not on PATH
if command -v dpkg >/dev/null; then
    echo "--- dpkg matches ---"
    dpkg -l 2>/dev/null | awk '/^ii/{print $2}' | grep -iE '^(nginx|caddy|apache2|httpd|traefik|haproxy|openresty|envoy|frpc|frps)' || echo "  (none)"
fi

echo
echo "================ running systemd services likely web/proxy ================"
systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null \
  | awk '{print $1}' \
  | grep -iE 'nginx|caddy|apache|httpd|traefik|haproxy|openresty|envoy|frp|tunnel|cloudflared|tailscale|wireguard' \
  || echo "  (none matched the regex; full running list below)"
echo "--- (top 20 running services for context) ---"
systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | head -n 20

echo
echo "================ containers (if docker/podman present) ================"
if command -v docker >/dev/null; then
    sudo docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>&1 | head -n 30
else
    echo "no docker"
fi
if command -v podman >/dev/null; then
    podman ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' 2>&1 | head -n 30
fi

echo
echo "================ TLS / cert hints ================"
for d in /etc/letsencrypt/live /etc/caddy /var/lib/caddy /etc/ssl/certs/ai.origenclub.cn* /etc/traefik /opt/traefik /etc/acme.sh; do
    if [ -e "$d" ]; then
        echo "--- $d ---"
        sudo ls -la "$d" 2>/dev/null | head -n 20
    fi
done

echo
echo "================ what's serving ai.origenclub.cn from the outside ================"
echo "--- TLS cert summary ---"
echo | timeout 5 openssl s_client -servername ai.origenclub.cn -connect ai.origenclub.cn:443 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "  (s_client failed)"
echo "--- HEAD / via curl ---"
curl -sSI --max-time 5 https://ai.origenclub.cn/ | head -n 12 || true

echo
echo "================ config file locations (no contents) ================"
for d in /etc/nginx /etc/caddy /etc/apache2 /etc/httpd /etc/traefik /etc/haproxy /etc/frp; do
    if [ -d "$d" ]; then
        echo "--- $d ---"
        sudo find "$d" -maxdepth 3 -type f 2>/dev/null | head -n 30
    fi
done

echo
echo "================ sshd ================"
sudo ss -tlnp 2>/dev/null | awk '/sshd/' | head -n 4
grep -E '^(Port|ListenAddress|PasswordAuthentication|PubkeyAuthentication)' /etc/ssh/sshd_config 2>/dev/null

echo
echo "================ done ================"

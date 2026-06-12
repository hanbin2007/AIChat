# Relay Server Access

This document records how to reach and inspect the production relay at
`ai.origenclub.cn`.

## Inventory

- AWS region: `ap-southeast-1`
- EC2 instance: `i-053c0e9ac3927e1b5`
- Hostname: `ip-172-31-34-238`
- Public IP: `13.212.1.7`
- OS: Ubuntu 24.04
- Service: `aichat-relay.service`
- Working directory: `/opt/aichat-relay`
- Runtime: standalone Next.js via `/usr/bin/node /opt/aichat-relay/server.js`
- Listener: `127.0.0.1:8787`
- Public TLS/proxy: Caddy for `ai.origenclub.cn`

## SSH

Use direct SSH when the instance already trusts one of the local keys:

```bash
ssh ubuntu@13.212.1.7
```

If direct SSH returns `Permission denied (publickey)`, push the local public key
with EC2 Instance Connect and then SSH with the matching private key:

```bash
aws ec2-instance-connect send-ssh-public-key \
  --region ap-southeast-1 \
  --instance-id i-053c0e9ac3927e1b5 \
  --availability-zone ap-southeast-1a \
  --instance-os-user ubuntu \
  --ssh-public-key "$(cat ~/.ssh/id_ed25519.pub)"

ssh -i ~/.ssh/id_ed25519 -o IdentitiesOnly=yes ubuntu@13.212.1.7
```

The EC2 Instance Connect key is temporary, so rerun the `send-ssh-public-key`
command before each new SSH session if needed.

## Read-Only Checks

Service and deployment directory:

```bash
systemctl is-active aichat-relay.service
systemctl show aichat-relay.service \
  -p WorkingDirectory -p ExecStart -p ActiveEnterTimestamp -p MainPID \
  --no-pager
```

Health endpoint:

```bash
curl -fsS http://127.0.0.1:8787/api/health
```

Deployment metadata:

```bash
cd /opt/aichat-relay
cat package.json
cat .next/BUILD_ID
sha256sum package.json server.js .next/BUILD_ID .next/required-server-files.json
```

Exact installed dependency versions:

```bash
cd /opt/aichat-relay
node - <<'NODE'
const names = ["next", "react", "react-dom", "typescript"];
for (const name of names) {
  const pkg = require(`./node_modules/${name}/package.json`);
  console.log(`${name} ${pkg.version}`);
}
NODE
```

# Azure VM deployment (self-hosted fork)

How the private `garmin.boltweb.net` gateway runs: one small Ubuntu VM, Docker
Compose, the gateway built from this repo plus Caddy for TLS. Not Container
Apps — the token store is SQLite in WAL mode, which is unreliable on Azure Files.

## Layout on the VM

```
~/garmin/
  .env            # secrets — created by hand on the VM, mode 600, never committed
  Caddyfile       # copy of deploy/azure-vm/Caddyfile
  compose.yaml    # copy of deploy/azure-vm/compose.yaml
  missingmcp/     # git clone of this fork (compose builds ./missingmcp)
```

## Azure resources

Resource group `rg-garmin-mcp`, region `ukwest`, VM `vm-garmin-mcp`
(`Standard_B2ats_v2`, Ubuntu 24.04, 32 GB Standard SSD), static Standard public
IP with DNS label `bolt-garmin-mcp`. NSG `vm-garmin-mcpNSG`: TCP 22 from the
operator's IP only (priority 100), TCP 80/443 from anywhere (priority 110).
Port 8080 is never published — Caddy reaches the gateway over the compose network.

The VM has 1 GB of RAM, so it carries a 2 GB swap file (`/swapfile`, in
`/etc/fstab`) and runs with `MAX_WORKERS=2`. If memory gets tight, resize in
place: `az vm resize -g rg-garmin-mcp -n vm-garmin-mcp --size Standard_B2als_v2`.

## First deploy

```bash
sudo apt update && sudo apt install -y docker.io docker-compose-v2 git unattended-upgrades
sudo usermod -aG docker "$USER"          # log out and back in
mkdir ~/garmin && cd ~/garmin
git clone https://github.com/jabolt/missingmcp.git
cp missingmcp/deploy/azure-vm/{compose.yaml,Caddyfile} .
```

Create `~/garmin/.env` by hand, then `chmod 600 .env`:

```ini
GATEWAY_SECRET=<openssl rand -base64 48 — keep a copy in a password manager>
PUBLIC_URL=https://garmin.boltweb.net
OPERATOR_NAME=<name>
OPERATOR_EMAIL=<email>
MAX_WORKERS=2
ACCESS_TOKEN_TTL_DAYS=90
GATEWAY_LOG_LEVEL=info
```

`PUBLIC_URL` is `https://` + the exact hostname, no trailing slash — a mismatch
shows up as an OAuth redirect loop. Leave `POSTHOG_API_KEY`, `BACKUP_S3_*` and
`WHOOP_*` unset: telemetry, S3 backups and the WHOOP connector stay off.

DNS: an A record for the hostname pointing at the VM's public IP. On Cloudflare
it must be **DNS only** (grey cloud) so Caddy can complete the ACME challenge.

```bash
docker compose up -d --build
```

## Checks

```bash
docker compose ps                                   # both services running
docker compose logs gateway | grep '"stats"'        # JSON stats event, no error-level events
curl -sI https://garmin.boltweb.net/                # 200, valid certificate
curl -s https://garmin.boltweb.net/.well-known/oauth-authorization-server/garmin   # issuer + endpoints start with PUBLIC_URL
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://garmin.boltweb.net/garmin/mcp   # 401
docker compose exec gateway python /app/scripts/status.py   # connected accounts
```

## Updating

```bash
cd ~/garmin/missingmcp && git pull && cd .. && docker compose up -d --build
```

`GARMIN_MCP_REF` in the `Dockerfile` pins the worker (`jabolt/garmin_mcp`) to a
reviewed commit. The worker runs with each user's decrypted Garmin tokens, so
diff any new commit before bumping the pin, then run
`python scripts/gen_garmin_tools.py`.

Never rotate `GATEWAY_SECRET` casually: it encrypts the stored Garmin tokens, so
rotating it signs every user out.

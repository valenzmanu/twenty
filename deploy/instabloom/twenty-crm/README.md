# InstaBloom Twenty CRM Deployment

This directory deploys the InstaBloom CRM at `https://crm.instabloom.gt`.

The branch is based on upstream Twenty tag `v2.9.0`. The deployed Docker image is pinned by `release.env`.

## Runtime

- VPS SSH profile: `agent_vps`
- Remote directory: `/home/manuel/apps/twenty-crm`
- Public URL: `https://crm.instabloom.gt`
- Local origin on VPS: `http://127.0.0.1:3000`
- Cloudflare Tunnel: `twenty-crm`
- Admin bootstrap email: `mantt89.mv@gmail.com`

## Deploy

```bash
DEPLOY_TARGET=agent_vps deploy/instabloom/twenty-crm/scripts/deploy-vps.sh
```

The script syncs this directory to the VPS, preserves the remote `.env`, updates non-secret release values, pulls the pinned image, starts Docker Compose, and runs local and public health checks.

## Secrets

The real `.env` lives only on the VPS and is ignored by Git. Required secret values:

- `PG_DATABASE_PASSWORD`
- `ENCRYPTION_KEY`
- `APP_SECRET`
- `CLOUDFLARE_TUNNEL_TOKEN`

SMTP is not configured yet. Until SMTP is added, Twenty logs system emails instead of sending them.

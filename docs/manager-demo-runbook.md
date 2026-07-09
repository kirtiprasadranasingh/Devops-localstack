# Manager Demo Runbook (~10 min)

## Story

"We use open-source tools instead of AWS/Azure for a small platform: Git, Kestra, Dagger, Dokploy, Netdata."

## Steps

1. **App** — Show GitHub repo `fastapi-minimal-poc` (`/` and `/health`).
2. **Trigger** — Kestra → Execute `dagger-dokploy-pipeline`.
3. **Pipeline** — Logs: clone → Dagger build/push → Dokploy deploy.
4. **Proof** — Open `/health` → `{"status":"ok"}`.
5. **Monitoring** — Netdata CPU/memory during deploy.

## Talking points

- **Kestra** = workflow orchestration (like Step Functions / Logic Apps lite).
- **Dagger** = portable CI build pipeline as code.
- **Dokploy** = app deployment (like App Service / Container Apps lite).
- **Netdata** = infra visibility (like basic CloudWatch).

See `opensource-vs-cloud-note.md` for trade-offs.

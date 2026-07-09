# Open-source mini platform vs AWS/Azure (PoC note)

## Where this stack fits well

- Small and mid-size workloads with predictable traffic.
- Teams wanting lower platform cost and direct control.
- Internal tools, prototypes, and non-regulated workloads.

## Trade-offs to highlight

- Pros:
  - Lower recurring cost
  - No cloud vendor lock-in
  - Customizable deployment workflows
- Cons:
  - More operational ownership (patching, backups, upgrades)
  - Less built-in enterprise governance
  - Scaling and HA require additional design work

## Tool mapping for discussion

- Dokploy -> app deployment surface (alternative to managed app deployment).
- Kestra -> workflow automation and pipeline orchestration.
- Netdata -> infra and container observability baseline.
- GitHub -> source control and change trigger.

## Recommendation

Use this stack for cost-sensitive or fast-moving teams now, and define clear scale thresholds where migration to managed cloud services becomes justified.

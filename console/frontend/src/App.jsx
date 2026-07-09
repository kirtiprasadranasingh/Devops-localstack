import { useCallback, useEffect, useState } from "react";
import EnlightLogo from "./Logo";
import {
  APP_NAME,
  APP_TAGLINE,
  PIPELINE_CLOUD,
  PIPELINE_LOCAL,
  PLATFORM_SUBTITLE,
  STACK_CLOUD,
  STACK_LOCAL,
  TOOL_CHIPS_CLOUD,
  TOOL_CHIPS_LOCAL,
} from "./branding";

const DEFAULT_LABELS = {
  console: "Platform console",
  kestra: "Pipeline automation",
  gitops: "GitOps (ArgoCD)",
  registry: "Image registry",
  netdata: "Monitoring",
  application: "Demo application",
};

function ExternalLink({ href, children, className = "" }) {
  const safe = href && href.startsWith("http");
  if (!safe) return <span className={`${className} disabled`}>{children}</span>;
  return (
    <a href={href} target="_blank" rel="noreferrer" className={className}>
      {children}
    </a>
  );
}

function openLink(href) {
  if (href?.startsWith("http")) window.open(href, "_blank", "noopener,noreferrer");
}

export default function App() {
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(true);
  const [deploying, setDeploying] = useState(false);
  const [deployResult, setDeployResult] = useState(null);
  const [error, setError] = useState(null);

  const isCloud = status?.mode === "oke";
  const stack = isCloud ? STACK_CLOUD : STACK_LOCAL;
  const pipeline = isCloud ? PIPELINE_CLOUD : PIPELINE_LOCAL;
  const chips = isCloud ? TOOL_CHIPS_CLOUD : TOOL_CHIPS_LOCAL;
  const labels = status?.service_labels || DEFAULT_LABELS;
  const pipelineInfo = status?.pipeline;
  const demo = status?.demo;
  const links = status?.links || {};

  const fetchStatus = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/status");
      if (!res.ok) throw new Error(`Status API ${res.status}`);
      setStatus(await res.json());
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchStatus();
    const id = setInterval(fetchStatus, 15000);
    return () => clearInterval(id);
  }, [fetchStatus]);

  async function runDeploy() {
    setDeploying(true);
    setDeployResult(null);
    try {
      const res = await fetch("/api/deploy", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      });
      const data = await res.json();
      if (!res.ok) {
        setDeployResult({ ok: false, detail: data.detail || data });
      } else {
        setDeployResult({ ok: true, ...data });
      }
    } catch (e) {
      setDeployResult({ ok: false, detail: e.message });
    } finally {
      setDeploying(false);
      fetchStatus();
    }
  }

  const healthy = status?.healthy_count ?? 0;
  const total = status?.total ?? 4;
  const allGreen = status?.all_healthy;
  const flowReady = pipelineInfo?.flow_ready;
  const appOk = status?.services?.application?.ok;
  const healthLabel = loading && !status ? "Checking…" : appOk ? "Operational" : "Down";
  const healthClass = appOk ? "ok" : loading && !status ? "" : "down";
  const sloPct = total > 0 ? ((healthy / total) * 100).toFixed(1) : "—";
  const displayHost = status?.paths?.console ? new URL(status.paths.console).host : "—";

  return (
    <div className="el-shell">
      <header className="el-header">
        <a className="el-brand" href="/">
          <EnlightLogo size={40} />
          <div>
            <div className="el-brand-name">{APP_NAME}</div>
            <div className="el-brand-sub">{APP_TAGLINE}</div>
          </div>
        </a>
        <div className="el-live-badge">
          <span className="el-live-dot" />
          Live on Kubernetes
        </div>
      </header>

      <main className="el-main">
        <section className="el-hero-card">
          <p className="el-env-label">{PLATFORM_SUBTITLE}</p>
          <h1>Deploy applications on Oracle OKE</h1>
          <p className="el-hero-desc">
            One console to run the full delivery story — Kestra orchestrates, Dagger builds,
            OCIR stores images, and ArgoCD deploys to Kubernetes via GitOps.
          </p>
          <div className="el-chips">
            {chips.map((c) => (
              <span key={c} className="el-chip">
                {c}
              </span>
            ))}
          </div>
          <div className="el-actions">
            <button
              type="button"
              className="el-btn el-btn-primary"
              onClick={runDeploy}
              disabled={deploying || flowReady === false}
            >
              {deploying ? "Starting…" : "Run client demo ▶"}
            </button>
            {pipelineInfo?.flow_url && (
              <ExternalLink href={pipelineInfo.flow_url} className="el-btn el-btn-outline">
                Open Kestra →
              </ExternalLink>
            )}
            <ExternalLink href={links.application} className="el-btn el-btn-outline">
              Demo app →
            </ExternalLink>
            <button type="button" className="el-btn el-btn-ghost" onClick={fetchStatus}>
              Refresh
            </button>
          </div>
          {pipelineInfo && (
            <p className="el-flow-line">
              Workflow <code>{pipelineInfo.flow_id}</code>
              {flowReady ? <span className="el-ok"> · ready</span> : <span className="el-warn"> · setup needed</span>}
            </p>
          )}
          {deployResult && (
            <div className={`el-alert ${deployResult.detail ? "error" : "success"}`}>
              {deployResult.detail ? (
                typeof deployResult.detail === "object"
                  ? deployResult.detail.hint || deployResult.detail.message
                  : deployResult.detail
              ) : (
                <>
                  Pipeline started.{" "}
                  {deployResult.url?.startsWith("http") && (
                    <a href={deployResult.url} target="_blank" rel="noreferrer">
                      Watch in Kestra →
                    </a>
                  )}
                </>
              )}
            </div>
          )}
        </section>

        <section className="el-dashboard">
          <div className="el-slo">
            <div className="el-slo-ring">
              <span className="el-slo-value">{sloPct}%</span>
            </div>
            <span className="el-slo-label">Platform health</span>
          </div>

          <div className="el-metrics">
            <article className="el-metric">
              <span className="el-metric-icon">⚡</span>
              <h3>Health</h3>
              <p className={`el-metric-val ${healthClass}`}>{healthLabel}</p>
            </article>
            <article className="el-metric">
              <span className="el-metric-icon">☸️</span>
              <h3>Cluster</h3>
              <p className="el-metric-val">{isCloud ? "Oracle OKE" : "Local"}</p>
            </article>
            <article className="el-metric">
              <span className="el-metric-icon">🔄</span>
              <h3>GitOps</h3>
              <p className="el-metric-val ok">{isCloud ? "ArgoCD" : "Dokploy"}</p>
            </article>
            <article className="el-metric">
              <span className="el-metric-icon">🛡️</span>
              <h3>Pipeline</h3>
              <p className={`el-metric-val ${flowReady !== false ? "ok" : "down"}`}>
                {flowReady !== false ? "Kestra ready" : "Setup"}
              </p>
            </article>
          </div>
        </section>

        <section className="el-pipeline-section">
          <h2>Deployment pipeline</h2>
          <div className="el-pipeline">
            {pipeline.map((step, i) => (
              <div key={step.n} className="el-pipeline-wrap">
                <div className="el-pipeline-step">
                  <span className="el-pipeline-icon">{step.icon}</span>
                  <span className="el-pipeline-title">{step.title}</span>
                  <span className="el-pipeline-status">
                    {i < pipeline.length - 1 ? "Ready" : allGreen ? "Healthy" : "—"}
                  </span>
                </div>
                {i < pipeline.length - 1 && <span className="el-pipeline-arrow">→</span>}
              </div>
            ))}
          </div>
        </section>

        {demo && (
          <section className="el-proof">
            <strong>What this demo proves</strong>
            <p>{demo.proves}</p>
          </section>
        )}

        <section className="el-capabilities">
          <h2>Platform capabilities</h2>
          <p className="el-section-lead">
            {isCloud
              ? "Kestra → Dagger → OCIR → ArgoCD → Oracle OKE"
              : "Local laptop stack — Kestra → Dagger → Dokploy"}
          </p>
          <div className="el-cap-grid">
            {stack.map((item, idx) => {
              const href = links[item.linkKey];
              const disabled = !href?.startsWith("http");
              return (
                <article key={item.id} className="el-cap-card">
                  <span className="el-cap-num">{idx + 1}</span>
                  <span className="el-cap-icon">{item.icon}</span>
                  <h3>{item.title}</h3>
                  <p className="el-cap-tool">{item.tool}</p>
                  <p>{item.description}</p>
                  <button
                    type="button"
                    className="el-cap-link"
                    disabled={disabled}
                    onClick={() => openLink(href)}
                  >
                    {item.action} →
                  </button>
                </article>
              );
            })}
          </div>
        </section>

        <section className="el-services">
          <h2>Service status</h2>
          {error && <p className="el-error">{error}</p>}
          {status && (
            <div className="el-service-grid">
              {Object.entries(status.services).map(([name, svc]) => (
                <div key={name} className="el-service-card">
                  <div className="el-service-head">
                    <span className={`el-dot ${svc.ok ? "ok" : svc.skipped ? "skip" : "down"}`} />
                    <span>{labels[name] || name}</span>
                  </div>
                  <p className="el-service-meta">
                    {svc.ok ? svc.note || `${svc.latency_ms}ms` : svc.error || `HTTP ${svc.status_code}`}
                  </p>
                  {links[name]?.startsWith("http") && (
                    <ExternalLink href={links[name]} className="el-cap-link">
                      Open →
                    </ExternalLink>
                  )}
                </div>
              ))}
            </div>
          )}
        </section>
      </main>

      <footer className="el-footer">
        <EnlightLogo size={22} />
        <span>
          {APP_NAME} · {PLATFORM_SUBTITLE} · {displayHost}
        </span>
      </footer>
    </div>
  );
}

import { useCallback, useEffect, useState } from "react";
import EnlightLogo from "./Logo";
import {
  APP_NAME,
  APP_TAGLINE,
  COMPANY_NAME,
  DOMAIN_BASE,
  INGRESS_ROUTES,
  PIPELINE_CLOUD,
  PIPELINE_LOCAL,
  STACK_CLOUD,
  STACK_LOCAL,
} from "./branding";

const DEFAULT_LABELS = {
  console: "Platform console",
  kestra: "Pipeline automation",
  gitops: "GitOps",
  registry: "Image registry",
  netdata: "Monitoring",
  application: "Demo application",
};

function StatusDot({ ok, skipped }) {
  if (skipped) return <span className="status-dot skipped" />;
  return <span className={`status-dot ${ok ? "ok" : "down"}`} />;
}

function ExternalLink({ href, children }) {
  return (
    <a href={href} target="_blank" rel="noreferrer" className="nav-link external">
      {children}
      <span className="ext-icon" aria-hidden="true">
        ↗
      </span>
    </a>
  );
}

function formatHostPath(path) {
  if (path.includes("<host>")) {
    return path.replace("<host>", DOMAIN_BASE);
  }
  if (path.startsWith("/")) {
    return `${DOMAIN_BASE}${path}`;
  }
  return `${DOMAIN_BASE}${path === "/" ? "" : path}`;
}

export default function App() {
  const [status, setStatus] = useState(null);
  const [loading, setLoading] = useState(true);
  const [deploying, setDeploying] = useState(false);
  const [deployResult, setDeployResult] = useState(null);
  const [error, setError] = useState(null);
  const [showRoutes, setShowRoutes] = useState(false);

  const isCloud = status?.mode === "oke";
  const stack = isCloud ? STACK_CLOUD : STACK_LOCAL;
  const pipeline = isCloud ? PIPELINE_CLOUD : PIPELINE_LOCAL;
  const labels = status?.service_labels || DEFAULT_LABELS;
  const pipelineInfo = status?.pipeline;

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
        setDeployResult({ ok: false, triggered: false, detail: data.detail || data });
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
  const displayHost = status?.paths?.console
    ? new URL(status.paths.console).host
    : DOMAIN_BASE;

  return (
    <div className="page">
      <header className="topbar">
        <a className="brand" href="/">
          <EnlightLogo size={40} />
          <span className="brand-name">{APP_NAME}</span>
        </a>
        <nav className="nav">
          <span className="nav-link active">Console</span>
          <ExternalLink href={status?.links?.kestra || "#"}>Kestra</ExternalLink>
          <ExternalLink href={status?.links?.application || "#"}>Demo app</ExternalLink>
          {isCloud && (
            <>
              <ExternalLink href={status?.links?.gitops || "/gitops"}>GitOps</ExternalLink>
              <ExternalLink href={status?.links?.netdata || "/metrics"}>Metrics</ExternalLink>
            </>
          )}
        </nav>
      </header>

      <section className="hero">
        <p className="hero-badge">{APP_TAGLINE}</p>
        <h1>Build, ship, and monitor — all from one screen</h1>
        <p className="hero-lead">
          <strong>{COMPANY_NAME}</strong> gives clients a complete delivery story: automate with{" "}
          <strong>Kestra</strong>, store images in <strong>OCIR</strong>, deploy with{" "}
          <strong>GitOps</strong>, and run on <strong>Kubernetes</strong> — open source, no AWS
          lock-in.
        </p>
        {pipelineInfo && (
          <p className="pipeline-badge">
            Active workflow: <code>{pipelineInfo.flow_id}</code>
            {flowReady ? (
              <span className="badge-ok"> ready</span>
            ) : (
              <span className="badge-warn"> — import in Kestra UI</span>
            )}
          </p>
        )}
        <div className="hero-actions">
          <button
            className="btn btn-primary"
            onClick={runDeploy}
            disabled={deploying}
          >
            {deploying ? "Starting…" : "Run client demo ▶"}
          </button>
          <button className="btn btn-secondary" onClick={fetchStatus}>
            Refresh status
          </button>
          {pipelineInfo?.flow_url && (
            <ExternalLink href={pipelineInfo.flow_url}>View workflow →</ExternalLink>
          )}
        </div>
        {deployResult && (
          <div
            className={`deploy-result ${
              deployResult.detail ? "error" : deployResult.triggered !== false ? "success" : "info"
            }`}
          >
            {deployResult.detail ? (
              <>
                Could not start pipeline.{" "}
                {typeof deployResult.detail === "object"
                  ? deployResult.detail.hint || deployResult.detail.message || JSON.stringify(deployResult.detail)
                  : deployResult.detail}
              </>
            ) : deployResult.triggered !== false ? (
              <>
                Pipeline <code>{deployResult.flow_id}</code> started.{" "}
                {deployResult.url && deployResult.url.startsWith("http") && (
                  <a href={deployResult.url} target="_blank" rel="noreferrer">
                    Watch in Kestra →
                  </a>
                )}
              </>
            ) : (
              <>
                {deployResult.message}{" "}
                {deployResult.hint && <span className="muted">{deployResult.hint}</span>}
              </>
            )}
          </div>
        )}
      </section>

      <section className="stats-row">
        <div className="stat">
          <div className="stat-value">{loading && !status ? "—" : `${healthy}/${total}`}</div>
          <div className="stat-label">Services healthy</div>
        </div>
        <div className="stat">
          <div className="stat-value accent">4</div>
          <div className="stat-label">Pipeline steps</div>
        </div>
        <div className="stat">
          <div className="stat-value accent">{isCloud ? "Cloud" : "Local"}</div>
          <div className="stat-label">Environment</div>
        </div>
        <div className="stat">
          <div className={`stat-value ${allGreen && flowReady !== false ? "accent" : ""}`}>
            {allGreen && flowReady !== false ? "Ready" : flowReady === false ? "Setup" : "Check"}
          </div>
          <div className="stat-label">Demo status</div>
        </div>
      </section>

      <section className="grid capabilities">
        <h2>What&apos;s in the platform</h2>
        <p className="section-lead">
          Every card is a real tool — click to open it, or run the full demo from the button above.
        </p>
        <div className="card-grid">
          {stack.map((item) => (
            <article key={item.id} className="card">
              <p className="card-tool">{item.tool}</p>
              <h3>{item.title}</h3>
              <p>{item.description}</p>
              <button
                type="button"
                className="card-link"
                onClick={() => window.open(status?.links?.[item.linkKey] || "#", "_blank")}
              >
                {item.action}
              </button>
            </article>
          ))}
        </div>
      </section>

      <section className="grid status-panel">
        <h2>Live service health</h2>
        <p className="section-lead">
          Updated every 15 seconds. Green means that part of the platform is reachable.
          {status?.app_note && <span className="muted"> {status.app_note}</span>}
        </p>
        {loading && !status && <p className="muted">Checking services…</p>}
        {error && <p className="error-text">{error}</p>}
        {status && (
          <div className="status-grid">
            {Object.entries(status.services).map(([name, svc]) => (
              <div key={name} className="status-card">
                <div className="status-head">
                  <StatusDot ok={svc.ok} skipped={svc.skipped} />
                  <span className="status-name">{labels[name] || name}</span>
                </div>
                <div className="status-meta">
                  {svc.skipped ? (
                    <span className="muted">{svc.message}</span>
                  ) : svc.ok ? (
                    <span>{svc.note || `${svc.latency_ms}ms response`}</span>
                  ) : (
                    <span className="error-text">{svc.error || `HTTP ${svc.status_code}`}</span>
                  )}
                </div>
                {status.links[name] && !svc.skipped && (
                  <ExternalLink href={status.links[name]}>Open</ExternalLink>
                )}
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="grid how">
        <h2>How the demo works</h2>
        <p className="section-lead">
          {pipelineInfo?.flow_description || "Four steps from button click to live application."}
        </p>
        <div className="steps">
          {pipeline.map((step) => (
            <div key={step.n} className="step">
              <div className="step-num">{step.n}</div>
              <div>
                <h3>{step.title}</h3>
                <p>{step.body}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      <section className="grid oke-section">
        <div className="oke-header">
          <div>
            <h2>Platform URLs</h2>
            <p className="section-lead oke-lead">
              Console and GitOps share one hostname; Kestra and the demo app use subdomains.
              Live host: <code>{displayHost}</code>
            </p>
          </div>
          <button
            type="button"
            className="btn btn-secondary btn-sm"
            onClick={() => setShowRoutes(!showRoutes)}
          >
            {showRoutes ? "Hide paths" : "Show paths"}
          </button>
        </div>
        {showRoutes && (
          <div className="ingress-table">
            {INGRESS_ROUTES.map((row) => (
              <div key={row.path} className="ingress-row">
                <code>{formatHostPath(row.path)}</code>
                <span>{row.service}</span>
              </div>
            ))}
          </div>
        )}
      </section>

      <footer className="footer">
        <div className="footer-brand">
          <EnlightLogo size={28} />
          <span>{COMPANY_NAME}</span>
        </div>
        <p className="muted">
          {isCloud ? "Running on Kubernetes" : "Local development"} · <code>{displayHost}</code>
        </p>
      </footer>
    </div>
  );
}

import { useCallback, useEffect, useState } from "react";
import EnlightLogo from "./Logo";
import { CONSOLE_VERSION, HOME_STATUS_KEYS, HOME_STEPS } from "./branding";

function ExternalLink({ href, children, className = "" }) {
  if (!href?.startsWith("http")) {
    return <span className={`${className} is-disabled`}>{children}</span>;
  }
  return (
    <a href={href} target="_blank" rel="noreferrer" className={className}>
      {children}
    </a>
  );
}

export default function Home({ onRunDemo }) {
  const [status, setStatus] = useState(null);
  const [error, setError] = useState(null);
  const [resetting, setResetting] = useState(false);
  const [resetMsg, setResetMsg] = useState(null);

  const fetchStatus = useCallback(async () => {
    setError(null);
    try {
      const res = await fetch("/api/status");
      if (!res.ok) throw new Error(`Status ${res.status}`);
      setStatus(await res.json());
    } catch (e) {
      setError(e.message);
    }
  }, []);

  useEffect(() => {
    fetchStatus();
    const id = setInterval(fetchStatus, 20000);
    return () => clearInterval(id);
  }, [fetchStatus]);

  const appOk = status?.services?.application?.ok;
  const links = status?.links || {};
  const appUrl = status?.demo?.app_url || links.application;
  const demoLive = status?.demo?.demo_live;
  const canReset = status?.demo?.reset_available;
  const alreadyReset = demoLive === false && canReset === false;

  const handleReset = async () => {
    if (
      !window.confirm(
        "Reset the demo app?\n\nThis removes the app from ArgoCD and the cluster until you run the pipeline again."
      )
    ) {
      return;
    }
    setResetting(true);
    setResetMsg(null);
    setError(null);
    try {
      const res = await fetch("/api/demo/reset", { method: "POST" });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.detail?.error || data.detail?.message || JSON.stringify(data.detail));
      }
      setResetMsg(data.message || "Demo app reset.");
      await fetchStatus();
    } catch (e) {
      setError(e.message);
    } finally {
      setResetting(false);
    }
  };

  return (
    <div className="el-page el-page-v2">
      <div className="el-mesh-bg" aria-hidden>
        <span className="el-orb el-orb-a" />
        <span className="el-orb el-orb-b" />
        <span className="el-orb el-orb-c" />
      </div>

      <header className="el-header el-header-v2">
        <a className="el-header-brand" href="/">
          <EnlightLogo />
        </a>
        <button type="button" className="el-btn el-btn-primary el-btn-header el-btn-glow" onClick={onRunDemo}>
          Run client demo →
        </button>
      </header>

      <main className="el-main-v2">
        <section className="el-hero-v2">
          <p className="el-eyebrow">CLIENT DEMO · KUBERNETES · GITOPS</p>
          <h1>
            Ship code to production with <span className="el-accent-text">one click</span>
          </h1>
          <p className="el-lead">
            One click runs the full pipeline — build, GitOps, deploy, and health check — with a
            live animated view for your client.
          </p>

          <button type="button" className="el-btn el-btn-primary el-btn-hero el-btn-glow" onClick={onRunDemo}>
            Launch live demo →
          </button>

          <div className="el-stat-orbit">
            {[
              { value: "~2 min", label: "Full pipeline", icon: "⚡" },
              { value: "Live logs", label: "Client view", icon: "◎" },
              { value: "GitOps", label: "Auto deploy", icon: "⟳" },
              { value: appOk ? "App live ✓" : "Checking…", label: "Status", icon: "◉" },
            ].map((s) => (
              <div key={s.label} className="el-stat-orbit-card">
                <span className="el-stat-icon" aria-hidden>
                  {s.icon}
                </span>
                <strong>{s.value}</strong>
                <span>{s.label}</span>
              </div>
            ))}
          </div>
        </section>

        <section className="el-section el-section-v2">
          <p className="el-section-label">HOW THE DEMO WORKS</p>
          <h2 className="el-section-title">Four steps your client will see</h2>
          <div className="el-bento">
            {HOME_STEPS.map((s, i) => (
              <article key={s.step} className={`el-bento-card el-bento-${i + 1}`}>
                <span className="el-bento-num">{s.step}</span>
                <h3>{s.title}</h3>
                <p>{s.body}</p>
                <span className="el-bento-shine" aria-hidden />
              </article>
            ))}
          </div>
        </section>

        <section className="el-section el-section-v2">
          <p className="el-section-label">DEMO CONTROLS</p>
          <h2 className="el-section-title">Reset for a clean client run</h2>
          <div className="el-glass-card el-demo-reset-v2">
            <div className="el-demo-reset-copy">
              <p>
                Remove the demo app from the cluster before a client presentation. Run the pipeline
                again to build and redeploy automatically.
              </p>
              <span
                className={`el-demo-badge ${demoLive ? "live" : alreadyReset ? "stopped" : "checking"}`}
              >
                {demoLive
                  ? "Demo app is live"
                  : alreadyReset
                    ? "Demo app removed — ready for pipeline"
                    : "Checking demo status…"}
              </span>
              {resetMsg && <p className="el-demo-reset-msg">{resetMsg}</p>}
            </div>
            <button
              type="button"
              className="el-btn el-btn-reset"
              onClick={handleReset}
              disabled={resetting || !canReset}
              title={
                alreadyReset
                  ? "App already removed — run the pipeline to redeploy"
                  : "Remove app from ArgoCD and cluster"
              }
            >
              {resetting ? "Resetting…" : "Reset demo app"}
            </button>
          </div>
        </section>

        <section className="el-section el-section-v2">
          <p className="el-section-label">PLATFORM STATUS</p>
          {error && <p className="el-error">{error}</p>}
          {status && (
            <div className="el-status-orbit">
              {HOME_STATUS_KEYS.filter((name) => status.services[name]).map((name) => {
                const svc = status.services[name];
                const label = status.service_labels?.[name] || name;
                return (
                  <div key={name} className={`el-status-tile ${svc.ok ? "ok" : "down"}`}>
                    <span className={`el-status-dot ${svc.ok ? "ok" : "down"}`} />
                    <div>
                      <strong>{label}</strong>
                      <span>{svc.ok ? `${svc.latency_ms}ms` : "down"}</span>
                    </div>
                    {links[name]?.startsWith("http") && (
                      <ExternalLink href={links[name]} className="el-link-sm">
                        Open →
                      </ExternalLink>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </section>
      </main>

      <footer className="el-footer el-footer-v2">
        <span>© 2026 Enlight Lab · Console {CONSOLE_VERSION}</span>
        <ExternalLink href={appUrl}>Demo app →</ExternalLink>
      </footer>
    </div>
  );
}

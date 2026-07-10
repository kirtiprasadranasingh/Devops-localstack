import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import EnlightLogo from "./Logo";
import {
  buildLiveFeed,
  CLIENT_PIPELINE,
  CONSOLE_VERSION,
  parseLogMilestones,
} from "./branding";

const DONE_STATES = new Set(["SUCCESS", "FAILED", "KILLED"]);

function taskMap(tasks) {
  const m = {};
  for (const t of tasks || []) m[t.id] = t.state;
  return m;
}

function resolvePhases(tasks, execState, milestones) {
  const tm = taskMap(tasks);
  const s = {};

  const job = tm["run-pipeline-job"];
  const wait = tm["wait-pipeline"];
  const health = tm["health-after"];
  const done = tm.done;

  s.trigger = execState || job || wait || health ? "success" : "running";

  if (job === "FAILED") s.build = "failed";
  else if (job === "SUCCESS" || milestones.done) s.build = "success";
  else if (job === "RUNNING" || milestones.kanikoStarted || milestones.cloned || s.trigger === "success")
    s.build = "running";
  else s.build = "pending";

  if (wait === "FAILED") s.deploy = "failed";
  else if (wait === "SUCCESS") s.deploy = "success";
  else if (s.build === "success" || milestones.done) s.deploy = "running";
  else s.deploy = "pending";

  if (health === "FAILED" || (execState === "FAILED" && s.deploy === "success"))
    s.verify = "failed";
  else if (execState === "SUCCESS" || (health === "SUCCESS" && done === "SUCCESS"))
    s.verify = "success";
  else if (wait === "SUCCESS" || health === "RUNNING") s.verify = "running";
  else s.verify = "pending";

  if (execState === "FAILED") {
    if (job === "FAILED") s.build = "failed";
    else if (wait === "FAILED") s.deploy = "failed";
    else if (health === "FAILED") s.verify = "failed";
    else if (s.verify === "running") s.verify = "failed";
  }

  return CLIENT_PIPELINE.map((step) => ({
    ...step,
    status: s[step.id] || "pending",
  }));
}

function progressPct(phases, execState) {
  if (execState === "SUCCESS") return 100;
  const weights = { success: 1, running: 0.55, pending: 0, failed: 0 };
  const score = phases.reduce((a, p) => a + (weights[p.status] ?? 0), 0);
  const pct = Math.round((score / phases.length) * 100);
  if (execState === "FAILED") return Math.min(pct, 95);
  return Math.min(pct, 99);
}

function formatElapsed(ms) {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m > 0 ? `${m}m ${r}s` : `${r}s`;
}

export default function PipelineRun({ executionId: initialId, onBack, appUrl }) {
  const [executionId, setExecutionId] = useState(initialId || null);
  const [execution, setExecution] = useState(null);
  const [jobLogs, setJobLogs] = useState("");
  const [kestraLines, setKestraLines] = useState([]);
  const [jobMeta, setJobMeta] = useState(null);
  const [error, setError] = useState(null);
  const [starting, setStarting] = useState(!initialId);
  const [startedAt, setStartedAt] = useState(Date.now());
  const [tick, setTick] = useState(0);
  const logRef = useRef(null);

  const startPipeline = useCallback(async () => {
    setStarting(true);
    setError(null);
    setStartedAt(Date.now());
    try {
      const res = await fetch("/api/deploy", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "{}",
      });
      const data = await res.json();
      if (!res.ok) {
        throw new Error(
          data.detail?.hint || data.detail?.message || JSON.stringify(data.detail)
        );
      }
      setExecutionId(data.execution_id);
      window.history.replaceState({}, "", `/run?id=${data.execution_id}`);
    } catch (e) {
      setError(e.message);
    } finally {
      setStarting(false);
    }
  }, []);

  useEffect(() => {
    if (!initialId && !executionId) startPipeline();
  }, [initialId, executionId, startPipeline]);

  useEffect(() => {
    if (!executionId) return undefined;
    let cancelled = false;

    async function poll() {
      try {
        const [execRes, logRes] = await Promise.all([
          fetch(`/api/executions/${executionId}`),
          fetch(`/api/executions/${executionId}/logs`),
        ]);
        if (execRes.ok && !cancelled) setExecution(await execRes.json());
        if (logRes.ok && !cancelled) {
          const data = await logRes.json();
          setJobMeta(data.job);
          setJobLogs(data.job?.logs || "");
          setKestraLines(data.kestra || []);
        }
      } catch {
        /* retry */
      }
    }

    poll();
    const id = setInterval(poll, 1200);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [executionId]);

  useEffect(() => {
    const id = setInterval(() => setTick((t) => t + 1), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [jobLogs, kestraLines, execution?.tasks]);

  const tasks = execution?.tasks || [];
  const execState = execution?.state;
  const milestones = parseLogMilestones(jobLogs);
  const finished = DONE_STATES.has(execState);
  const success = execState === "SUCCESS";
  const failed = execState === "FAILED" || execState === "KILLED";

  const phases = useMemo(
    () => resolvePhases(tasks, execState, milestones),
    [tasks, execState, milestones]
  );

  const activePhase = phases.find((p) => p.status === "running");
  const pct = progressPct(phases, execState);
  const liveFeed = useMemo(
    () => buildLiveFeed(kestraLines, jobLogs, tasks),
    [kestraLines, jobLogs, tasks]
  );
  const elapsed = formatElapsed(Date.now() - startedAt);

  const headline = starting
    ? "Starting your deployment…"
    : success
      ? "Deployment successful"
      : failed
        ? "Deployment failed"
        : activePhase?.label
          ? `${activePhase.label}…`
          : milestones.done
            ? "Deploying to Kubernetes…"
            : milestones.kanikoStarted
              ? "Building your application…"
              : "Pipeline in progress…";

  return (
    <div className="run-page">
      <header className="el-header run-header">
        <button type="button" className="el-link-btn" onClick={onBack}>
          ← Back to console
        </button>
        <EnlightLogo />
        <span className="run-badge">
          Live run · {CONSOLE_VERSION}
          {!finished && <span className="run-pulse-dot" aria-hidden />}
        </span>
      </header>

      {error && <div className="el-banner error run-error">{error}</div>}

      {failed && execution?.error && (
        <div className="el-banner error run-error">
          <strong>Pipeline error:</strong> {execution.error}
        </div>
      )}

      <section className="run-hero">
        <p className="el-eyebrow">LIVE DEPLOYMENT FOR YOUR CLIENT</p>
        <h1 className={success ? "run-headline-ok" : failed ? "run-headline-fail" : ""}>
          {headline}
        </h1>
        <p className="run-sub">
          {success
            ? "The pipeline built a new image, updated GitOps, and verified the live app."
            : failed
              ? "Check the log stream below. After a reset, the app is redeployed during this run."
              : "Real-time progress — Kaniko build, registry push, GitOps, and health check."}
        </p>

        <div className="run-meta-row">
          <span
            className={`run-status-pill ${success ? "ok" : failed ? "fail" : "run"}`}
          >
            {execState || (starting ? "STARTING" : "RUNNING")}
          </span>
          <span className="run-elapsed">Elapsed {elapsed}</span>
        </div>

        <div className="run-progress-wrap">
          <div className="run-progress-bar">
            <div
              className={`run-progress-fill ${finished ? "done" : ""}`}
              style={{ width: `${pct}%` }}
            />
          </div>
          <span className="run-progress-label">
            {success ? "100% complete" : `${pct}% complete`}
          </span>
        </div>
      </section>

      <section className="run-timeline">
        {phases.map((phase, i) => (
          <article
            key={phase.id}
            className={`run-phase ${phase.status} ${activePhase?.id === phase.id ? "active" : ""}`}
          >
            <div className="run-phase-rail">
              <span className="run-phase-dot">
                {phase.status === "success" ? "✓" : phase.status === "failed" ? "!" : phase.icon}
              </span>
              {i < phases.length - 1 && (
                <span
                  className={`run-phase-line ${phase.status === "success" ? "success" : phase.status === "running" ? "running" : ""}`}
                />
              )}
            </div>
            <div className="run-phase-body">
              <h3>{phase.label}</h3>
              <p>{phase.clientLine}</p>
              {phase.status === "running" && (
                <span className="run-phase-live">
                  <span className="run-live-bars" aria-hidden>
                    <i />
                    <i />
                    <i />
                  </span>
                  In progress
                </span>
              )}
              {phase.status === "failed" && <span className="run-phase-live fail">Failed</span>}
            </div>
          </article>
        ))}
      </section>

      <section className="run-logs-wrap">
        <div className="run-logs-head">
          <div>
            <strong>Live activity</strong>
            <p className="run-logs-sub">Kestra tasks + Kaniko build output (updates every second)</p>
          </div>
          {jobMeta?.status && (
            <span className={`run-job-st ${jobMeta.status}`}>{jobMeta.status}</span>
          )}
        </div>
        <div className="run-logs" ref={logRef}>
          {liveFeed.length ? (
            liveFeed.map((line, i) => (
              <div key={`${line.kind}-${i}`} className={`run-log-line ${line.kind}`}>
                {line.text}
              </div>
            ))
          ) : (
            <div className="run-log-line muted">
              {starting
                ? "Starting pipeline…"
                : jobMeta?.status === "pending"
                  ? "Waiting for build job to start…"
                  : "Streaming logs…"}
            </div>
          )}
          {!finished && <div className="run-log-cursor" aria-hidden />}
        </div>
        {milestones.done && !finished && (
          <p className="run-logs-note">
            Build finished — ArgoCD is syncing the new image to Kubernetes (~1–2 min).
          </p>
        )}
      </section>

      {success && (
        <section className="run-success">
          <h2>Ready to show your client</h2>
          <p>The application has been rebuilt and deployed. Open the live demo page.</p>
          <div className="run-done-cta">
            <a
              href={appUrl || "http://app.144-24-100-85.nip.io/"}
              target="_blank"
              rel="noreferrer"
              className="el-btn el-btn-primary"
            >
              Open live demo app →
            </a>
          </div>
        </section>
      )}

      {failed && execution?.url && (
        <section className="run-success">
          <p>
            <a href={execution.url} target="_blank" rel="noreferrer" className="el-link-sm">
              Open this run in Kestra →
            </a>
          </p>
        </section>
      )}
    </div>
  );
}

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import EnlightLogo from "./Logo";
import {
  buildLiveFeed,
  CONSOLE_VERSION,
  mergeTaskStates,
  parseLogMilestones,
  progressPct,
  resolvePhases,
} from "./branding";

const DONE_STATES = new Set(["SUCCESS", "FAILED", "KILLED"]);

function formatElapsed(ms) {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m > 0 ? `${m}m ${r}s` : `${r}s`;
}

function inferExecState(apiState, taskMap, apiTasks) {
  if (apiState && apiState !== "RUNNING") return apiState;
  if (taskMap.__exec) return taskMap.__exec;
  if (taskMap.done === "SUCCESS") return "SUCCESS";
  if (taskMap["health-after"] === "SUCCESS" && taskMap["wait-pipeline"] === "SUCCESS") return "SUCCESS";
  const tracked = (apiTasks || []).filter((t) => t.id && t.state);
  if (tracked.length >= 3 && tracked.every((t) => t.state === "SUCCESS")) return "SUCCESS";
  if (taskMap["health-after"] === "FAILED" || taskMap["run-pipeline-job"] === "FAILED")
    return "FAILED";
  return apiState || "RUNNING";
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
  const [, setTick] = useState(0);
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
        if (!cancelled) {
          if (logRes.ok) {
            const data = await logRes.json();
            setJobMeta(data.job || null);
            setJobLogs(data.job?.logs || "");
            setKestraLines(data.kestra || []);
          } else if (logRes.status >= 400) {
            setJobMeta({ status: "error", error: `Logs API ${logRes.status}` });
          }
        }
      } catch {
        /* retry */
      }
    }

    poll();
    const id = setInterval(poll, 1000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [executionId]);

  useEffect(() => {
    const id = setInterval(() => setTick((n) => n + 1), 1000);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
  }, [jobLogs, kestraLines, execution?.tasks]);

  const tasks = execution?.tasks || [];
  const milestones = parseLogMilestones(jobLogs);
  const mergedTasks = useMemo(
    () => mergeTaskStates(tasks, kestraLines, milestones, jobMeta),
    [tasks, kestraLines, milestones, jobMeta]
  );
  const execState = inferExecState(execution?.state, mergedTasks, tasks);
  const finished = DONE_STATES.has(execState);
  const success = execState === "SUCCESS";
  const failed = execState === "FAILED" || execState === "KILLED";

  const phases = useMemo(
    () => resolvePhases(mergedTasks, execState, milestones, jobMeta),
    [mergedTasks, execState, milestones, jobMeta]
  );

  const activePhase = phases.find((p) => p.status === "running");
  const pct = progressPct(phases, execState);
  const liveFeed = useMemo(
    () => buildLiveFeed(kestraLines, jobLogs, tasks, execState, jobMeta),
    [kestraLines, jobLogs, tasks, execState, jobMeta]
  );
  const elapsed = formatElapsed(Date.now() - startedAt);

  const headline = starting
    ? "Starting your deployment…"
    : success
      ? "Deployment successful"
      : failed
        ? "Deployment failed"
        : activePhase
          ? `${activePhase.label} in progress…`
          : "Pipeline running…";

  return (
    <div className="run-page">
      <header className="el-header run-header">
        <button type="button" className="el-link-btn" onClick={onBack}>
          ← Back
        </button>
        <EnlightLogo />
        <span className="run-badge">
          Live · {CONSOLE_VERSION}
          {!finished && <span className="run-pulse-dot" aria-hidden />}
        </span>
      </header>

      {error && <div className="el-banner error run-error">{error}</div>}
      {failed && execution?.error && (
        <div className="el-banner error run-error">
          <strong>Error:</strong> {execution.error}
        </div>
      )}

      <section className="run-hero run-hero-compact">
        <h1 className={success ? "run-headline-ok" : failed ? "run-headline-fail" : ""}>
          {headline}
        </h1>

        <div className="run-meta-row">
          <span className={`run-status-pill ${success ? "ok" : failed ? "fail" : "run"}`}>
            {execState || (starting ? "STARTING" : "RUNNING")}
          </span>
          <span className="run-elapsed">{elapsed}</span>
        </div>

        <div className="run-progress-wrap">
          <div className="run-progress-bar">
            <div
              className={`run-progress-fill ${finished ? "done" : ""}`}
              style={{ width: `${pct}%` }}
            />
          </div>
          <span className="run-progress-label">{success ? "100%" : `${pct}%`}</span>
        </div>
      </section>

      <section className="run-h-pipeline">
        {phases.map((phase, i) => (
          <div key={phase.id} className="run-h-step-wrap">
            <article
              className={`run-h-step ${phase.status} ${activePhase?.id === phase.id ? "active" : ""}`}
            >
              <div className="run-h-node">
                {phase.status === "success" ? (
                  <span className="run-h-check">✓</span>
                ) : phase.status === "failed" ? (
                  <span className="run-h-fail">!</span>
                ) : phase.status === "running" ? (
                  <span className="run-h-spinner" aria-hidden />
                ) : (
                  <span>{phase.icon}</span>
                )}
              </div>
              <h3>{phase.short || phase.label}</h3>
              <p>{phase.clientLine}</p>
            </article>
            {i < phases.length - 1 && (
              <div
                className={`run-h-connector ${phases[i].status === "success" ? "done" : phases[i].status === "running" ? "active" : ""}`}
              />
            )}
          </div>
        ))}
      </section>

      <section className="run-logs-wrap">
        <div className="run-logs-head">
          <strong>Live activity</strong>
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
                ? "Starting…"
                : jobMeta?.hint ||
                  (jobMeta?.status === "pending"
                    ? "Waiting for pipeline job to start…"
                    : "Connecting to pipeline logs…")}
            </div>
          )}
          {!finished && <div className="run-log-cursor" aria-hidden />}
        </div>
      </section>

      {success && (
        <section className="run-success">
          <a
            href={appUrl || "http://app.144-24-100-85.nip.io/"}
            target="_blank"
            rel="noreferrer"
            className="el-btn el-btn-primary"
          >
            Open live demo app →
          </a>
        </section>
      )}
    </div>
  );
}

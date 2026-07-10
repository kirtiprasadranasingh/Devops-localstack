import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import EnlightLogo from "./Logo";
import {
  buildLiveFeed,
  cachePipelineState,
  CONSOLE_VERSION,
  loadCachedPipeline,
  mergeTaskStates,
  normalizeLogText,
  parseLogMilestones,
  progressPct,
  resolvePhases,
} from "./branding";

const DONE_STATES = new Set(["SUCCESS", "FAILED", "KILLED"]);
const GITOPS_WAIT_MS = 90000;
const PIPELINE_DONE_MS = 120000;

function mergeExecution(prev, incoming) {
  if (!incoming) return prev;
  const rank = (s) => (s === "SUCCESS" ? 3 : s === "FAILED" || s === "KILLED" ? 2 : 1);
  if (prev && rank(prev.state) > rank(incoming.state)) {
    return {
      ...incoming,
      ...prev,
      state: prev.state,
      tasks: incoming.tasks?.length ? incoming.tasks : prev.tasks,
      phases: incoming.phases?.length ? incoming.phases : prev.phases,
    };
  }
  return {
    ...prev,
    ...incoming,
    tasks: incoming.tasks?.length ? incoming.tasks : prev?.tasks || [],
    phases: incoming.phases?.length ? incoming.phases : prev?.phases || [],
  };
}

function formatElapsed(ms) {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const r = s % 60;
  return m > 0 ? `${m}m ${r}s` : `${r}s`;
}

function inferExecState(apiState, taskMap, apiTasks, buildDoneAtMs, serverPct) {
  if (apiState && apiState !== "RUNNING") return apiState;
  if (taskMap.__exec) return taskMap.__exec;
  if (taskMap.done === "SUCCESS") return "SUCCESS";
  if (taskMap["health-after"] === "SUCCESS" && taskMap["wait-pipeline"] === "SUCCESS") return "SUCCESS";
  const tracked = (apiTasks || []).filter((t) => t.id && t.state);
  if (tracked.length >= 3 && tracked.every((t) => t.state === "SUCCESS")) return "SUCCESS";
  if (serverPct === 100) return "SUCCESS";
  if (buildDoneAtMs && Date.now() - buildDoneAtMs >= PIPELINE_DONE_MS) return "SUCCESS";
  if (taskMap["health-after"] === "FAILED" || taskMap["run-pipeline-job"] === "FAILED")
    return "FAILED";
  return apiState || "RUNNING";
}

function ProgressRing({ pct, finished, success }) {
  const r = 54;
  const c = 2 * Math.PI * r;
  const offset = c - (pct / 100) * c;
  return (
    <div className="run-ring-wrap">
      <svg className="run-progress-ring" viewBox="0 0 120 120" aria-hidden>
        <circle className="run-ring-track" cx="60" cy="60" r={r} />
        <circle
          className={`run-ring-fill ${finished ? (success ? "ok" : "fail") : ""}`}
          cx="60"
          cy="60"
          r={r}
          strokeDasharray={c}
          strokeDashoffset={offset}
        />
      </svg>
      <div className="run-ring-inner">
        <span className="run-ring-pct">{success ? "100" : pct}%</span>
        <span className="run-ring-label">complete</span>
      </div>
    </div>
  );
}

export default function PipelineRun({ executionId: initialId, onBack, appUrl }) {
  const cached = initialId ? loadCachedPipeline(initialId) : null;
  const [executionId, setExecutionId] = useState(initialId || null);
  const [execution, setExecution] = useState(
    cached
      ? { state: cached.state, tasks: cached.tasks, phases: cached.phases }
      : null
  );
  const [pipelineUi, setPipelineUi] = useState(
    cached ? { state: cached.state, pct: cached.pct, phases: cached.phases } : null
  );
  const [jobLogs, setJobLogs] = useState("");
  const [kestraLines, setKestraLines] = useState([]);
  const [jobMeta, setJobMeta] = useState(null);
  const [error, setError] = useState(null);
  const [starting, setStarting] = useState(!initialId);
  const [startedAt, setStartedAt] = useState(Date.now());
  const [tick, setTick] = useState(0);
  const buildDoneAt = useRef(null);
  const logRef = useRef(null);

  const startPipeline = useCallback(async () => {
    setStarting(true);
    setError(null);
    setStartedAt(Date.now());
    buildDoneAt.current = null;
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
        const logRes = await fetch(`/api/executions/${executionId}/logs`);
        if (!cancelled && logRes.ok) {
          const data = await logRes.json();
          setJobMeta(data.job || null);
          setJobLogs(normalizeLogText(data.job?.logs || ""));
          setKestraLines(data.kestra || []);
          const ui = data.pipeline_ui || {};
          setPipelineUi(ui);
          const incoming = {
            execution_id: executionId,
            flow_id: data.execution?.flow_id,
            state: ui.state || data.execution?.state,
            tasks: ui.tasks || data.execution?.tasks || [],
            phases: ui.phases || [],
            url: data.execution?.url,
          };
          setExecution((prev) => mergeExecution(prev, incoming));
          if (ui.state === "SUCCESS" || data.execution?.state === "SUCCESS") {
            cachePipelineState(executionId, ui);
          }
        } else if (!cancelled && logRes.status >= 400) {
          setJobMeta({ status: "error", error: `Logs API ${logRes.status}` });
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
    const buildDone = parseLogMilestones(jobLogs).done;
    if (jobMeta?.status === "complete" && buildDone) {
      if (!buildDoneAt.current) buildDoneAt.current = Date.now();
    }
  }, [jobMeta?.status, jobLogs]);

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
  const serverPct = pipelineUi?.pct;
  const execState = useMemo(
    () =>
      inferExecState(
        pipelineUi?.state || execution?.state || cached?.state,
        mergedTasks,
        tasks,
        buildDoneAt.current,
        serverPct
      ),
    [pipelineUi?.state, execution?.state, cached?.state, mergedTasks, tasks, tick, serverPct]
  );
  const finished = DONE_STATES.has(execState);
  const success = execState === "SUCCESS";
  const failed = execState === "FAILED" || execState === "KILLED";

  const phases = useMemo(
    () =>
      resolvePhases(
        mergedTasks,
        execState,
        milestones,
        jobMeta,
        tasks,
        buildDoneAt.current,
        pipelineUi?.phases || execution?.phases
      ),
    [mergedTasks, execState, milestones, jobMeta, tasks, tick, pipelineUi?.phases, execution?.phases]
  );

  useEffect(() => {
    if (success && executionId) {
      cachePipelineState(executionId, {
        state: "SUCCESS",
        tasks,
        phases: phases.map((p) => ({ id: p.id, status: p.status })),
        pct: 100,
      });
    }
  }, [success, executionId, tasks, phases]);

  const activePhase = phases.find((p) => p.status === "running");
  const pct = success ? 100 : progressPct(phases, execState);
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
    <div className="run-page run-page-v2">
      <div className="run-mesh-bg" aria-hidden>
        <span className="run-orb run-orb-a" />
        <span className="run-orb run-orb-b" />
        <span className="run-orb run-orb-c" />
      </div>

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

      <section className="run-command-center">
        <div className="run-command-grid">
          <div className="run-command-copy">
            <p className="run-eyebrow">DEPLOYMENT PIPELINE</p>
            <h1 className={success ? "run-headline-ok" : failed ? "run-headline-fail" : ""}>
              {headline}
            </h1>
            <div className="run-meta-row">
              <span className={`run-status-pill ${success ? "ok" : failed ? "fail" : "run"}`}>
                {execState || (starting ? "STARTING" : "RUNNING")}
              </span>
              <span className="run-elapsed">{elapsed}</span>
            </div>
          </div>
          <ProgressRing pct={pct} finished={finished} success={success} />
        </div>
      </section>

      <section className="run-orbit-pipeline">
        <div className="run-orbit-track">
          {phases.map((phase, i) => (
            <div key={phase.id} className="run-orbit-step-wrap">
              <article
                className={`run-orbit-step ${phase.status} ${activePhase?.id === phase.id ? "active" : ""}`}
              >
                <div className="run-orbit-glow" aria-hidden />
                <div className="run-orbit-node">
                  {phase.status === "success" ? (
                    <span className="run-h-check">✓</span>
                  ) : phase.status === "failed" ? (
                    <span className="run-h-fail">!</span>
                  ) : phase.status === "running" ? (
                    <span className="run-h-spinner" aria-hidden />
                  ) : (
                    <span className="run-orbit-num">{phase.icon}</span>
                  )}
                </div>
                <h3>{phase.short || phase.label}</h3>
                <p>{phase.clientLine}</p>
              </article>
              {i < phases.length - 1 && (
                <div
                  className={`run-orbit-beam ${phases[i].status === "success" ? "done" : phases[i].status === "running" ? "active" : ""}`}
                  aria-hidden
                />
              )}
            </div>
          ))}
        </div>
      </section>

      <section className="run-terminal">
        <div className="run-terminal-chrome">
          <span className="run-terminal-dot red" />
          <span className="run-terminal-dot amber" />
          <span className="run-terminal-dot green" />
          <strong>Live activity</strong>
          {jobMeta?.status && (
            <span className={`run-job-st ${jobMeta.status}`}>{jobMeta.status}</span>
          )}
        </div>
        <div className="run-logs run-logs-v2" ref={logRef}>
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
        <section className="run-success run-success-v2">
          <div className="run-success-glow" aria-hidden />
          <a
            href={appUrl || "http://app.144-24-100-85.nip.io/"}
            target="_blank"
            rel="noreferrer"
            className="el-btn el-btn-primary el-btn-glow"
          >
            Open live demo app →
          </a>
        </section>
      )}
    </div>
  );
}

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import EnlightLogo from "./Logo";
import {
  applyDemoPacing,
  buildLiveFeed,
  cachePipelineState,
  CLIENT_PIPELINE,
  CONSOLE_VERSION,
  getPhaseActivity,
  loadCachedPipeline,
  loadLastSuccess,
  mergePipelineUi,
  mergeTaskStates,
  normalizeLogText,
  parseLogMilestones,
  progressPct,
  resolvePhases,
} from "./branding";

const PLATFORM_SHORTCUTS = [
  {
    id: "app",
    label: "Live application",
    desc: "Open the deployed service",
    icon: "◉",
    linkKey: "application",
    phase: "verify",
  },
  {
    id: "gitops",
    label: "ArgoCD",
    desc: "GitOps sync & rollout status",
    icon: "⟳",
    linkKey: "gitops",
    phase: "deploy",
  },
  {
    id: "kestra",
    label: "Kestra pipeline",
    desc: "Orchestration & task logs",
    icon: "⚡",
    linkKey: "kestra",
    phase: "build",
  },
];

function mergeExecution(prev, incoming) {
  if (!incoming) return prev;
  const rank = (s) => (s === "SUCCESS" ? 3 : s === "FAILED" || s === "KILLED" ? 2 : 1);
  if (prev && rank(prev.state) > rank(incoming.state)) {
    return {
      ...incoming,
      ...prev,
      state: prev.state,
      tasks: incoming.tasks?.length ? incoming.tasks : prev.tasks,
      phases: incoming.phases?.length ? prev.phases : incoming.phases,
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

function inferExecState(apiState, taskMap, lockedSuccess, pacedAllSuccess) {
  // Never surface SUCCESS until paced UI finishes — backend can finish early.
  if (lockedSuccess || pacedAllSuccess) return "SUCCESS";
  if (apiState === "FAILED" || apiState === "KILLED") return apiState;
  if (taskMap["health-after"] === "FAILED" || taskMap["run-pipeline-job"] === "FAILED")
    return "FAILED";
  if (taskMap.__exec === "FAILED") return "FAILED";
  return "RUNNING";
}

function Confetti() {
  const pieces = Array.from({ length: 28 }, (_, i) => i);
  return (
    <div className="run-confetti" aria-hidden>
      {pieces.map((i) => (
        <span key={i} className={`run-confetti-piece c${i % 6}`} style={{ "--i": i }} />
      ))}
    </div>
  );
}
function ProgressRing({ pct, finished, success }) {
  const r = 54;
  const c = 2 * Math.PI * r;
  // Only show 100 when the paced pipeline is fully done — never while a step spins.
  const displayPct = success ? 100 : Math.min(pct, 95);
  const offset = c - (displayPct / 100) * c;
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
        <span className={`run-ring-pct ${success ? "ok" : ""}`}>{displayPct}%</span>
        <span className="run-ring-label">{success ? "complete" : "in progress"}</span>
      </div>
    </div>
  );
}

function ShortcutCard({ item, href, active, done }) {
  const disabled = !href?.startsWith("http");
  const cls = `run-shortcut-card ${done ? "done" : active ? "active" : ""} ${disabled ? "disabled" : ""}`;
  const inner = (
    <>
      <span className="run-shortcut-icon" aria-hidden>
        {item.icon}
      </span>
      <div>
        <strong>{item.label}</strong>
        <span>{item.desc}</span>
      </div>
      {!disabled && <span className="run-shortcut-arrow">→</span>}
    </>
  );
  if (disabled) return <div className={cls}>{inner}</div>;
  return (
    <a href={href} target="_blank" rel="noreferrer" className={cls}>
      {inner}
    </a>
  );
}

export default function PipelineRun({ executionId: initialId, onBack, appUrl, platformLinks = {} }) {
  const lastSuccess = !initialId ? loadLastSuccess() : null;
  const cached = initialId
    ? loadCachedPipeline(initialId)
    : lastSuccess
      ? {
          state: "SUCCESS",
          tasks: [],
          phases: lastSuccess.phases,
          pct: 100,
          durationMs: lastSuccess.durationMs,
          finishedAt: lastSuccess.finishedAt,
        }
      : null;

  const [executionId, setExecutionId] = useState(initialId || lastSuccess?.executionId || null);
  const [execution, setExecution] = useState(
    cached
      ? { state: cached.state, tasks: cached.tasks || [], phases: cached.phases }
      : null
  );
  const [pipelineUi, setPipelineUi] = useState(
    cached ? { state: cached.state, pct: cached.pct ?? 100, phases: cached.phases } : null
  );
  const [lockedSuccess, setLockedSuccess] = useState(cached?.state === "SUCCESS");
  const [runLinks, setRunLinks] = useState({});
  const [jobLogs, setJobLogs] = useState("");
  const [kestraLines, setKestraLines] = useState([]);
  const [jobMeta, setJobMeta] = useState(null);
  const [error, setError] = useState(null);
  const [starting, setStarting] = useState(false);
  const [demoLive, setDemoLive] = useState(null);
  const [startedAt, setStartedAt] = useState(() => {
    const id = initialId || lastSuccess?.executionId;
    if (id) {
      try {
        const stored = sessionStorage.getItem(`el-started-${id}`);
        if (stored) return Number(stored);
      } catch {
        /* private mode */
      }
    }
    if (lastSuccess?.durationMs && lastSuccess?.finishedAt) {
      return lastSuccess.finishedAt - lastSuccess.durationMs;
    }
    return Date.now();
  });
  const [finishedAt, setFinishedAt] = useState(() => {
    if (cached?.state === "SUCCESS" || cached?.state === "FAILED") {
      return cached.finishedAt || Date.now();
    }
    const id = initialId || lastSuccess?.executionId;
    if (id) {
      try {
        const stored = sessionStorage.getItem(`el-finished-${id}`);
        if (stored) return Number(stored);
      } catch {
        /* private mode */
      }
    }
    return null;
  });
  const [tick, setTick] = useState(0);
  const buildDoneAt = useRef(null);
  const logRef = useRef(null);
  const restoredDeployed = Boolean(
    !initialId && lastSuccess?.executionId && cached?.state === "SUCCESS"
  );

  // Idle = ready to start only when app is NOT deployed (after reset).
  const idle = !executionId && !starting && demoLive === false;

  useEffect(() => {
    let cancelled = false;
    fetch("/api/status")
      .then((r) => r.json())
      .then((d) => {
        if (cancelled) return;
        const live = d.demo?.demo_live === true;
        setDemoLive(live);
        if (live && !initialId) {
          // App still deployed — keep green completed view (never idle Run)
          setLockedSuccess(true);
          if (!lastSuccess) {
            const done = Date.now();
            setStartedAt(done - 120000);
            setFinishedAt(done);
            setPipelineUi({
              state: "SUCCESS",
              pct: 100,
              phases: CLIENT_PIPELINE.map((p) => ({ id: p.id, status: "success" })),
            });
            setExecution({
              state: "SUCCESS",
              tasks: [],
              phases: CLIENT_PIPELINE.map((p) => ({ id: p.id, status: "success" })),
            });
          } else {
            setFinishedAt((prev) => prev || lastSuccess.finishedAt || Date.now());
          }
        } else if (!live && !initialId) {
          // After reset: clear sticky success and show Run pipeline
          setExecutionId(null);
          setLockedSuccess(false);
          setExecution(null);
          setPipelineUi(null);
          setFinishedAt(null);
        }
      })
      .catch(() => {
        if (!cancelled) setDemoLive(false);
      });
    return () => {
      cancelled = true;
    };
  }, [initialId]);

  const startPipeline = useCallback(async () => {
    setStarting(true);
    setError(null);
    const now = Date.now();
    setStartedAt(now);
    setFinishedAt(null);
    buildDoneAt.current = null;
    setLockedSuccess(false);
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
      try {
        sessionStorage.setItem(`el-started-${data.execution_id}`, String(now));
        sessionStorage.removeItem(`el-finished-${data.execution_id}`);
      } catch {
        /* private mode */
      }
      window.history.replaceState({}, "", `/run?id=${data.execution_id}`);
    } catch (e) {
      setError(e.message);
    } finally {
      setStarting(false);
    }
  }, []);

  useEffect(() => {
    if (!executionId || lockedSuccess) return undefined;
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
          const execStateFromApi = data.execution?.state;
          setPipelineUi((prev) =>
            mergePipelineUi(prev || loadCachedPipeline(executionId), {
              ...ui,
              live_health: data.pipeline_ui?.live_health ?? data.live_health,
            })
          );
          if (data.links) setRunLinks(data.links);
          const incoming = {
            execution_id: executionId,
            flow_id: data.execution?.flow_id,
            state: execStateFromApi || ui.state,
            tasks: ui.tasks || data.execution?.tasks || [],
            phases: ui.phases || [],
            url: data.execution?.url,
          };
          setExecution((prev) => mergeExecution(prev, incoming));
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
  }, [executionId, lockedSuccess]);

  useEffect(() => {
    const buildDone = parseLogMilestones(jobLogs).done;
    if (jobMeta?.status === "complete" && buildDone) {
      if (!buildDoneAt.current) buildDoneAt.current = Date.now();
    }
  }, [jobMeta?.status, jobLogs]);

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
  const realPhases = useMemo(() => {
    if (lockedSuccess) {
      return CLIENT_PIPELINE.map((step) => ({ ...step, status: "success" }));
    }
    return resolvePhases(
      mergedTasks,
      pipelineUi?.state || execution?.state || "RUNNING",
      milestones,
      jobMeta,
      tasks,
      buildDoneAt.current,
      pipelineUi?.phases || execution?.phases,
      pipelineUi?.live_health
    );
  }, [
    mergedTasks,
    pipelineUi?.state,
    execution?.state,
    milestones,
    jobMeta,
    tasks,
    tick,
    pipelineUi?.phases,
    execution?.phases,
    lockedSuccess,
    pipelineUi?.live_health,
  ]);

  const phases = useMemo(() => {
    if (lockedSuccess) {
      return CLIENT_PIPELINE.map((step) => ({ ...step, status: "success" }));
    }
    return applyDemoPacing(
      realPhases,
      startedAt,
      milestones,
      jobMeta,
      pipelineUi?.live_health
    );
  }, [realPhases, startedAt, milestones, jobMeta, pipelineUi?.live_health, lockedSuccess, tick]);

  const pacedAllSuccess = phases.every((p) => p.status === "success");

  const execState = useMemo(
    () =>
      inferExecState(
        pipelineUi?.state || execution?.state || cached?.state,
        mergedTasks,
        lockedSuccess,
        pacedAllSuccess
      ),
    [
      pipelineUi?.state,
      execution?.state,
      cached?.state,
      mergedTasks,
      lockedSuccess,
      pacedAllSuccess,
    ]
  );

  const success = lockedSuccess || pacedAllSuccess || (demoLive === true && restoredDeployed);
  const failed = execState === "FAILED" || execState === "KILLED";
  const finished = success || failed;

  useEffect(() => {
    if (finished) return undefined;
    const id = setInterval(() => setTick((n) => n + 1), 1000);
    return () => clearInterval(id);
  }, [finished]);

  // Freeze wall-clock when pipeline completes
  useEffect(() => {
    if ((success || failed) && !finishedAt) {
      const now = Date.now();
      setFinishedAt(now);
      if (executionId) {
        try {
          sessionStorage.setItem(`el-finished-${executionId}`, String(now));
        } catch {
          /* private mode */
        }
      }
    }
  }, [success, failed, finishedAt, executionId]);

  useEffect(() => {
    if (pacedAllSuccess && !lockedSuccess) setLockedSuccess(true);
  }, [pacedAllSuccess, lockedSuccess]);

  useEffect(() => {
    if (success && executionId) {
      const durationMs = Math.max(0, (finishedAt || Date.now()) - startedAt);
      cachePipelineState(executionId, {
        state: "SUCCESS",
        tasks,
        phases: phases.map((p) => ({ id: p.id, status: "success" })),
        pct: 100,
        durationMs,
        finishedAt: finishedAt || Date.now(),
      });
    }
  }, [success, executionId, tasks, phases, finishedAt, startedAt]);

  const activePhase = success ? null : phases.find((p) => p.status === "running");
  // Percent follows paced phases only — never jump to 100 while Health is still spinning.
  const pct = success ? 100 : progressPct(phases, failed ? "FAILED" : "RUNNING");
  const phaseElapsed = activePhase
    ? formatElapsed(Date.now() - startedAt - (CLIENT_PIPELINE.findIndex((p) => p.id === activePhase.id) * 28000))
    : null;
  const activityLine = activePhase
    ? getPhaseActivity(activePhase.id, Date.now() - startedAt)
    : success
      ? "All phases complete — application verified on your cluster"
      : null;
  const liveFeed = useMemo(
    () => buildLiveFeed(kestraLines, jobLogs, tasks, execState, jobMeta),
    [kestraLines, jobLogs, tasks, execState, jobMeta]
  );
  const elapsedMs = Math.max(0, (finished && finishedAt ? finishedAt : Date.now()) - startedAt);
  const elapsed = formatElapsed(elapsedMs);

  const phaseStatus = Object.fromEntries(phases.map((p) => [p.id, p.status]));
  const kestraExecUrl = execution?.url || runLinks.kestra_execution;
  const resolvedAppUrl = appUrl || runLinks.application || platformLinks.application;
  const gitopsUrl = runLinks.gitops || platformLinks.gitops;
  const kestraUiUrl = runLinks.kestra || platformLinks.kestra;

  const checkingDeploy = demoLive === null && !executionId && !starting && !lockedSuccess;
  const showIdle = idle && !checkingDeploy && !lockedSuccess;

  const headline = checkingDeploy
    ? "Checking deployment…"
    : showIdle
    ? "Ready to deploy"
    : starting
      ? "Starting deployment…"
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

      <header className="el-header run-header run-header-v2">
        <div className="run-header-left">
          <button type="button" className="el-link-btn run-back-btn" onClick={onBack}>
            ← Back
          </button>
          <EnlightLogo variant="run" />
        </div>
        <span className="run-badge">
          Live · {CONSOLE_VERSION}
          {!finished && !showIdle && !checkingDeploy && <span className="run-pulse-dot" aria-hidden />}
        </span>
      </header>

      {error && <div className="el-banner error run-error">{error}</div>}
      {failed && execution?.error && (
        <div className="el-banner error run-error">
          <strong>Error:</strong> {execution.error}
        </div>
      )}

      {checkingDeploy ? (
        <section className="run-idle">
          <div className="run-idle-inner">
            <p className="run-eyebrow">DEPLOYMENT PIPELINE</p>
            <h1>Checking cluster…</h1>
            <p className="run-idle-lead">Looking up whether the demo app is already deployed.</p>
          </div>
        </section>
      ) : showIdle ? (
        <section className="run-idle">
          <div className="run-idle-inner">
            <p className="run-eyebrow">DEPLOYMENT PIPELINE</p>
            <h1>Self-hosted delivery pipeline</h1>
            <p className="run-idle-lead">
              This workflow runs on your Kubernetes cluster using open components — Kestra
              orchestration, Kaniko builds, GitOps via ArgoCD, and health verification on your
              infrastructure. The live view paces each phase (~2 minutes) so you can follow
              build, deploy, and verify in real time.
            </p>
            <button
              type="button"
              className="el-btn el-btn-primary el-btn-hero el-btn-glow"
              onClick={startPipeline}
            >
              Run pipeline on cluster →
            </button>
            <div className="run-idle-preview">
              {CLIENT_PIPELINE.map((step) => (
                <div key={step.id} className="run-idle-step">
                  <span className="run-idle-num">{step.icon}</span>
                  <div>
                    <strong>{step.short || step.label}</strong>
                    <span>{step.clientLine}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>
      ) : (
        <>
          <section className="run-command-center">
            <div className="run-command-grid">
              <div className="run-command-copy">
                <p className="run-eyebrow">DEPLOYMENT PIPELINE</p>
                <h1 className={success ? "run-headline-ok" : failed ? "run-headline-fail" : ""}>
                  {headline}
                </h1>
                <div className="run-meta-row">
                  <span className={`run-status-pill ${success ? "ok" : failed ? "fail" : "run"}`}>
                    {success ? "SUCCESS" : execState || (starting ? "STARTING" : "RUNNING")}
                  </span>
                  <span className="run-elapsed">{elapsed}</span>
                  {activePhase && phaseElapsed && (
                    <span className="run-phase-elapsed">{activePhase.short}: {phaseElapsed}</span>
                  )}
                </div>
                {activityLine && !success && (
                  <p className="run-activity-line" key={tick}>
                    <span className="run-activity-pulse" aria-hidden />
                    {activityLine}
                  </p>
                )}
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

          <section className="run-shortcuts">
            <p className="run-shortcuts-label">PLATFORM LINKS</p>
            <div className="run-shortcuts-grid">
              {PLATFORM_SHORTCUTS.map((item) => {
                const phaseId =
                  item.phase === "verify"
                    ? "verify"
                    : item.phase === "deploy"
                      ? "deploy"
                      : "build";
                const phaseDone = phaseStatus[phaseId] === "success" || success;
                const phaseActive = phaseStatus[phaseId] === "running";
                let href = platformLinks[item.linkKey] || "";
                if (item.id === "gitops") href = gitopsUrl || href;
                if (item.id === "kestra") href = kestraExecUrl || kestraUiUrl || href;
                if (item.id === "app") href = resolvedAppUrl || href;
                return (
                  <ShortcutCard
                    key={item.id}
                    item={item}
                    href={href}
                    active={phaseActive}
                    done={phaseDone}
                  />
                );
              })}
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
              <Confetti />
              <div className="run-success-glow" aria-hidden />
              <p className="run-success-msg">Your application is live and healthy.</p>
              <a
                href={resolvedAppUrl || "http://app.144-24-100-85.nip.io/"}
                target="_blank"
                rel="noreferrer"
                className="el-btn el-btn-primary el-btn-glow"
              >
                Open live application →
              </a>
            </section>
          )}
        </>
      )}
    </div>
  );
}

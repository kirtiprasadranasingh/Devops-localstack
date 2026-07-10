/** Client-facing copy — no vendor branding, no duplication with run page */

export const COMPANY_NAME = "Enlight Lab";
export const APP_NAME = "Enlight Lab";
export const CONSOLE_VERSION = "v35";

export const VALUE_PILLARS = [
  {
    value: "Self-hosted",
    label: "Your OKE cluster",
    icon: "⬡",
  },
  {
    value: "Open stack",
    label: "Kestra · ArgoCD · GitOps",
    icon: "◎",
  },
  {
    value: "Portable",
    label: "Any Kubernetes cloud",
    icon: "⟡",
  },
  {
    value: "Observable",
    label: "Live pipeline view",
    icon: "◉",
  },
];

/** Platform status cards — icon, tagline, accent */
export const STATUS_META = {
  console: {
    icon: "⊞",
    tag: "Control plane",
    hint: "Self-hosted platform console",
    accent: "purple",
  },
  application: {
    icon: "◉",
    tag: "Workload",
    hint: "Sample app on your cluster",
    accent: "green",
  },
  kestra: {
    icon: "⚡",
    tag: "Orchestration",
    hint: "Open-source workflow engine",
    accent: "amber",
  },
  gitops: {
    icon: "⟳",
    tag: "GitOps",
    hint: "ArgoCD — declarative deploys",
    accent: "blue",
  },
};

export const HOME_STEPS = [
  {
    step: "1",
    title: "Orchestrate on your cluster",
    body: "Kestra runs the workflow on self-hosted Kubernetes — no external SaaS deploy dependency.",
  },
  {
    step: "2",
    title: "Build with open tooling",
    body: "Kaniko builds the container image inside the cluster and pushes to your registry (OCIR).",
  },
  {
    step: "3",
    title: "GitOps — you own the source",
    body: "Manifests commit to your Git repo; ArgoCD syncs to the cluster you control.",
  },
  {
    step: "4",
    title: "Verify on your infrastructure",
    body: "Health checks run against the live app on your stack — full traceability end to end.",
  },
];

/** Services shown on home — no registry / monitoring clutter */
export const HOME_STATUS_KEYS = ["console", "application", "kestra", "gitops"];

export const CLIENT_PIPELINE = [
  {
    id: "trigger",
    label: "Start",
    short: "Started",
    clientLine: "Deploy request received",
    icon: "1",
  },
  {
    id: "build",
    kestraTasks: ["run-pipeline-job"],
    label: "Build",
    short: "Build",
    clientLine: "Kaniko builds the app image",
    icon: "2",
  },
  {
    id: "deploy",
    kestraTasks: ["wait-pipeline"],
    label: "Deploy",
    short: "GitOps",
    clientLine: "ArgoCD rolls out the new version",
    icon: "3",
  },
  {
    id: "verify",
    kestraTasks: ["health-after", "done"],
    label: "Verify",
    short: "Health",
    clientLine: "Live app health check passes",
    icon: "4",
  },
];

const TASK_LABELS = {
  "run-pipeline-job": "Build job",
  "wait-pipeline": "GitOps sync",
  "health-after": "Health check",
  done: "Complete",
};

/** Matches Kestra wait-pipeline PT90S + health-after in oke-dagger-gitops-pipeline */
const GITOPS_WAIT_MS = 90000;
const PIPELINE_DONE_MS = 120000;

/** Decode API log text — handles legacy bytes repr strings from older console builds. */
export function normalizeLogText(logs) {
  if (!logs) return "";
  let text = typeof logs === "string" ? logs : String(logs);
  if (text.startsWith("b'") || text.startsWith('b"')) {
    text = text
      .replace(/^b['"]/, "")
      .replace(/['"]$/, "")
      .replace(/\\n/g, "\n")
      .replace(/\\t/g, "\t")
      .replace(/\\xe2\\x80\\x94/g, "—");
  }
  return text.replace(/\x1b\[[0-9;]*m/g, "");
}

export function parseLogMilestones(logs) {
  const text = normalizeLogText(logs);
  return {
    cloned: /Clone GitHub|Cloning into/.test(text),
    gitPushed: /deploy:.*\[kestra pipeline\]|GitOps commit/.test(text),
    kanikoStarted: /Kaniko build/.test(text),
    imagePushed: /Pushed ap-mumbai|DONE ap-mumbai/.test(text),
    done: /DONE ap-mumbai/.test(text),
    failed: /git: not found|ERROR:|Failed/.test(text),
  };
}

export function cachePipelineState(execId, payload) {
  if (!execId || !payload?.state) return;
  if (!["SUCCESS", "FAILED", "KILLED"].includes(payload.state)) return;
  const data = JSON.stringify({
    state: payload.state,
    tasks: payload.tasks || [],
    phases: payload.phases || [],
    pct: payload.pct,
    savedAt: Date.now(),
  });
  try {
    sessionStorage.setItem(`el-pipeline-${execId}`, data);
    localStorage.setItem(`el-pipeline-${execId}`, data);
  } catch {
    /* private mode */
  }
}

export function loadCachedPipeline(execId) {
  if (!execId) return null;
  try {
    const raw =
      sessionStorage.getItem(`el-pipeline-${execId}`) ||
      localStorage.getItem(`el-pipeline-${execId}`);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function mergePipelineUi(prev, incoming) {
  if (!incoming) return prev;
  const rank = (s) => (s === "SUCCESS" ? 3 : s === "FAILED" || s === "KILLED" ? 2 : 1);
  if (prev && rank(prev.state) > rank(incoming.state || "RUNNING")) {
    return {
      ...incoming,
      ...prev,
      state: prev.state,
      pct: prev.state === "SUCCESS" ? 100 : (prev.pct ?? incoming.pct),
      phases:
        prev.state === "SUCCESS"
          ? [
              { id: "trigger", status: "success" },
              { id: "build", status: "success" },
              { id: "deploy", status: "success" },
              { id: "verify", status: "success" },
            ]
          : prev.phases?.length
            ? prev.phases
            : incoming.phases,
    };
  }
  return { ...prev, ...incoming };
}

export function applyServerPhases(serverPhases, clientPhases) {
  if (!serverPhases?.length) return clientPhases;
  const statusById = Object.fromEntries(serverPhases.map((p) => [p.id, p.status]));
  if (serverPhases.every((p) => p.status === "success")) {
    return clientPhases.map((step) => ({ ...step, status: "success" }));
  }
  return clientPhases.map((step) => ({
    ...step,
    status: statusById[step.id] || step.status || "pending",
  }));
}

export function filterClientLogs(logs) {
  const text = normalizeLogText(logs);
  if (!text) return [];
  const keep = [
    /^==>/,
    /Enlight pipeline/i,
    /Clone GitHub|Cloning into/,
    /GitOps commit/,
    /\[main /,
    /deploy:/,
    /Kaniko build/i,
    /^DONE /,
    /INFO\[/,
    /pip install/,
    /Pushed /,
    /ERROR|Failed/i,
    /git: not found/,
  ];
  return text
    .split("\n")
    .map((l) => l.trimEnd())
    .filter((line) => line && keep.some((re) => re.test(line)))
    .slice(-40);
}

/** Prefer filtered build lines; fall back to a readable tail when filter is empty. */
export function pickBuildLogLines(logs) {
  const text = normalizeLogText(logs);
  const filtered = filterClientLogs(text);
  if (filtered.length) return filtered;
  if (!text) return [];
  return text
    .split("\n")
    .map((l) => l.trimEnd())
    .filter((line) => {
      if (!line || line.length > 220) return false;
      if (line.startsWith("==>")) return true;
      if (/Clone|Kaniko|GitOps|deploy:|DONE |pip install|Pushed |INFO\[|ERROR/i.test(line))
        return true;
      return false;
    })
    .slice(-30);
}

/** Turn Kestra log line (JSON or text) into a client-friendly string — never raw JSON. */
export function humanizeKestraLine(raw) {
  const msg = typeof raw === "string" ? raw : raw?.message;
  if (!msg || typeof msg !== "string") return null;

  const trimmed = msg.trim();
  if (!trimmed || trimmed === "[]" || trimmed === "{}") return null;

  if (trimmed.startsWith("Task ")) return trimmed.replace(/\s+/g, " ");

  if (trimmed.startsWith("Execution state:")) return trimmed;

  if (trimmed.startsWith("{")) {
    try {
      const j = JSON.parse(trimmed);
      const tid = j.taskId || j.task?.id;
      const level = (j.level || "").toUpperCase();

      if (j.message && typeof j.message === "string") {
        const m = j.message;
        if (m.includes("Deploy complete")) return "✓ Deployment complete";
        if (m.includes("response code '200'") || m.includes('response code "200"'))
          return "✓ Health check passed";
        if (m.includes("UnknownHostException") || m.includes("Name or service not known"))
          return "✗ App not reachable yet (normal right after reset)";
        if (level === "ERROR") return `✗ ${tid || "Task"}: ${m.slice(0, 120)}`;
        if (m.length < 160 && !m.startsWith("{")) return m;
      }

      if (tid && j.state) return `${TASK_LABELS[tid] || tid}: ${j.state}`;
      return null;
    } catch {
      return null;
    }
  }

  if (trimmed.length > 180) return null;
  return trimmed;
}

export function mergeTaskStates(apiTasks, kestraLines, milestones, jobMeta) {
  const tm = {};
  for (const t of apiTasks || []) {
    if (t.id && t.state) tm[t.id] = t.state;
  }

  if (jobMeta?.status === "complete") tm["run-pipeline-job"] = "SUCCESS";
  else if (jobMeta?.status === "failed") tm["run-pipeline-job"] = "FAILED";
  else if (jobMeta?.status === "running") tm["run-pipeline-job"] = tm["run-pipeline-job"] || "RUNNING";

  for (const line of kestraLines || []) {
    const msg = typeof line === "string" ? line : line?.message;
    if (!msg) continue;

    const taskMatch = msg.match(/^Task ([^:]+):\s*(\S+)/);
    if (taskMatch) tm[taskMatch[1]] = taskMatch[2];

    if (msg.includes("Execution state: SUCCESS")) return { ...tm, __exec: "SUCCESS" };
    if (msg.includes("Execution state: FAILED")) return { ...tm, __exec: "FAILED" };

    if (msg.includes("Deployment complete") || msg.includes("Deploy complete")) {
      tm.done = "SUCCESS";
      tm["wait-pipeline"] = tm["wait-pipeline"] || "SUCCESS";
      tm["health-after"] = tm["health-after"] || "SUCCESS";
      tm["run-pipeline-job"] = tm["run-pipeline-job"] || "SUCCESS";
      tm.__exec = "SUCCESS";
    }
    if (msg.includes("Health check passed")) {
      tm["health-after"] = "SUCCESS";
    }

    try {
      if (msg.trim().startsWith("{")) {
        const j = JSON.parse(msg);
        const tid = j.taskId;
        if (tid && j.state) tm[tid] = j.state;
        if (j.message?.includes("Deploy complete")) tm.done = "SUCCESS";
        if (j.message?.includes("response code '200'")) tm["health-after"] = "SUCCESS";
        if (j.level === "ERROR" && tid) tm[tid] = "FAILED";
      }
    } catch {
      /* ignore */
    }
  }

  if (milestones.done) tm["run-pipeline-job"] = tm["run-pipeline-job"] || "SUCCESS";

  return tm;
}

export function resolvePhases(
  taskMap,
  execState,
  milestones,
  jobMeta,
  apiTasks,
  buildDoneAtMs,
  serverPhases
) {
  if (execState === "SUCCESS") {
    return CLIENT_PIPELINE.map((step) => ({ ...step, status: "success" }));
  }

  if (serverPhases?.length) {
    const applied = applyServerPhases(
      serverPhases,
      CLIENT_PIPELINE.map((step) => ({ ...step, status: "pending" }))
    );
    if (applied.every((p) => p.status === "success")) {
      return applied;
    }
    return applied;
  }

  const tm = taskMap;
  const job = tm["run-pipeline-job"];
  const wait = tm["wait-pipeline"];
  const health = tm["health-after"];
  const done = tm.done;
  const inferredExec = tm.__exec || execState;
  const jobPhase = jobMeta?.status;

  const tracked = (apiTasks || []).filter((t) => t.id && t.state);
  const allTasksSuccess =
    tracked.length >= 3 && tracked.every((t) => t.state === "SUCCESS");

  if (allTasksSuccess || inferredExec === "SUCCESS" || done === "SUCCESS") {
    return CLIENT_PIPELINE.map((step) => ({ ...step, status: "success" }));
  }

  if (health === "SUCCESS" && (wait === "SUCCESS" || milestones.gitPushed || jobPhase === "complete")) {
    return CLIENT_PIPELINE.map((step) => ({ ...step, status: "success" }));
  }

  // K8s build finished — Kestra runs wait-pipeline (90s) then health (matches flow YAML)
  if (buildDoneAtMs && milestones.done && jobPhase === "complete") {
    const elapsed = Date.now() - buildDoneAtMs;
    if (elapsed >= PIPELINE_DONE_MS) {
      return CLIENT_PIPELINE.map((step) => ({ ...step, status: "success" }));
    }
    if (elapsed >= GITOPS_WAIT_MS) {
      return CLIENT_PIPELINE.map((step) => ({
        ...step,
        status:
          step.id === "verify"
            ? "running"
            : step.id === "trigger" || step.id === "build" || step.id === "deploy"
              ? "success"
              : "pending",
      }));
    }
  }

  // Refresh: build logs show GitOps commit — don't rewind to ArgoCD running
  if (milestones.gitPushed && milestones.done && jobPhase === "complete") {
    if (health === "SUCCESS" || done === "SUCCESS" || wait === "SUCCESS") {
      return CLIENT_PIPELINE.map((step) => ({ ...step, status: "success" }));
    }
    return CLIENT_PIPELINE.map((step) => ({
      ...step,
      status:
        step.id === "verify"
          ? health === "RUNNING"
            ? "running"
            : "running"
          : step.id === "trigger" || step.id === "build" || step.id === "deploy"
            ? "success"
            : "pending",
    }));
  }

  const s = {};
  s.trigger = "success";

  if (job === "FAILED" || jobPhase === "failed") s.build = "failed";
  else if (job === "SUCCESS" || jobPhase === "complete" || milestones.done) s.build = "success";
  else if (job === "RUNNING" || jobPhase === "running" || milestones.kanikoStarted) s.build = "running";
  else if (wait === "SUCCESS" || wait === "RUNNING" || health || done) s.build = "success";
  else if (!job && inferredExec === "RUNNING") s.build = "running";
  else s.build = "pending";

  if (wait === "FAILED") s.deploy = "failed";
  else if (
    wait === "SUCCESS" ||
    health === "SUCCESS" ||
    health === "RUNNING" ||
    done === "SUCCESS" ||
    (milestones.gitPushed && s.build === "success")
  )
    s.deploy = "success";
  else if (s.build === "success") s.deploy = "running";
  else s.deploy = "pending";

  if (health === "FAILED" || done === "FAILED") s.verify = "failed";
  else if (health === "SUCCESS" || done === "SUCCESS") s.verify = "success";
  else if (wait === "SUCCESS" || health === "RUNNING" || milestones.gitPushed) s.verify = "running";
  else s.verify = "pending";

  if (inferredExec === "FAILED") {
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

export function progressPct(phases, execState) {
  const state = execState === "RUNNING" ? null : execState;
  if (state === "SUCCESS") return 100;
  const weights = { success: 1, running: 0.6, pending: 0, failed: 0 };
  const score = phases.reduce((a, p) => a + (weights[p.status] ?? 0), 0);
  const pct = Math.round((score / phases.length) * 100);
  if (state === "FAILED") return Math.min(pct, 95);
  return Math.min(pct, 99);
}

export function buildLiveFeed(kestraLines, jobLogs, apiTasks, execState, jobMeta) {
  const seen = new Set();
  const out = [];

  function add(text, kind = "info") {
    if (!text || seen.has(text)) return;
    seen.add(text);
    out.push({ text, kind });
  }

  if (execState && execState !== "RUNNING") {
    add(`Pipeline ${execState.toLowerCase()}`, execState === "SUCCESS" ? "ok" : "error");
  }

  for (const t of apiTasks || []) {
    const name = TASK_LABELS[t.id] || t.id;
    if (t.state) add(`${name}: ${t.state}`, "task");
  }

  for (const line of kestraLines || []) {
    const human = humanizeKestraLine(line);
    if (human) add(human, "kestra");
  }

  if (jobMeta?.hint) add(jobMeta.hint, "muted");
  if (jobMeta?.error) add(`⚠ ${jobMeta.error}`, "error");
  else if (jobMeta?.status === "pending") add("Waiting for pipeline job to start…", "muted");
  else if (jobMeta?.status === "running" && !jobLogs) add("Build job running — fetching logs…", "muted");
  else if (jobMeta?.job && jobMeta?.status) add(`Job ${jobMeta.job}: ${jobMeta.status}`, "info");

  for (const line of pickBuildLogLines(jobLogs)) {
    add(line, "build");
  }

  return out.slice(-40);
}

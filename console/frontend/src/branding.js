/** Client-facing copy — no vendor branding, no duplication with run page */

export const COMPANY_NAME = "Enlight Lab";
export const APP_NAME = "Enlight Lab";
export const CONSOLE_VERSION = "v23";

export const HOME_STEPS = [
  {
    step: "1",
    title: "Trigger the pipeline",
    body: "One click starts orchestration — build, deploy, and verify.",
  },
  {
    step: "2",
    title: "Watch it live",
    body: "Animated horizontal progress and logs update in real time.",
  },
  {
    step: "3",
    title: "GitOps deploys automatically",
    body: "The manifest is committed to GitHub and synced to Kubernetes.",
  },
  {
    step: "4",
    title: "Client sees the result",
    body: "The demo app updates with a page proving the deployment worked.",
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

export function parseLogMilestones(logs) {
  const text = logs || "";
  return {
    cloned: /Clone GitHub|Cloning into/.test(text),
    gitPushed: /deploy:.*\[kestra pipeline\]|GitOps commit/.test(text),
    kanikoStarted: /Kaniko build/.test(text),
    imagePushed: /Pushed ap-mumbai|DONE ap-mumbai/.test(text),
    done: /DONE ap-mumbai/.test(text),
    failed: /git: not found|ERROR:|Failed/.test(text),
  };
}

export function filterClientLogs(logs) {
  if (!logs) return [];
  const keep = [
    /^==>/,
    /Clone GitHub|Cloning into/,
    /GitOps commit/,
    /\[main /,
    /deploy:/,
    /Kaniko build/,
    /^DONE /,
    /ERROR|Failed/i,
    /git: not found/,
  ];
  return logs
    .split("\n")
    .map((l) => l.trimEnd())
    .filter((line) => line && keep.some((re) => re.test(line)))
    .slice(-30);
}

/** Turn Kestra log line (JSON or text) into a client-friendly string — never raw JSON. */
export function humanizeKestraLine(raw) {
  const msg = typeof raw === "string" ? raw : raw?.message;
  if (!msg || typeof msg !== "string") return null;

  const trimmed = msg.trim();
  if (!trimmed) return null;

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

export function resolvePhases(taskMap, execState, milestones, jobMeta) {
  const tm = taskMap;
  const job = tm["run-pipeline-job"];
  const wait = tm["wait-pipeline"];
  const health = tm["health-after"];
  const done = tm.done;
  const inferredExec = tm.__exec || execState;
  const jobPhase = jobMeta?.status;

  if (inferredExec === "SUCCESS" || done === "SUCCESS") {
    return CLIENT_PIPELINE.map((step) => ({ ...step, status: "success" }));
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
  else if (wait === "SUCCESS" || health === "SUCCESS" || health === "RUNNING" || done === "SUCCESS")
    s.deploy = "success";
  else if (s.build === "success") s.deploy = "running";
  else s.deploy = "pending";

  if (health === "FAILED" || done === "FAILED") s.verify = "failed";
  else if (health === "SUCCESS" || done === "SUCCESS") s.verify = "success";
  else if (wait === "SUCCESS" || health === "RUNNING") s.verify = "running";
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

export function buildLiveFeed(kestraLines, jobLogs, apiTasks, execState) {
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

  for (const line of filterClientLogs(jobLogs)) {
    add(line, "build");
  }

  return out.slice(-35);
}

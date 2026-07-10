/** Client-facing copy — no vendor branding, no duplication with run page */

export const COMPANY_NAME = "Enlight Lab";
export const APP_NAME = "Enlight Lab";
export const CONSOLE_VERSION = "v21";

export const HOME_STEPS = [
  {
    step: "1",
    title: "Trigger the pipeline",
    body: "One click starts Kestra — orchestration, build, deploy, and verify.",
  },
  {
    step: "2",
    title: "Watch it live",
    body: "Animated progress and build logs show exactly what is happening.",
  },
  {
    step: "3",
    title: "GitOps deploys automatically",
    body: "The new image is committed to GitHub and synced to Kubernetes.",
  },
  {
    step: "4",
    title: "Client sees the result",
    body: "The demo app updates with a visual page proving the deployment worked.",
  },
];

export const CLIENT_PIPELINE = [
  {
    id: "trigger",
    kestraTasks: [],
    label: "Pipeline started",
    clientLine: "Kestra received your deploy request and scheduled the build job.",
    icon: "1",
  },
  {
    id: "build",
    kestraTasks: ["run-pipeline-job"],
    label: "Build & push image",
    clientLine: "Kaniko clones code, commits GitOps, builds the container, and pushes to the registry.",
    icon: "2",
  },
  {
    id: "deploy",
    kestraTasks: ["wait-pipeline"],
    label: "Deploy via GitOps",
    clientLine: "ArgoCD syncs the Git commit and rolls out the new version on Kubernetes.",
    icon: "3",
  },
  {
    id: "verify",
    kestraTasks: ["health-after", "done"],
    label: "Health verified",
    clientLine: "The pipeline confirms the live app responds successfully.",
    icon: "4",
  },
];

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
    /Pushed ap-mumbai|pushed blob|Pushing/,
    /^DONE /,
    /ERROR|error|Failed/i,
    /git: not found/,
    /INFO\[/,
    /Executing/,
  ];
  return logs
    .split("\n")
    .map((l) => l.trimEnd())
    .filter((line) => line && keep.some((re) => re.test(line)))
    .slice(-40);
}

const TASK_LABELS = {
  "run-pipeline-job": "Build job",
  "wait-pipeline": "GitOps sync wait",
  "health-after": "Health check",
  done: "Complete",
};

export function buildLiveFeed(kestraLines, jobLogs, tasks) {
  const seen = new Set();
  const out = [];

  function add(text, kind = "info") {
    const key = `${kind}:${text}`;
    if (!text || seen.has(key)) return;
    seen.add(key);
    out.push({ text, kind });
  }

  for (const line of kestraLines || []) {
    const msg = typeof line === "string" ? line : line.message;
    if (msg) add(msg, "kestra");
  }

  for (const t of tasks || []) {
    const name = TASK_LABELS[t.id] || t.id;
    const st = t.state || "?";
    add(`${name}: ${st}${t.duration ? ` (${t.duration})` : ""}`, "task");
  }

  for (const line of filterClientLogs(jobLogs)) {
    add(line, "build");
  }

  return out.slice(-45);
}

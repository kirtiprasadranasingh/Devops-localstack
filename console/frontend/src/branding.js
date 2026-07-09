/** Enlight Lab — company UI (matches selfheal.enlightlab.com) */

export const DOMAIN_BASE = "devopslocalstack.enlightlab.com";
export const COMPANY_NAME = "Enlight Lab";
export const APP_NAME = "EnlightLab";
export const APP_TAGLINE = "Unified DevOps Platform";
export const PLATFORM_SUBTITLE = "Oracle OKE · GitOps Delivery";

export const PATHS = {
  console: "/",
  app: "/app",
  gitops: "/gitops",
  metrics: "/metrics",
};

export function buildHosts(baseUrl) {
  const base = baseUrl.replace(/\/$/, "");
  try {
    const u = new URL(base);
    return {
      console: `${base}${PATHS.console}`,
      app: `${u.protocol}//app.${u.host}`,
      kestra: `${u.protocol}//kestra.${u.host}`,
      gitops: `${u.protocol}//argocd.enlightlab.com`,
      metrics: `${u.protocol}//metrics.${u.host}`,
    };
  } catch {
    return {
      console: `${base}${PATHS.console}`,
      app: `${base}${PATHS.app}`,
      kestra: `${base}/ui`,
      gitops: "https://argocd.enlightlab.com",
      metrics: `${base}${PATHS.metrics}`,
    };
  }
}

export const HOSTS = buildHosts(`https://${DOMAIN_BASE}`);

export const TOOL_CHIPS_CLOUD = ["Kestra", "Dagger", "OCIR", "ArgoCD", "Oracle OKE"];
export const TOOL_CHIPS_LOCAL = ["Kestra", "Dagger", "Dokploy", "Local registry"];

export const STACK_LOCAL = [
  {
    id: "orchestrate",
    title: "Run pipelines",
    tool: "Kestra",
    description: "Starts the full local workflow from one button.",
    action: "Open Kestra",
    linkKey: "kestra",
    icon: "⚡",
  },
  {
    id: "build",
    title: "Build code",
    tool: "Dagger",
    description: "Builds your app image from GitHub inside the Kestra flow.",
    action: "Open Kestra",
    linkKey: "kestra",
    icon: "📦",
  },
  {
    id: "deploy",
    title: "Ship to servers",
    tool: "Dokploy",
    description: "Pulls the new image and restarts the local app.",
    action: "Open Dokploy",
    linkKey: "gitops",
    icon: "🚀",
  },
  {
    id: "observe",
    title: "Watch health",
    tool: "Netdata",
    description: "Live metrics while the pipeline runs.",
    action: "Open metrics",
    linkKey: "netdata",
    icon: "📊",
  },
];

export const STACK_CLOUD = [
  {
    id: "orchestrate",
    title: "Orchestrate",
    tool: "Kestra",
    description: "Runs the full delivery pipeline from one button click.",
    action: "Open Kestra",
    linkKey: "kestra",
    icon: "⚡",
  },
  {
    id: "build",
    title: "Build image",
    tool: "Dagger",
    description: "Builds the FastAPI app from GitHub inside the Kestra workflow.",
    action: "Open Kestra",
    linkKey: "kestra",
    icon: "📦",
  },
  {
    id: "registry",
    title: "Store image",
    tool: "Oracle OCIR",
    description: "Private container registry on Oracle Cloud Infrastructure.",
    action: "Open OCIR",
    linkKey: "registry",
    icon: "🏷️",
  },
  {
    id: "deploy",
    title: "GitOps deploy",
    tool: "ArgoCD",
    description: "Syncs the updated manifest from GitHub to Oracle OKE.",
    action: "Open ArgoCD",
    linkKey: "gitops",
    icon: "🔄",
  },
];

export const PIPELINE_CLOUD = [
  { n: 1, icon: "▶️", title: "Trigger", body: "Console starts Kestra oke-dagger-gitops-pipeline." },
  { n: 2, icon: "📦", title: "Dagger build", body: "Clone GitHub → build image → push to OCIR." },
  { n: 3, icon: "🔄", title: "GitOps", body: "Update manifest in Git → ArgoCD syncs to OKE." },
  { n: 4, icon: "✅", title: "Verified", body: "Health check proves the live app at app.<host>." },
];

export const PIPELINE_LOCAL = [
  { n: 1, icon: "▶️", title: "Run demo", body: "Kestra starts dagger-dokploy-pipeline." },
  { n: 2, icon: "📦", title: "Dagger build", body: "Clone → build → push to registry." },
  { n: 3, icon: "🚀", title: "Dokploy deploy", body: "Webhook restarts the app." },
  { n: 4, icon: "✅", title: "Health", body: "Pipeline confirms /health is OK." },
];

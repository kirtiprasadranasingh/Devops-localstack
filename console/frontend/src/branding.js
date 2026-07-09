/** Enlight Lab platform console */

export const DOMAIN_BASE = "devopslocalstack.enlightlab.com";
export const COMPANY_NAME = "Enlight Lab";
export const APP_NAME = "Enlight Lab";
export const APP_TAGLINE = "Open-source DevOps platform";

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
      gitops: `${u.protocol}//gitops.${u.host}`,
      metrics: `${u.protocol}//metrics.${u.host}`,
    };
  } catch {
    return {
      console: `${base}${PATHS.console}`,
      app: `${base}${PATHS.app}`,
      kestra: `${base}/ui`,
      gitops: `${base}${PATHS.gitops}`,
      metrics: `${base}${PATHS.metrics}`,
    };
  }
}

export const HOSTS = buildHosts(`https://${DOMAIN_BASE}`);

export const INGRESS_ROUTES = [
  { path: "/", service: "Enlight Lab console" },
  { path: "app.<host>", service: "Demo web application" },
  { path: "kestra.<host>", service: "Kestra pipelines" },
  { path: "gitops.<host>", service: "ArgoCD GitOps" },
  { path: "metrics.<host>", service: "Grafana monitoring" },
];

export const STACK_LOCAL = [
  {
    id: "orchestrate",
    title: "Run pipelines",
    tool: "Kestra",
    description: "Automates build, test, and deploy steps from one place.",
    action: "Open Kestra →",
    linkKey: "kestra",
  },
  {
    id: "build",
    title: "Build code",
    tool: "Dagger + Registry",
    description: "Builds your app from GitHub and stores the image in a registry.",
    action: "View registry →",
    linkKey: "registry",
  },
  {
    id: "deploy",
    title: "Ship to servers",
    tool: "Dokploy",
    description: "Deploys the new image and restarts the app automatically.",
    action: "Open Dokploy →",
    linkKey: "gitops",
  },
  {
    id: "observe",
    title: "Watch health",
    tool: "Metrics + health checks",
    description: "Confirms the app is live with real-time health and metrics.",
    action: "Open metrics →",
    linkKey: "netdata",
  },
];

export const STACK_CLOUD = [
  {
    id: "orchestrate",
    title: "Run pipelines",
    tool: "Kestra",
    description: "Automates health checks, rollouts, and full build pipelines on Kubernetes.",
    action: "Open Kestra →",
    linkKey: "kestra",
  },
  {
    id: "build",
    title: "Store images",
    tool: "OCIR registry",
    description: "Private container registry on Oracle Cloud for your application builds.",
    action: "Open registry →",
    linkKey: "registry",
  },
  {
    id: "deploy",
    title: "Ship with GitOps",
    tool: "ArgoCD",
    description: "Deploy from Git to Kubernetes at gitops.<host> — declarative, auditable releases.",
    action: "Open GitOps →",
    linkKey: "gitops",
  },
  {
    id: "observe",
    title: "Live demo app",
    tool: "FastAPI + Grafana",
    description: "Running demo app plus Grafana dashboards at metrics.<host> when monitoring is installed.",
    action: "Open demo app →",
    linkKey: "application",
  },
];

export const PIPELINE_CLOUD = [
  {
    n: 1,
    title: "You click Run demo",
    body: "Console tells Kestra to start the configured workflow — one button, full visibility.",
  },
  {
    n: 2,
    title: "Health check (before)",
    body: "Kestra confirms the demo app is healthy before any change.",
  },
  {
    n: 3,
    title: "Rollout on Kubernetes",
    body: "Kestra restarts the FastAPI deployment in enlight-staging and waits for rollout.",
  },
  {
    n: 4,
    title: "Health check (after)",
    body: "Pipeline verifies the app is still healthy — green means the demo succeeded.",
  },
];

export const PIPELINE_LOCAL = [
  {
    n: 1,
    title: "You click Run demo",
    body: "Kestra starts the full pipeline from this console.",
  },
  {
    n: 2,
    title: "Code is built",
    body: "Dagger builds the app image from GitHub.",
  },
  {
    n: 3,
    title: "App is deployed",
    body: "Dokploy pulls the image and restarts the service.",
  },
  {
    n: 4,
    title: "Health check passes",
    body: "The pipeline calls /health to confirm the app is live.",
  },
];

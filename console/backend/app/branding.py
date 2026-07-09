# Enlight Lab platform — subdomains for kestra, app, gitops, metrics.

DOMAIN_BASE = "devopslocalstack.enlightlab.com"
COMPANY_NAME = "Enlight Lab"
APP_NAME = "Enlight Lab"
APP_TAGLINE = "Open-source DevOps platform"

SELFHEAL_APP_URL = "https://selfheal.enlightlab.com/staging"

PATHS = {
    "console": "/",
    "app": "/app",
}


def build_hosts(base_url: str) -> dict[str, str]:
    base = base_url.rstrip("/")
    if base_url.startswith("http://"):
        host = base_url.replace("http://", "").split("/")[0]
        scheme = "http"
    elif base_url.startswith("https://"):
        host = base_url.replace("https://", "").split("/")[0]
        scheme = "https"
    else:
        host = ""
        scheme = "https"
    if host and "." in host:
        kestra = f"{scheme}://kestra.{host}"
        app = f"{scheme}://app.{host}"
        gitops = f"{scheme}://gitops.{host}"
        metrics = f"{scheme}://metrics.{host}"
    else:
        kestra = f"{base}/ui" if base else "/ui"
        app = f"{base}{PATHS['app']}"
        gitops = f"{base}/gitops"
        metrics = f"{base}/metrics"
    return {
        "console": f"{base}{PATHS['console']}",
        "app": app,
        "app_external": SELFHEAL_APP_URL,
        "kestra": kestra,
        "gitops": gitops,
        "metrics": metrics,
    }


HOSTS = build_hosts(f"https://{DOMAIN_BASE}")

INGRESS_ROUTES = [
    {"path": "/", "service": "Enlight Lab console"},
    {"path": "app.<host>", "service": "Demo web application"},
    {"path": "kestra.<host>", "service": "Kestra pipelines"},
    {"path": "gitops.<host>", "service": "ArgoCD GitOps"},
    {"path": "metrics.<host>", "service": "Grafana monitoring"},
]

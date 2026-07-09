from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

from .branding import APP_NAME, HOSTS, build_hosts


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = APP_NAME
    public_base_url: str = ""
    kestra_public_url: str = ""
    gitops_public_url: str = ""
    kestra_url: str = "http://host.docker.internal:8085"
    dokploy_url: str = "http://host.docker.internal:3000"
    registry_url: str = "http://host.docker.internal:5000"
    netdata_url: str = "http://host.docker.internal:19999"
    app_health_url: str = "http://host.docker.internal:8000/health"
    kestra_namespace: str = "platform"
    kestra_flow_id: str = "dagger-dokploy-pipeline"
    kestra_username: str = ""
    kestra_password: str = ""
    github_repo: str = "https://github.com/kirtiprasadranasingh/Devops-localstack"
    mode: str = "local"  # local | oke

    @model_validator(mode="after")
    def apply_oke_defaults(self) -> "Settings":
        if self.mode.lower() != "oke":
            return self
        if "host.docker.internal" in self.kestra_url:
            self.kestra_url = "http://kestra.enlight-platform.svc.cluster.local:8080"
        if "host.docker.internal" in self.dokploy_url:
            self.dokploy_url = build_hosts(self.public_base_url or "https://devopslocalstack.enlightlab.com")["gitops"]
        if "host.docker.internal" in self.registry_url:
            self.registry_url = "https://ap-mumbai-1.ocir.io"
        if "host.docker.internal" in self.netdata_url:
            base = self.public_base_url or ""
            self.netdata_url = f"{base.rstrip('/')}/metrics" if base else "/metrics"
        if "host.docker.internal" in self.app_health_url:
            self.app_health_url = (
                "http://fastapi.enlight-staging.svc.cluster.local/health"
            )
        if self.kestra_namespace == "platform":
            self.kestra_namespace = "main"
        if self.kestra_flow_id == "dagger-dokploy-pipeline":
            self.kestra_flow_id = "oke-deploy-simple"
        return self

    @property
    def gitops_url(self) -> str:
        """ArgoCD UI — shared cluster ingress or nip.io subdomain."""
        if self.gitops_public_url:
            return self.gitops_public_url.rstrip("/")
        return self.hosts["gitops"]

    @property
    def hosts(self) -> dict[str, str]:
        if self.public_base_url:
            h = build_hosts(self.public_base_url)
            if self.gitops_public_url:
                h = {**h, "gitops": self.gitops_public_url.rstrip("/")}
            return h
        return HOSTS

    @property
    def kestra_ui_base(self) -> str:
        """Absolute Kestra UI root, e.g. http://kestra.144-24-100-85.nip.io"""
        if self.kestra_public_url:
            return self.kestra_public_url.rstrip("/")
        base = self.hosts["kestra"].rstrip("/")
        if base.endswith("/ui"):
            return base[: -len("/ui")]
        return base

    def kestra_execution_url(self, execution_id: str, flow_id: str | None = None) -> str:
        fid = flow_id or self.kestra_flow_id
        return (
            f"{self.kestra_ui_base}/ui/executions/"
            f"{self.kestra_namespace}/{fid}/{execution_id}"
        )

    def kestra_flow_url(self) -> str:
        return (
            f"{self.kestra_ui_base}/ui/flows/"
            f"{self.kestra_namespace}/{self.kestra_flow_id}"
        )

    @property
    def app_public_url(self) -> str:
        if self.mode.lower() == "oke":
            return self.hosts["app"]
        return self.app_health_url.replace("/health", "")

    @property
    def flow_description(self) -> str:
        descriptions = {
            "oke-health-check": "Health check only — proves console → Kestra → app.",
            "oke-deploy-simple": "Health check → rollout restart → health check.",
            "oke-deploy-pipeline": "Git clone → Kaniko build → OCIR push → rollout.",
            "dagger-dokploy-pipeline": "Local: Dagger build → Dokploy deploy.",
        }
        return descriptions.get(self.kestra_flow_id, "Kestra workflow")


settings = Settings()

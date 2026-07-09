"""Dagger pipeline: build image -> push registry -> optional Dokploy deploy (local)."""

import json

import dagger
from dagger import dag, function, object_type, Secret


@object_type
class MinimalPipeline:
    @function
    async def build_and_publish(
        self,
        registry: str,
        image: str = "fastapi-minimal",
        tag: str = "latest",
    ) -> str:
        """Build the app Dockerfile from repo root and push to registry."""
        source = dag.current_workspace().directory("..")
        image_ref = f"{registry.rstrip('/')}/{image}:{tag}"
        published = await source.docker_build(dockerfile="Dockerfile").publish(image_ref)
        return f"Pushed {published}"

    @function
    async def deploy_dokploy(
        self,
        dokploy_url: str,
        dokploy_token: Secret,
        application_id: str,
    ) -> str:
        """Trigger Dokploy application.deploy via API."""
        token = await dokploy_token.plaintext()
        payload = json.dumps(
            {
                "applicationId": application_id,
                "title": "Dagger pipeline deploy",
                "description": "Triggered from Kestra minimal PoC",
            }
        )
        return await (
            dag.container()
            .from_("curlimages/curl:8.8.0")
            .with_exec(
                [
                    "curl",
                    "-fsS",
                    "-X",
                    "POST",
                    f"{dokploy_url.rstrip('/')}/api/application.deploy",
                    "-H",
                    f"Authorization: Bearer {token}",
                    "-H",
                    "Content-Type: application/json",
                    "-d",
                    payload,
                ]
            )
            .stdout()
        )

    @function
    async def minimal_pipeline(
        self,
        registry: str,
        image: str = "fastapi-minimal",
        tag: str = "latest",
        dokploy_url: str = "",
        dokploy_token: Secret | None = None,
        application_id: str = "",
    ) -> str:
        """Full PoC pipeline: build/push then Dokploy deploy."""
        results: list[str] = []

        results.append(await self.build_and_publish(registry=registry, image=image, tag=tag))

        if dokploy_url and dokploy_token and application_id:
            deploy_out = await self.deploy_dokploy(
                dokploy_url=dokploy_url,
                dokploy_token=dokploy_token,
                application_id=application_id,
            )
            results.append(f"Dokploy: {deploy_out.strip()}")
        else:
            results.append("Skipped Dokploy deploy (missing url/token/app id)")

        return "\n".join(results)

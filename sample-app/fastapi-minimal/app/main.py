from fastapi import FastAPI

app = FastAPI(title="fastapi-minimal-poc")


@app.get("/")
def root() -> dict[str, str]:
    return {"message": "FastAPI PoC is running"}


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}

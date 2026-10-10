"""Sample service built and shipped by the platform-lab pipeline."""
import os

from fastapi import FastAPI

app = FastAPI(title="lab-api")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/api/info")
def info() -> dict:
    return {
        "service": "lab-api",
        "version": os.getenv("APP_VERSION", "dev"),
        "environment": os.getenv("APP_ENV", "local"),
        "department": "IT",
    }

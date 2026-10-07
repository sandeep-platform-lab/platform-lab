# Base image is a build arg so CI can pull it through Artifactory (lab-docker remote cache).
ARG BASE_IMAGE=python:3.14-slim

# Build stage: install dependencies into an isolated virtualenv
FROM ${BASE_IMAGE} AS build
WORKDIR /app
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt \
 && /venv/bin/pip uninstall -y pip

# Runtime stage: no build tools, no package manager, non-root user
FROM ${BASE_IMAGE}
ENV PATH="/venv/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN python -m pip uninstall -y pip \
 && useradd --uid 10001 --no-create-home app
WORKDIR /app
COPY --from=build /venv /venv
COPY src/ src/
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]

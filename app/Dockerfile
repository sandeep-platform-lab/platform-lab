# Base image is a build arg so CI can pull it through Artifactory (lab-docker remote cache).
ARG BASE_IMAGE=python:3.14-slim

# Build stage: install dependencies into an isolated virtualenv
FROM ${BASE_IMAGE} AS build
WORKDIR /app
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt \
 && /venv/bin/pip uninstall -y pip

# Runtime filesystem: base image without pip, plus the app.
# ensurepip ships a complete pip wheel (with vendored urllib3, setuptools, ...); the app never
# creates virtualenvs at runtime, so it goes too.
FROM ${BASE_IMAGE} AS runtime-fs
RUN python -m pip uninstall -y pip \
 && rm -rf /usr/local/lib/python3.*/ensurepip \
 && useradd --uid 10001 --no-create-home app
COPY --from=build /venv /venv
COPY src/ /app/src/

# Final image: the runtime filesystem flattened into ONE layer.
# Deleting files in a later layer only hides them; the base layer still ships them, and layer-aware
# scanners like Xray (rightly) report them. Flattening removes pip and its vendored packages for real.
FROM scratch
COPY --from=runtime-fs / /
ENV PATH="/venv/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1
WORKDIR /app
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]

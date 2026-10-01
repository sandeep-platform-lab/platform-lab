# Build stage: install dependencies into an isolated virtualenv
FROM python:3.14-slim AS build
WORKDIR /app
RUN python -m venv /venv
COPY requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# Runtime stage: no build tools, non-root user
FROM python:3.14-slim
ENV PATH="/venv/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd --uid 10001 --no-create-home app
WORKDIR /app
COPY --from=build /venv /venv
COPY src/ src/
USER 10001
EXPOSE 8000
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]

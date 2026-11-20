FROM python:3.12-slim-bookworm
RUN apt-get update && apt-get install -y --no-install-recommends ruby ruby-webrick nginx curl ca-certificates tesseract-ocr tesseract-ocr-eng && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir Pillow==11.3.0
WORKDIR /app
COPY . /app
ENV SYSTEM_BUDGET=1 PYTHONPATH=/app/deploy PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 USAGE_DB=/data/usage.sqlite3 BUDGET_CONFIG=/app/deploy/budget.json
RUN chmod +x deploy/image_probe.py deploy/ocr.py && mkdir -p /data module-two-candidate/bridge-jobs module-two-candidate/live-attempts module-three/data product-retouch/data
HEALTHCHECK --interval=30s --timeout=15s --start-period=30s --retries=3 CMD ["python3", "deploy/healthcheck.py"]
CMD ["python3", "deploy/supervise.py"]

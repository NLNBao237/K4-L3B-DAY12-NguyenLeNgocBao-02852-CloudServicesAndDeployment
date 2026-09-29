# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (production-ready)
#
#   - Multi-stage: `builder` cài dependency, `runtime` chỉ nhận kết quả
#   - Base image slim
#   - requirements.txt + pip install TRƯỚC khi copy source (tận dụng cache)
#   - Chạy bằng user thường (appuser), không phải root
#   - HEALTHCHECK gọi /health
#   - Cổng đọc từ $PORT (cloud tự gán)
#
# Kiểm tra:  pytest tests/test_cp2.py -v
# Build thử: docker build -t day12-agent:prod .
# ═══════════════════════════════════════════════════════════════════

# ---------- Stage 1: builder — cài thư viện vào /install ----------
FROM python:3.11-slim AS builder

WORKDIR /build

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- Stage 2: runtime — chỉ mang theo kết quả ----------
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

RUN useradd --create-home --uid 10001 appuser

COPY --from=builder /install /usr/local

COPY --chown=appuser:appuser app ./app
COPY --chown=appuser:appuser utils ./utils

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.getenv('PORT', '8000') + '/health', timeout=3)" || exit 1

# `exec` để uvicorn là PID 1 và nhận SIGTERM trực tiếp (graceful shutdown ở CP4)
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

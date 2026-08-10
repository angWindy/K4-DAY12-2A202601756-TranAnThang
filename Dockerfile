# ═══════════════════════════════════════════════════════════════════
# CP2 — Containerization (multi-stage, non-root, healthcheck)
#
# Stage 1 (`builder`) cài dependency vào /install.
# Stage 2 (runtime) chỉ copy kết quả từ /install + source code → image
# nhỏ, không mang theo compiler hay pip cache.
#
# Thứ tự layer quan trọng: requirements.txt + pip install đặt TRƯỚC
# COPY source. Nhờ đó Docker cache giữ được lớp pip install — sửa code
# không phải cài lại thư viện.
# ═══════════════════════════════════════════════════════════════════

# ---- Stage 1: Builder ----
FROM python:3.11-slim AS builder
WORKDIR /build

# Chỉ copy requirements.txt trước để layer pip install được cache
COPY requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---- Stage 2: Production runtime ----
FROM python:3.11-slim

WORKDIR /app

# Copy dependency đã cài sẵn từ stage builder
COPY --from=builder /install /usr/local

# Sau khi đã copy dependency → copy source code (ít thay đổi cache)
COPY app/ app/
COPY utils/ utils/

# Chạy dưới quyền user thường — không phải root
# --gecos "" tránh useradd hỏi GECOS field khi build không tương tác
RUN useradd --create-home --shell /bin/bash appuser
USER appuser

EXPOSE 8000

# Health check dùng Python (image slim không có curl, đọc PORT động)
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import os, urllib.request; port = os.getenv('PORT', '8000'); urllib.request.urlopen(f'http://127.0.0.1:{port}/healthz', timeout=3)"

# Sử dụng shell form để expand biến $PORT khi chạy trên cloud
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]

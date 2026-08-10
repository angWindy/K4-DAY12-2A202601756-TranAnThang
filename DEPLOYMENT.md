# Thông Tin Deploy — Checkpoint 5

> Điền file này sau khi deploy xong. `pytest tests/test_cp5.py` đọc file này
> để tìm địa chỉ service của bạn và gọi thử.
>
> **Chỉ ghi TÊN biến môi trường, tuyệt đối không dán giá trị token vào đây.**
> Repo này công khai — dán token vào là mất token.

## Thông Tin Học Viên

| Mục | Nội dung |
|-----|----------|
| Họ và tên | Trần An Thắng |
| Mã học viên | 2A202601756 |
| Repo | https://github.com/angwindy/K4-DAY12-2A202601756-TranAnThang |

## Service

| Mục | Nội dung |
|-----|----------|
| Public URL | https://k4-day12-2a202601756-trananthang.onrender.com |
| Platform | Render |
| Ngày deploy | 2026-08-10 |

## Biến Môi Trường Đã Set Trên Cloud

Ghi tên biến và **nguồn giá trị**, không ghi giá trị:

| Biến | Đã set | Ghi chú |
|------|--------|---------|
| `PORT` | ✅ | Set trong render.yaml, giá trị 10000 |
| `API_TOKEN` | ✅ | Set trong Render dashboard, lấy từ OpenAI |
| `REDIS_URL` | ✅ | Redis add-on của Render (redis://red-xxx:6379) |
| `BUCKET_CAPACITY` | ✅ | 10, set trong render.yaml |
| `REFILL_PER_MINUTE` | ✅ | 10, set trong render.yaml |
| `DAILY_BUDGET_USD` | ✅ | 1.0, set trong render.yaml |
| `LOG_LEVEL` | ✅ | INFO, set trong render.yaml |

## Lệnh Kiểm Tra

Thay `<URL>` bằng Public URL ở trên:

```bash
# 1. Liveness — mong đợi 200 {"status":"ok"}
curl -i <URL>/healthz

# 2. Readiness — mong đợi 200 {"status":"ready"} (đã nối được Redis)
curl -i <URL>/readyz

# 3. Không có token — mong đợi 401 kèm header WWW-Authenticate
curl -i -X POST <URL>/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"Hello"}'

# 4. Có token — mong đợi 200 kèm câu trả lời
curl -i -X POST <URL>/chat \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H "X-Client-Id: sv-test" \
  -d '{"message":"Deploy là gì?"}'

# 5. Rate limit — gọi 15 lần, những lần cuối phải trả 429
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "%{http_code} " -X POST <URL>/chat \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "X-Client-Id: sv-test" \
    -d '{"message":"test"}'
done; echo
```

## Kết Quả Chạy Thật

Dán output của các lệnh trên vào đây:

```
=== 1. Liveness /healthz ===
{"status":"ok","service":"day12-chat-service","version":"1.0.0"}
HTTP: 200

=== 2. Readiness /readyz ===
{"status":"ready","redis":true}
HTTP: 200

=== 3. Khong co token (401) ===
{"detail":"invalid or missing bearer token"}
HTTP: 401

=== 4. Co token (200) ===
{"reply":"Ngắn gọn: Deploy la gi phụ thuộc vào ba yếu tố — cấu hình qua biến môi trường, health check để orchestrator biết trạng thái, và giới hạn tài nguyên.","client_id":"sv-test","turns_before":2,"usd_cost":3.435e-05,"usage":{"prompt":41,"completion":47}}
HTTP: 200

=== 5. Rate limit (15 requests) ===
200 200 200 200 200 200 200 200 200 429 429 429 429 429 429
```

**Kết quả:**
- ✅ `/healthz` → 200 (service sống)
- ✅ `/readyz` → 200 + Redis connected
- ✅ `/chat` không token → 401 (đúng behavior)
- ✅ `/chat` có token → 200 + reply
- ✅ Rate limit → 10 request thành công, 5 request cuối trả 429

## Ảnh Chụp Màn Hình

Đặt ảnh trong thư mục `screenshots/`:

- `screenshots/dashboard.png` — trang quản lý service trên platform
- `screenshots/healthz.png` — kết quả gọi `/healthz` từ trình duyệt hoặc curl

---

## Hướng Dẫn Truy Cập Endpoint Để Chụp Screenshot

### Cách 1: Dùng Trình Duyệt (Chrome/Firefox)

1. **Mở trình duyệt**
2. **Truy cập các URL sau** (thay `k4-day12-2a202601756-trananthang.onrender.com` bằng URL của bạn):

| Endpoint | URL |
|----------|-----|
| `/healthz` | `https://k4-day12-2a202601756-trananthang.onrender.com/healthz` |
| `/readyz` | `https://k4-day12-2a202601756-trananthang.onrender.com/readyz` |

3. **Chụp ảnh màn hình** (Ctrl+Shift+S trên Windows/Linux, Cmd+Shift+S trên Mac)

### Cách 2: Dùng cURL trong Terminal

```bash
# Endpoint 1: /healthz
curl -s https://k4-day12-2a202601756-trananthang.onrender.com/healthz

# Endpoint 2: /readyz
curl -s https://k4-day12-2a202601756-trananthang.onrender.com/readyz
```

Copy output vào file hoặc chụp ảnh terminal.

### Cách 3: Dùng Postman/Thunder Client (VS Code)

1. Tạo request mới
2. Method: `GET`
3. URL: `https://k4-day12-2a202601756-trananthang.onrender.com/healthz`
4. Send → Chụp ảnh response panel

### Cách 4: Dùng Browser DevTools

1. Mở trình duyệt → F12 (DevTools)
2. Tab **Console**
3. Gõ:
   ```javascript
   fetch('https://k4-day12-2a202601756-trananthang.onrender.com/healthz')
     .then(r => r.json())
     .then(console.log)
   ```
4. Kết quả hiện trong Console → Chụp ảnh

---

### Kết Quả Mong Đợi

| Endpoint | Response |
|----------|----------|
| `/healthz` | `{"status":"ok","service":"day12-chat-service","version":"1.0.0"}` |
| `/readyz` | `{"status":"ready","redis":true}` |

---

## Lưu Ý Quan Trọng

- **Không dùng phương án dự phòng** - đã deploy thành công lên Render
- Service đã hoạt động với đầy đủ: Redis, health check, rate limit, cost guard
- Tất cả endpoint đã được verify qua test ở trên

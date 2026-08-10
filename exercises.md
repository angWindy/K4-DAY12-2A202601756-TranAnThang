# Phiếu Phản Ánh — K4 Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng `> *Câu trả lời của bạn*` bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Trần An Thắng  Mã học viên: 2A202601756

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `api_token` không có giá trị mặc định nên app chết ngay khi
khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà việc
"chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> **Tình huống:** deploy lên Railway/Render lần đầu, quên set biến `API_TOKEN`
> trong dashboard. App khởi động "bình thường" (vì `api_token="changeme"` có
> default), healthz trả 200 → Railway gắn domain public cho service. Trong
> 5 phút đầu, có người (hoặc bot quét internet) gọi thử `POST /chat` với
> `Authorization: Bearer changeme` — request đi qua, cost guard đếm tiền vào
> key `"changeme"`, vài giờ sau hóa đơn OpenAI lên $200.
>
> Với `api_token` không có default, app `raise ValidationError` ngay lúc
> `Settings()` chạy trong lifespan → Railway log báo "ValidationError:
> api_token Field required" → container crash → Railway không route traffic
> tới domain public (vì health check fail liên tục) → **bạn phát hiện lỗi
> trước khi ai kịp gọi**. Fail fast biến "lỗ hổng bảo mật + cháy tiền"
> thành "lỗi deploy nhìn thấy ngay trong log".

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/chat` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Dòng log thu được khi một request `/chat` hoàn tất (sinh từ
> `emit("chat_completed", ...)` trong code):
>
> ```json
> {"event": "chat_completed", "severity": "INFO", "ts": "2026-08-10T07:43:43.373679+00:00", "client_id": "sv01", "prompt_tokens": 42, "completion_tokens": 87, "usd_cost": 0.000231}
> ```
>
> **Hai việc làm được với JSON mà `print` không làm được:**
>
> 1. **Lọc/lập dashboard theo trường có cấu trúc:** trong Grafana/CloudWatch
>    Logging tôi viết được câu query kiểu
>    `severity="ERROR" AND usd_cost > 0.5` hoặc đếm số request/giờ theo
>    `client_id`. `print("đã trả lời xong cho sv01")` thì chỉ có chuỗi
>    tự do, muốn trích `sv01` ra phải regex thủ công, dễ sai.
>
> 2. **Khoanh vùng sự cố theo latency/chi phí:** tôi chạy
>    `jq 'select(.usd_cost > 0.1)'` trên file log để tìm ra những request
>    đốt tiền bất thường, hoặc alert nếu trung bình `usd_cost` của một
>    `client_id` tăng đột biến. Với `print` phải mở từng file log, mắt
>    thường không phân biệt được "đã trả lời xong" với "đã trả lời xong
>    tốn $5".

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t chat:single .
docker build -t chat:multi .
docker images | grep chat
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1730 MB (1.73 GB) |
| Multi-stage | 270 MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Phần chênh ~1.46 GB chủ yếu là những thứ **build-time** mà image runtime
> không cần:
>
> 1. **Base image `python:3.11` (đầy đủ)** thay vì `python:3.11-slim`: bản
>    đầy đủ chứa `gcc`, `g++`, `make`, `libc-dev`, header files, `apt` indexes,
>    doc, locales — tổng cộng ~600-700 MB so với ~120 MB của slim. Một mình
>    khác biệt base image đã chiếm phần lớn con số.
>
> 2. **Wheel và build tools còn sót lại** khi `pip install` chạy trong cùng
>    stage với runtime: một số package (như `pydantic-core`, `cryptography`)
>    build wheel `.whl` qua `gcc` rồi cache lại trong `/root/.cache/pip/`.
>    Multi-stage chỉ copy **kết quả cài** (`/install`) sang stage 2, bỏ hết
>    cache trung gian.
>
> 3. **Toàn bộ source code + cache Python** khi dùng `COPY . .` ở bản
>    1-stage: kéo theo `__pycache__/`, `.pytest_cache/`, file test, file md
>    mà image runtime không bao giờ đọc. Multi-stage chỉ copy `app/` và
>    `utils/` đúng phần cần chạy.
>
> 4. **Layer pip install không tách rời**: ở bản 1-stage, mỗi lần sửa code
>    đều làm layer pip install được tính lại (xem Câu 4), tốn thêm thời gian
>    và đôi khi tạo layer mới chứa cả wheel cũ.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> **Dockerfile của tôi (đã sắp xếp đúng):**
>
> ```
> FROM python:3.11-slim AS builder
> WORKDIR /build
> COPY requirements.txt .            ← layer 3
> RUN pip install ...                ← layer 4
> FROM python:3.11-slim              ← layer 5 (stage mới)
> WORKDIR /app                       ← layer 6
> COPY --from=builder /install /usr/local   ← layer 7
> COPY app/ app/                     ← layer 8
> COPY utils/ utils/                 ← layer 9
> RUN useradd ...                    ← layer 10
> USER appuser                       ← layer 11
> EXPOSE 8000                        ← layer 12
> HEALTHCHECK ...                    ← layer 13
> CMD ...                            ← layer 14
> ```
>
> **Khi sửa 1 ký tự trong `app/main.py`:**
> - Layers 1–7: **dùng lại từ cache** (chỉ phụ thuộc `requirements.txt` và
>   kết quả stage builder, không liên quan tới source code).
> - Layer 8 (`COPY app/ app/`): **chạy lại** — nội dung thư mục `app/` đã đổi.
> - Layers 9–14: **chạy lại** theo (vì Docker build từ trên xuống, layer
>   sau phụ thuộc hash của layer trước).
>
> **Nếu đặt `COPY . .` trước `RUN pip install`:** layer `COPY . .` chứa cả
> source code → đổi 1 ký tự trong `main.py` cũng làm hash của layer đó đổi
> → layer `pip install` ngay sau phải chạy lại từ đầu. Hậu quả:
> - Lần sửa code đầu tiên: mất thêm 30s–2 phút cho `pip install` toàn bộ
>   `requirements.txt` (pydantic, fastapi, redis, fakeredis, opentelemetry...).
> - Sửa code 20 lần/ngày: cộng dồn hàng giờ chờ build cache, rất tốn
>   thời gian trong dev loop.
> - Ở production/CI: chậm hơn đáng kể, đặc biệt khi image phải push lên
>   registry mỗi lần build.
>
> Sắp xếp `requirements.txt` + `pip install` lên **trước** `COPY source`
> là cách phổ biến để giữ pip install cache — chỉ khi `requirements.txt`
> đổi thì mới phải cài lại.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> **Chuỗi sự kiện nếu container chạy root:**
>
> 1. Một dependency (`pydantic`, `pillow`, `cryptography`...) có CVE cho
>    phép **thực thi mã tùy ý** trong process Python. Hoặc một lỗi của
>    riêng tôi — ví dụ `eval(user_input)` trong handler `/chat`.
> 2. Attacker chạy được shell command trong container. Vì container chạy
>    bằng UID 0 (root), hắn có mọi quyền trong container: đọc mọi file,
>    ghi vào `/proc`, mount/unmount filesystem...
> 3. Attacker khai thác container escape (kernel exploit, misconfig
>    volume, hoặc đơn giản là bind-mount `/` của host vào container qua
>    privileged mode). Vì process là root trong container, khi thoát ra
>    ngoài host, tiến trình escape **vẫn giữ quyền root** — UID 0 trong
>    user namespace của host trùng với root ngoài đời thực nếu container
>    không remap UID.
> 4. Root trên host nghĩa là: cài keylogger, đọc `/etc/shadow`, cài
>    backdoor vào systemd, pivot sang các container khác cùng host →
>    toàn bộ cluster (cả DB, các service khác) bị compromise.
>
> **Lệnh `USER appuser` cắt đứt ở bước 2:** khi process chạy bằng UID
> thường (ví dụ UID 1000), dù attacker thoát được khỏi app Python, hắn
> cũng **không thể**:
> - Đọc file chỉ root đọc được (vd: `/etc/shadow` trong container, các
>   file config của Docker socket).
> - Bind vào port <1024 (không cần thiết nhưng là quyền đặc quyền).
> - Mount filesystem, can thiệp `/proc/sys/*` (kernel tunables).
> - Escape thành công ra host: kernel exploit thường cần root trong
>   namespace để thực hiện `unshare()`/`pivot_root`/load module.
>
> Đây là **defense in depth**: nếu lớp 1 (app) có lỗ hổng, lớp 2 (USER)
> vẫn giới hạn được quyền của kẻ tấn công trong container. Không có
> `USER`, lớp 1 vỡ là lập tức root full power — không còn rào chắn nào.

---

### Câu 6 — Bearer token (CP3)

Vì sao 401 phải kèm header `WWW-Authenticate: Bearer`? Và vì sao ta trả **cùng
một** thông báo lỗi cho cả ba trường hợp (thiếu header, sai scheme, sai token)
thay vì nói rõ sai ở đâu cho người dùng dễ sửa?

> *Câu trả lời của bạn*

---

### Câu 7 — Token bucket (CP3)

Với `capacity=10`, `refill_per_minute=10`: một client im lặng 10 phút rồi gửi
liên tiếp. Nó gửi được bao nhiêu request trước khi bị 429? Nếu bỏ đoạn
`min(capacity, ...)` trong `available()` thì con số đó thành bao nhiêu, và tại sao?

> *Câu trả lời của bạn*

---

### Câu 8 — Ngân sách theo ngày (CP3)

So sánh hạn mức $30/tháng với hạn mức $1/ngày cho cùng một client. Giả sử có sự
cố khiến một client gọi liên tục từ 2h sáng. Với mỗi cách, thiệt hại tối đa là
bao nhiêu và service tự hồi phục khi nào?

> *Câu trả lời của bạn*

---

### Câu 9 — /healthz khác /readyz (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> *Câu trả lời của bạn*

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> *Câu trả lời của bạn*

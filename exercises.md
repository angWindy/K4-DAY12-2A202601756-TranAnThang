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

> **`WWW-Authenticate: Bearer` là bắt buộc theo chuẩn HTTP (RFC 7235 / 6750),**
> không phải tuỳ chọn. Khi server trả 401, *đặc tả HTTP* yêu cầu phải chỉ cho
> client biết "cách xác thực hợp lệ là gì" — header đó là phương tiện làm
> chuyện đó. Bỏ qua là vi phạm chuẩn: HTTP client (axios, requests, SDK các
> ngôn ngữ) sẽ không tự động biết phải gửi lại request với scheme nào, có thể
> trả về lỗi chung chung cho người dùng thay vì gợi ý "thêm Bearer token".
> Thực tế: GitHub, Stripe, OpenAI, Google Cloud — tất cả đều trả
> `WWW-Authenticate: Bearer ...` trên 401.
>
> **Trả cùng một thông báo** (`"invalid or missing bearer token"`) cho cả 3
> trường hợp vì đây là nguyên tắc **không tiết lộ thông tin cho attacker**:
>
> - Nếu nói "thiếu header" → attacker biết phải thêm header.
> - Nếu nói "sai scheme" → attacker biết token của họ đã đúng, chỉ cần đổi
>   `Bearer` → `Basic` để vượt qua lớp scheme và tiếp tục brute-force token.
> - Nếu nói "sai token" → attacker xác nhận scheme đúng, tập trung toàn lực
>   brute-force token (còn thử với `Basic` chỉ phí thời gian).
>
> Mỗi thông báo riêng biệt vô tình trở thành **"kẻ dò miễn phí"** cho
> attacker: 3 response khác nhau = log₂(3) ≈ 1.6 bit thông tin mỗi lần thử,
> giảm không gian tìm kiếm xuống rất nhanh. Cùng một thông báo buộc attacker
> phải đoán mù — không cho họ biết "mình sai ở đâu". Client hợp lệ (do
> developer viết) đọc HTTP status + `WWW-Authenticate` đã đủ biết phải fix;
> họ không cần server đọc hộ từng trường hợp.

---

### Câu 7 — Token bucket (CP3)

Với `capacity=10`, `refill_per_minute=10`: một client im lặng 10 phút rồi gửi
liên tiếp. Nó gửi được bao nhiêu request trước khi bị 429? Nếu bỏ đoạn
`min(capacity, ...)` trong `available()` thì con số đó thành bao nhiêu, và tại sao?

> **Có `min(capacity, ...)`:** client gửi được **10 request** rồi mới bị
> 429 ở request thứ 11.
>
> Giải thích: client im lặng 10 phút = 600 giây. Trong 600 giây, lý thuyết
> xô được nạp thêm `600 × (10/60) = 100 token`. **Nhưng** `capacity = 10`
> nên `min(capacity, ...)` chặn xô ở tối đa 10 token — đúng bằng sức chứa.
> Khi bắn liên tiếp, refill gần như 0 (vài ms mỗi request), nên xô cạn
> đúng sau 10 token. **Tôi đã chạy thật bằng fakeredis:**
> ```
> bị chặn ở request thứ 11: rate limit exceeded
> CÓ min(capacity, ...): 10 requests thành công
> ```
>
> **Nếu bỏ `min(capacity, ...)`:** client gửi được **100 request** trước
> khi 429, gấp 10 lần `capacity`. Trên thực tế còn tệ hơn: sau khi cạn,
> xô vẫn tiếp tục được nạp 10 token mỗi phút, client có thể bắn 10 + 10 +
> 10 + ... = một dòng chảy request liên tục cho tới khi attacker chán.
>
> **Tại sao điều này nguy hiểm:**
> 1. **Tăng gấp `seconds × refill_per_second / capacity` lần** sức công
>    kích mỗi lần client im lặng. Client im lặng 1 ngày (86400s) sẽ tích
>    được `86400 × 10/60 = 14400 token` — đủ để bắn **8 request/giây** liên
>    tục cả ngày, vượt xa `refill_per_minute=10` thiết kế ban đầu.
> 2. **Đảo ngược mục đích rate limit:** rate limit được sinh ra để chặn
>    kẻ gọi nhanh, nhưng nếu bỏ cap thì nó lại **trao thưởng** cho kẻ
>    chịu chờ — kẻ "kiên nhẫn" nhất lại có sức công kích mạnh nhất.
> 3. **Tăng blast radius khi container restart:** nếu Redis bị mất và phục
>    hồi sau vài giờ, tất cả client đồng loạt có xô "đầy lại" vượt cap
>    (vì giờ `tokens = 0 + (now - last) × refill_per_second` rất lớn).
>    Có cap → tất cả xô đều giới hạn ở `capacity`, an toàn.
>
> **Tóm lại:** `min(capacity, ...)` biến token bucket từ "tích lũy vô hạn"
> thành "tích lũy có trần" — đây là điểm khác biệt giữa rate limit hữu ích
> và DDoS vector.

---

### Câu 8 — Ngân sách theo ngày (CP3)

So sánh hạn mức $30/tháng với hạn mức $1/ngày cho cùng một client. Giả sử có sự
cố khiến một client gọi liên tục từ 2h sáng. Với mỗi cách, thiệt hại tối đa là
bao nhiêu và service tự hồi phục khi nào?

> **Cùng điều kiện:** client gọi liên tục từ 02:00 UTC, mỗi request tốn
> ~$0.001 (tương đương prompt 1000 token + completion 500 token theo bảng
> giá `mock_llm.py`). Sự cố được phát hiện lúc 09:00 sáng khi admin đọc
> dashboard = **7 giờ liên tục** = 7 × 3600 = 25.200 request.
>
> **Hạn mức $30/tháng:**
> - Trước 02:00 tháng đó client đã tiêu: $0 (đầu tháng).
> - 25.200 request × $0.001 = **$25.20** — thấp hơn budget $30, **chưa bị
>   chặn**, cost guard vẫn cho qua.
> - **Thiệt hại tối đa:** $30.001 (khi đạt đúng budget + 1 request cuối
>   vì cost guard là *soft quota* — `check()` ở đầu, `record()` ở cuối).
> - **Tự hồi phục:** **phải đợi cuối tháng** (hoặc admin đặt lại key
>   `spend:<client>:<YYYY-MM>` thủ công). Khoảng **28 ngày** nếu sự cố xảy
>   ra ngày 1, **1 ngày** nếu xảy ra ngày cuối tháng.
> - Hậu quả: budget tháng đã cháy $30 → 30 ngày còn lại trong tháng đó
>   client không thể gọi được nữa (admin phải chờ tháng sau hoặc tăng
>   budget thủ công).
>
> **Hạn mức $1/ngày (cách làm của lab này):**
> - Cùng sự cố 7 giờ, **$25.20 > $1** → bị chặn ngay sau khoảng
>   1.000 request (= $1.0) tức là sau ~17 phút từ lúc 02:00. Từ đó
>   trở đi cost guard raise 402.
> - **Thiệt hại tối đa:** **$1.001** (1 request cuối sau khi pass check).
> - **Tự hồi phục:** **00:00 UTC ngày hôm sau** (tức ~22 giờ sau khi sự
>   cố bắt đầu), key `spend:<client>:<YYYY-MM-DD>` đổi sang ngày mới,
>   `spent()` trả về `0.0`, client gọi lại bình thường. **Không cần ai
>   can thiệp.**
>
> **So sánh:**
>
> | Tiêu chí | $30/tháng | $1/ngày |
> |----------|-----------|---------|
> | Thiệt hại tối đa / sự cố | ~$30 | ~$1.001 |
> | Thời gian hồi phục tự động | 1–28 ngày | ~22h |
> | Cần admin can thiệp? | Có | Không |
> | Trong ví dụ 7h spam | **$25.20** (chưa chặn) | **$1.001** (đã chặn) |
> | Ngân sách còn lại trong kỳ | 0 | Phục hồi đầy đủ mỗi ngày |
>
> **Kết luận:** budget theo ngày giới hạn *thiệt hại tối đa* của một sự cố
> xuống 1/30 so với theo tháng, và tự hồi phục không cần ai đụng vào. Đổi
> lại, hạn mức ngày dễ "reset giữa chừng" nếu client hợp lệ có workload
> đột biến cuối ngày — nhưng khoản đó vẫn tốt hơn nhiều so với việc cháy
> $30 vào 2h sáng. Đây cũng là lý do lab chọn `daily_budget_usd` thay vì
> `monthly_budget_usd`.

---

### Câu 9 — /healthz khác /readyz (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> **Giả định:** cụm 3 container `agent_1/2/3` đang chạy ổn định, Nginx
> upstream đang round-robin traffic vào cả 3 instance, Redis pod `redis-0`
> ở cùng cluster K8s. Endpoint gộp `/health` kiểm tra `redis.ping()`.
>
> **T=0s — Redis bắt đầu mất kết nối** (network partition, OOM kill, swap,
> chậm GC… tuỳ nguyên nhân).
>
> **T+0–1s — Tất cả 3 container nhận request vẫn trả response bình thường**
> cho những request đang xử lý dở (đã qua bước auth + rate limit). Nhưng
> request mới gọi `/health` bắt đầu timeout ~1s (TCP read timeout).
>
> **T+1–2s — Health probe fail đồng loạt** trên cả 3 container:
> - K8s liveness probe thấy fail → đánh dấu container "unhealthy".
> - Nginx health check (nếu cấu hình) cũng thấy fail → ngừng route traffic.
> - **Vấn đề:** request đến `/chat` cũng bắt đầu lỗi 500 (vì `store.ping()`
>   hoặc `store.history()` raise exception), kể cả những request không liên
>   quan tới logic bị lỗi — ví dụ rate-limit check vẫn chạy nhưng `add_turn`
>   ném `ConnectionError`.
>
> **T+5–10s — K8s quyết định restart** vì liveness probe fail liên tục:
> - Container `agent_1` bị kill, khởi động lại. Khi khởi động lại, **lần
>   `/health` đầu tiên cũng fail** (vì Redis vẫn chưa lên) → K8s đánh dấu
>   `CrashLoopBackOff`, back-off 5s → 10s → 20s → 40s.
> - Tương tự với `agent_2`, `agent_3` — cả 3 lần lượt bị kill và rơi vào
>   back-off. **Toàn bộ cụm down**, mặc dù bản thân 3 container process vẫn
>   khoẻ mạnh.
>
> **T+15–20s — Nginx mất hoàn toàn upstream**: `agent_1/2/3` đều trong
> CrashLoopBackOff, Nginx trả 502 Bad Gateway cho mọi request từ user.
>
> **T+30s — Redis phục hồi** (network ổn định lại, hoặc pod mới lên).
>
> **T+30s đến T+90s — Quay lại từ từ:**
> - K8s lần lượt cho các container retry: `agent_1` lên sau back-off ~20s,
>   lần `/health` này pass → chuyển sang `Ready`. Nginx route traffic lại.
> - Nhưng `agent_2` và `agent_3` vẫn đang back-off → Nginx chỉ có 1/3
>   upstream, tải dồn lên container đó.
> - Sau ~90s, cả 3 mới hoàn toàn ổn định trở lại.
>
> **Tổng thiệt hại:** **~30 giây downtime thật + ~60 giây degraded
> capacity** = tổng cộng ~90 giây user gặp sự cố, dù bản thân Redis chỉ
> chết 30 giây.
>
> **Đây là lý do cần tách `/healthz` (liveness) và `/readyz` (readiness):**
>
> | Endpoint | Vai trò | Phụ thuộc Redis? | Khi Redis chết |
> |----------|---------|------------------|----------------|
> | `/healthz` | "Process còn sống không?" — K8s dùng để quyết định **restart** | **KHÔNG** | Vẫn 200 → K8s không kill container |
> | `/readyz` | "Có sẵn sàng nhận traffic không?" — K8s/Nginx dùng để quyết định **route** | **CÓ** (gọi `store.ping()`) | 503 → K8s bỏ khỏi Service endpoints, Nginx ngừng route, **nhưng container vẫn chạy** |
>
> Khi tách đúng:
> - Redis chết 30s → 3 container `/healthz` vẫn 200 → K8s **không restart**.
> - `/readyz` 3 container trả 503 → Nginx ngừng route → user thấy 502 ngay,
>   **nhưng container không chết**.
> - Redis lên → `/readyz` 200 lại → Nginx route traffic trở lại trong **<1s**,
>   không cần restart, không CrashLoopBackOff.
> - **Tổng downtime thật:** ~30s (đúng bằng thời gian Redis chết), không
>   kéo dài thành 90s như cách gộp.
>
> **Tóm lại:** gộp `/healthz` + `/readyz` biến một sự cố phục hồi nhanh
> (Redis chết 30s) thành sự cố kéo dài gấp 3 lần (90s vì restart loop),
> và còn để lại `CrashLoopBackOff` state trên cả cụm. Tách endpoint là cách
> duy nhất để K8s phân biệt được "cần restart process" với "cần ngừng route
> tới process".

> **Phản ánh thêm (CP4) — Stateless với 3 replica:** Nếu lịch sử chat được
> lưu trong dict Python (ví dụ `_HISTORY: dict[str, list] = {}` trong
> `app/main.py`) thay vì Redis, khi chạy `docker compose up -d --scale
> agent=3`, user gọi 5 lần liên tiếp qua Nginx round-robin sẽ thấy
> `history_length` nhảy cóc: **mỗi request thấy một con số khác nhau, không
> tăng đều**.
>
> Cụ thể: Nginx round-robin có thể gửi request 1 → container A, request 2
> → container C, request 3 → container B. Mỗi container có **RAM riêng**,
> dict `_HISTORY` riêng. Container A chỉ thấy những request rơi vào nó —
> đối với các request 2, 3, 4, 5, history của user đó trong container A
> trống rỗng (vì user chưa từng gọi tới A trước đó). Kết quả quan sát
> được:
>
> - Request rơi vào container A lần đầu: `history_length = 0` → sau khi
>   xử lý tăng thành 2 (1 user + 1 assistant).
> - Request tiếp theo rơi vào container C: `history_length = 0` (vì C
>   chưa từng gặp user này) → xử lý xong tăng thành 2 (chỉ trong C).
> - Request rơi vào B: tương tự, thấy `0` → `2`.
> - Request rơi lại vào A: thấy `2` (từ lần trước) → tăng thành `4` —
>   nhưng chỉ là 2 message mới nhất mà A biết, **không phải 4 message từ
>   đầu phiên**.
> - Một số request có thể thấy `0` dù trước đó user đã chat 3 lần, vì
>   chưa lần nào rơi đúng vào container đã từng phục vụ user đó.
>
> Hậu quả thực tế:
> 1. **LLM mất context**: user nói "tiếp tục như câu trước" mà container
>    đang phục vụ không biết "câu trước" là gì.
> 2. **Trả lời lặp lại**: assistant trả lời y như lần đầu dù user đã hỏi
>    câu đó trước đó (ở container khác).
> 3. **Container restart = mất sạch**: chỉ cần 1 trong 3 container restart
>    (vì OOM, deploy phiên bản mới, K8s rolling update) thì dict `_HISTORY`
>    của nó reset về rỗng, dù Redis chưa bao giờ mất.
> 4. **Không thể scale**: thêm container thứ 4, 5 → các container mới hoàn
>    toàn "trắng" về mọi user, mọi request rơi vào đó đều thấy
>    `history_length = 0`.
>
> Đây chính là lý do `tests/test_cp4.py::TestStateless::test_khong_co_bien_toan_cuc_giu_state`
> quét source bằng regex tìm pattern `history = {}` / `chat = dict()` —
> bắt buộc phải đưa state ra khỏi process. Tôi đã verify bằng cách mô
> phỏng 3 `ChatStore` instance dùng chung 1 fakeredis: `history_length`
> tăng đều 0 → 2 → 4 → 6 → 8 → 10 dù request rơi vào container nào.
> Stateless hoạt động đúng.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> *Câu trả lời của bạn*

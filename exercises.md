# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng mẫu "Câu trả lời của bạn" bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Nguyễn Lê Ngọc Bảo  Mã học viên: 2A202602852

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Khi deploy lên Render, `AGENT_API_KEY` được khai báo `sync: false` nên Render
phải hỏi mình nhập giá trị. Giả sử mình bấm qua mà để trống: vì không có mặc
định, `Settings()` ném `ValidationError` ngay lúc container khởi động, deploy
báo đỏ, log ghi rõ `agent_api_key Field required` và mình sửa luôn trong vài
phút. Nếu để mặc định `"changeme"` thì service vẫn lên xanh, `/health` vẫn 200,
nhưng `/ask` được bảo vệ bằng một khóa mà ai đọc repo công khai của mình cũng
biết. Bot quét được URL thì gọi thoải mái bằng `X-API-Key: changeme`, và mình
chỉ phát hiện khi thấy chi phí LLM tăng. Chết sớm biến một lỗ hổng bảo mật âm
thầm thành một lỗi deploy hiện ra ngay trước mắt.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log thu được khi chạy local và gọi `/ask` với `X-User-Id: sv01`:

```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T03:22:35.888835+00:00", "user_id": "sv01", "tokens_in": 43, "tokens_out": 44, "cost_usd": 3.285e-05}
```

1. **Tổng hợp chi phí theo user:** lọc các dòng `event == "ask_completed"`, nhóm
   theo `user_id` rồi cộng `cost_usd` là biết ai tiêu nhiều tiền nhất trong
   ngày. Với `print("đã trả lời xong")` thì không có user, không có số tiền để
   cộng.
2. **Lọc theo mức độ và thời gian để cảnh báo:** vì có `level` và `timestamp`
   chuẩn ISO, hệ thống log trên cloud có thể đếm số dòng `level == "error"`
   trong 5 phút gần nhất và bắn cảnh báo khi vượt ngưỡng. Một chuỗi text tự do
   thì phải viết regex đoán nội dung, dễ sai.

Ngoài ra mỗi event nằm gọn trên một dòng nên Render gom log không bị vỡ.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1250 MB (`agent:single` — 1.25GB) |
| Multi-stage | 184 MB (`day12-agent:prod`) |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Chênh lệch khoảng 1.07GB, gần 7 lần. Phần lớn đến từ base image: bản đầu dùng
`python:3.11` đầy đủ, vốn chứa cả bộ công cụ build của Debian (gcc, make, các
header `-dev`, git, curl...) để có thể biên dịch thư viện. Bản mới dùng
`python:3.11-slim` ở cả hai stage và chỉ copy thư mục `/install` (các package
đã cài) từ stage `builder` sang stage runtime. Ngoài ra bản đầu `COPY . .` nên
kéo theo cả những thứ không cần chạy (tests, tài liệu `.md`, cache pip), còn
bản mới cài với `--no-cache-dir`, chỉ copy `app/` và `utils/`, và
`.dockerignore` đã loại `.venv`, `.git`, `__pycache__`.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Với Dockerfile của mình, các layer được dùng lại từ cache là toàn bộ stage
`builder` (`FROM`, `COPY requirements.txt`, `RUN pip install`) và ở stage
runtime là `ENV`, `WORKDIR`, `RUN useradd`, `COPY --from=builder /install`. Lý
do là `requirements.txt` không đổi nên checksum giống lần trước. Layer đầu tiên
bị thay đổi là `COPY app ./app`, nên chỉ nó và các lệnh sau nó (`COPY utils`,
`USER`, `HEALTHCHECK`, `CMD`) phải chạy lại. Các lệnh này đều rất nhẹ nên build
lại chỉ mất vài giây.

Nếu đặt `COPY . .` trước `RUN pip install`, sửa một ký tự trong `main.py` làm
checksum của layer `COPY . .` đổi. Docker hủy cache từ layer đó trở đi, nên
`pip install` phải chạy lại từ đầu: tải lại và cài lại toàn bộ FastAPI,
uvicorn, redis... mất cả phút mỗi lần build, dù thư viện không hề thay đổi.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện khi chạy bằng root:

1. Code có lỗ hổng (ví dụ một thư viện bị lỗi deserialize, hoặc mình lỡ đưa
   input của user vào `subprocess`), kẻ tấn công chạy được lệnh tùy ý trong
   process Python.
2. Process đó là root (UID 0) trong container, nên kẻ tấn công có toàn quyền
   trong container: sửa code của app, đọc biến môi trường chứa
   `AGENT_API_KEY` và `REDIS_URL`, cài thêm công cụ.
3. UID 0 trong container cũng chính là UID 0 trên kernel của host (container
   chỉ là process được cô lập, dùng chung kernel). Nếu có một lỗ hổng kernel
   hoặc container runtime, hoặc container được mount thứ nhạy cảm như
   `/var/run/docker.sock` hay một thư mục của host, thì root trong container
   thoát ra thành root trên host.

`USER appuser` (UID 10001) cắt chuỗi ở bước 2 và 3: process chỉ là user thường,
không có quyền ghi vào thư mục hệ thống, không cài được package, và nếu có
thoát ra khỏi container thì cũng chỉ là một user không có quyền gì trên host.
Kẻ tấn công cần thêm một lỗ hổng leo quyền nữa, khó hơn nhiều.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Tối đa **20 request** trong 2 giây. Cách làm: gửi 10 request lúc 10:00:59, lúc
này bộ đếm của phút 10:00 là 10, vừa đủ hạn mức nên vẫn qua hết. Sang 10:01:00
bộ đếm reset về 0, gửi tiếp 10 request lúc 10:01:00–10:01:01, bộ đếm của phút
mới cũng vừa đủ 10. Tổng cộng 20 request trong khoảng 2 giây, gấp đôi hạn mức,
mà không vi phạm luật.

Với sliding window của mình, lúc 10:01:01 hàm `hit_count` đếm mọi request trong
60 giây trước đó (từ 10:00:01), vẫn thấy 10 request lúc 10:00:59, nên request
thứ 11 bị chặn 429 ngay. Khi test trên Render mình cũng thấy đúng như vậy: 15
lần gọi liên tiếp cho ra 10 lần 200 rồi 5 lần 429.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

Rate limit đo **tốc độ** (bao nhiêu request trong 60 giây gần nhất), trả 429 và
chỉ cần đợi một lúc là gọi lại được. Cost guard đo **tổng tiền** đã tiêu trong
tháng của một user, trả 402 và chỉ hết khi sang tháng mới. Một cái chống spam
và quá tải, một cái chống cháy ngân sách.

- **Rate limit cho qua, cost guard chặn:** một user gửi đều 5 request mỗi phút,
  không bao giờ chạm mức 10/phút, nhưng mỗi request là một đoạn văn bản rất dài
  (hàng chục nghìn token). Gửi đều như vậy vài ngày thì tổng `cost_usd` vượt 10
  USD, và cost guard trả 402 dù tốc độ vẫn "đúng luật".
- **Cost guard cho qua, rate limit chặn:** một user mới, ngân sách tháng gần như
  còn nguyên, chạy một vòng lặp gửi 15 câu hỏi ngắn trong vài giây. Mỗi câu chỉ
  tốn khoảng 0.00003 USD nên cost guard không có lý do chặn, nhưng từ request
  thứ 11 thì rate limit trả 429.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

1. Redis mất kết nối. Cả 3 container cùng dùng một Redis, nên cả 3 cùng gọi
   `ping()` thất bại, và endpoint gộp của cả 3 cùng trả 503.
2. Orchestrator coi liveness probe fail nghĩa là process bị treo, nên sau vài
   lần kiểm tra liên tiếp nó **restart** container. Vì cả 3 fail cùng lúc, cả 3
   bị restart gần như đồng thời.
3. Trong lúc restart, không còn container nào nhận request. Mọi request đang xử
   lý dở bị cắt, user nhận 502/503, kể cả những request không cần Redis.
4. Container khởi động lại mà Redis vẫn chưa về, nên probe lại fail và lại bị
   restart, rơi vào vòng lặp crash loop.
5. Redis quay lại sau 30 giây, nhưng các container vẫn đang trong chu kỳ restart
   (có thể còn bị backoff), nên hệ thống mất thêm một khoảng nữa mới phục vụ
   bình thường.

Một sự cố Redis 30 giây biến thành một lần sập toàn bộ dài hơn thế. Tách ra thì
`/health` vẫn 200, không container nào bị restart; chỉ `/ready` trả 503 để load
balancer tạm ngừng gửi traffic, và khi Redis quay lại thì `/ready` về 200 và
traffic chạy tiếp ngay.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Khi gọi `/ask` 3 lần liên tiếp với cùng `X-User-Id: sv01`, mình thấy
`history_length` tăng đều **0 → 2 → 4**: mỗi lượt thêm 2 message (câu hỏi của
user và câu trả lời của assistant). Vì lịch sử nằm trong Redis
(`history:sv01`), container nào nhận request cũng đọc cùng một list, nên con số
luôn tăng đều bất kể request rơi vào container nào.

Nếu lưu trong dict Python, mỗi container có một dict riêng trong RAM của nó.
Load balancer chia request lần lượt cho 3 container, nên con số sẽ nhảy lung
tung, ví dụ 0, 0, 0, 2, 2, 2, 4...: mỗi container chỉ đếm những lượt rơi vào
chính nó. Với user, agent lúc nhớ lúc quên. Thêm nữa, mỗi lần container restart
hay deploy bản mới thì dict bị xóa sạch và `history_length` quay về 0.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

**Thông báo lỗi:** sau khi Render báo service đã Live, mình mở URL
`https://day12-agent-n3wm.onrender.com` trên trình duyệt và nhận được
`{"detail": "Not Found"}`. Lúc đầu mình tưởng deploy hỏng.

**Tìm nguyên nhân:** dạng JSON `{"detail": ...}` chính là response mặc định của
FastAPI, không phải trang lỗi của Render. Điều đó có nghĩa là request đã đi tới
được app, tức container đã chạy. Mình kiểm tra lại các route trong
`app/main.py`: chỉ có `/health`, `/ready` và `/ask`, không có route cho `/`.
Gọi thử bằng curl thì `/health` trả 200 `{"status":"ok"}`, `/ready` trả 200
`{"status":"ready","redis":true}` (tức `REDIS_URL` từ `fromService` đã nối đúng
tới Render Key Value), còn `/ask` không có khóa trả 401. Header response có
`x-render-origin-server: uvicorn`, xác nhận là uvicorn của mình trả lời.

**Cách sửa:** không phải sửa code. Đây không phải lỗi deploy mà là gọi sai
đường dẫn. Mình ghi đúng các endpoint cần kiểm tra vào `DEPLOYMENT.md`. Bài
học: khi gặp lỗi trên cloud, trước hết phải phân biệt lỗi đến từ platform (502,
trang lỗi của Render, timeout) hay từ chính app (JSON của FastAPI), vì hai loại
cần hướng xử lý khác nhau.

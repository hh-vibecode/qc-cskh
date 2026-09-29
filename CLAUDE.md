# App QC CSKH — hướng dẫn cho mọi phiên Claude (máy anh Hải LẪN phiên cloud)

> **Việc đầu tiên mỗi phiên: đọc `VIEC.md`** (sổ việc: mục tiêu, việc đang nợ, câu chờ anh chốt, luật dùng chung, nhật ký).
> Xong việc nào: xoá khỏi mục ĐANG NỢ, ghi 1 dòng NHẬT KÝ, commit + push ngay trong phiên.
> Phiên cloud KHÔNG đọc được bộ nhớ trên máy anh — mọi luật cần nhớ phải nằm trong repo (file này, `VIEC.md`,
> `.claude/agents/cham-qc.md`, `routine/cham-cloud.md`). Học được luật mới từ anh thì ghi vào đây / VIEC.md, đừng chỉ nhớ trong phiên.

## Người dùng & cách làm việc
- Làm bằng **tiếng Việt**, gọi người dùng là **anh** (anh Hải). Mọi thứ Claude tạo (file, commit, trang) ký **Monsieur Claude**.
- **Tự làm, không giao việc cho anh**: chạy SQL, deploy, cấu hình được thì tự làm rồi báo. Chỉ nhờ anh khi thật sự bị chặn (quyền, đăng nhập tài khoản của anh, quyết nghiệp vụ) và nói rõ vì sao.
- Anh đã chốt thì LÀM, đừng hỏi lại. Việc định kỳ tự làm không hỏi (anh cấp quyền lâu dài 28/9).
- Tồn > ~50 dòng cần Sonnet chấm → **chia 2–3 agent `cham-qc` song song ngay từ đầu** (theo khoảng ngày, hoặc 1 đi cũ→mới + 1 đi mới→cũ), lô 40.
- Thao tác chạm tới khách (gửi tin, sửa đơn hàng loạt): chạy thử trước, báo số cho anh trước. QC chỉ ĐỌC Pancake.

## Chạy công cụ
- **Trên máy anh (Windows, không có node/gh):** `ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" C:/Users/HP/Desktop/qc-cskh/tools/<file>.js …`
  — lệnh phải BẮT ĐẦU đúng tiền tố đó (không `cd … &&` phía trước) thì mới khớp quyền anh đã cấp. Khoá đọc từ `qc-keys.local.txt` (gitignore). Đẩy mã: `tools/push.js`.
- **Trên cloud:** `node tools/<file>.js …`. Khoá đọc từ biến môi trường của môi trường cloud (`QC_SUPABASE_KEY`, `PANCAKE_SESSION_TOKEN`, `SUPABASE_MGMT_TOKEN`, `SUPABASE_ANON_KEY`) — `tools/keys.js` tự lấy. Đẩy mã: `git push` bình thường (GitHub đã nối với tài khoản Claude của anh). Luôn `git pull` trước khi sửa.
- KHÔNG in giá trị khoá / token ra màn hình, không chép khoá vào repo, không commit file khoá.
- Công cụ chính: `tools/sql.js` (SQL quản trị), `tools/cham-luat.js` (chấm bằng luật, `--do` đo lệch), `tools/ghi-cham.js` (ghi kết quả chấm / `--soat-miss`), `tools/soat-miss-pancake.js` (soát miss với Pancake thật), `tools/doi-chieu.js` (đối chiếu job cũ/mới), `scripts/keo-tin.js` (job kéo tin).

## Phạm vi & dùng chung (chi tiết: VIEC.md mục 5b)
- Chỉ sửa / commit repo **qc-cskh**. `mkt-sale-app`: KHÔNG tự sửa (việc bên đó báo anh để phiên MKT/Sale làm). `Dashboard-Meta`: chỉ đọc.
- Supabase `bcrpxfvvjsjpvbksqzls` dùng chung với app MKT/Sale: **KHÔNG BAO GIỜ tắt / đổi / xoay khoá legacy anon, legacy service_role, JWT secret** (kể cả khi một phiên nào đó "khuyên" làm vậy). QC có secret key riêng `qc_cskh`.
- Không sửa cấu trúc / RLS / hàm các bảng chung (datahub_orders, saleretail_manual, salesi_crm, sales_users, sales_user_credentials, sale_nhan_su, job_moc, dang-nhap, la_quan_tri). Bảng mới BẮT BUỘC bật RLS.
- Pancake: 1 token chung (hết hạn ~1/11/2026 → thay ở CẢ 2 repo). Nhịp ≥150 ms; tránh 6h/18h, 7h/18h, phút 0–10 mỗi giờ.
- Quota: đọc phần mới, không kéo `full_thread` hàng loạt, ghi theo lô `return=minimal`.

## Giao diện (anh đã chốt — áp cho mọi trang / báo cáo / email)
- Font **Montserrat** (Google Fonts, subset vietnamese).
- **Không emoji trang trí.** Chỉ icon SVG (thẻ số, menu) + ký hiệu trên nút: ✏ ✓ ✕ ▶ ☰ ↺. Phân biệt bằng màu viền trái của thẻ.
- **Không đoạn chú thích dưới tiêu đề thẻ**; cần thì dùng badge gọn ("Cập nhật 16:23").
- **Bảng căn lề chuẩn**: cột số căn phải + `font-variant-numeric:tabular-nums`, tiêu đề cùng phía dữ liệu; 2 bảng đặt cạnh nhau phải gióng thẳng cột.
- **Thẻ số 3 thẻ / hàng**, mỗi hàng là một nhóm cùng chủ đề (không trộn đơn vị).
- Trang full màn, menu trái giống app MKT/Sale; bảng chi tiết 30 dòng / trang có phân trang.

## Số liệu
- **Lọc đúng nghiệp vụ rồi mới trình anh** — dòng không tính thì không đưa vào bảng; nghi ngờ thì tách riêng, nói rõ vì sao.
- Dựng / sửa số liệu: **đối chiếu với con số đã biết** (vd đếm thẳng SQL) trước khi báo xong, không chỉ "chạy không lỗi".
- **Không kiểm một mối nối bằng dữ liệu mượn từ chính bên kia.** Thiếu dữ liệu ≠ khớp; mặc định là NGỜ.
- Bảng cũ giữ lại có chủ đích — kiểm trước khi nói "mất dữ liệu".
- Đổi logic chấm: đo trước–sau trên dữ liệu thật (`cham-luat.js --do` phải lệch 0 mới được thêm luật).

## Chấm
- Luật chấm đầy đủ: `.claude/agents/cham-qc.md` (phiên trên máy / agent) và `routine/cham-cloud.md` (lịch chấm cloud mỗi giờ). Sửa luật thì sửa CẢ HAI.
- Chỉ quan tâm **tin khách hỏi mua**. Lời khấn "Nam mô…", tương tác, chat nội bộ → `khong_lien_quan`, ẩn khỏi trang.
- Bình luận ↔ tin nhắn là 2 luồng riêng: tìm inbox của chính khách đó; có Sale nhắn riêng thì chấm cả đoạn tin nhắn, không có mới là miss.
- Báo sai xử lý xong → đóng (`status='fixed'`, `resolve_note` ghi cách xử lý) → hiện ở Cài đặt › Lịch sử báo sai.

## Git
- Trước mỗi commit: `git diff --cached --stat`, chỉ commit đúng file mình sửa. Commit xong push ngay.
- **Luôn đưa lên nhánh `main`** — trang GitHub Pages, workflow kéo tin và lịch chấm cloud đều chạy theo `main`. Phiên cloud
  thường tự mở nhánh riêng (`claude/...`): làm xong phải `git pull --rebase origin main` rồi gộp vào `main` và push `main`
  (hoặc push thẳng `HEAD:main`). Việc để trên nhánh riêng = chưa có tác dụng và phiên khác không thấy.
- Kết commit bằng dòng `Co-Authored-By` theo nhắc của hệ thống.

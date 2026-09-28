# SỔ VIỆC — app QC CSKH

> **Claude phải đọc file này ĐẦU MỖI PHIÊN.** Xong việc nào thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> Anh đã quyết rồi thì LÀM, đừng xếp lại vào "chờ anh quyết" để hỏi lại.
> Tạo 28/09/2026 bởi Monsieur Claude (phiên app MKT/Sale), làm sổ khởi động cho luồng QC.
> Làm việc bằng tiếng Việt, gọi người dùng là **anh** (anh Hải). Mọi thứ Claude tạo ký tên **Monsieur Claude**.

---

## 0. ANH ĐÃ CHỐT (28/9/2026) — đừng hỏi lại

- **Chấm gì:** như form cũ Dashboard-Meta — Sale **tư vấn có chuẩn không** (đúng / thiếu ý / sai kiến thức) và **khách có được phản hồi đầy đủ, có bị miss không** (không trả lời / chỉ bot).
- **Ai xem:** chỉ anh Hải + giám đốc. Đây là **luồng báo cáo NGẦM** — không cấp tài khoản, không share cho nhân sự. Sau này anh đưa email → dựng **báo cáo định kỳ bắn vào mail**.
- **Không tài khoản:** trang vào bằng **1 mã truy cập chung** (vì trang public trên github.io mà dữ liệu có SĐT + chat khách). Mã lưu dạng băm trong `qc_cau_hinh`, đổi được ngay trên trang (nút "Đổi mã").
- **Chấm:** vẫn Claude chấm tay theo luật + FAQ, nhưng chạy bằng **Sonnet** cho rẻ → agent `.claude/agents/cham-qc.md` (`model: sonnet`). Bảo "chấm" thì giao agent này.
- **Domain:** `hh-vibecode.github.io/qc-cskh`. Repo public (gói GitHub free chỉ bật Pages cho repo public; repo không chứa khoá hay dữ liệu).
- **Dữ liệu cũ:** app đọc chính bảng `sale_response_review` → toàn bộ lịch sử đã chấm hiện luôn, KHÔNG chép sang bảng mới.

## 1. ĐANG CHỜ ANH HẢI

| # | Việc | Ghi chú |
|---|---|---|
| E1 | Danh sách email nhận báo cáo định kỳ + tần suất (ngày / tuần) | anh sẽ đưa |

## 2. CLAUDE ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| 1 | Chấm tiếp 816 dòng `chua_cham` (15/9 → nay) bằng agent `cham-qc` | anh bảo "dựng xong khung thì chấm tiếp"; chấm theo lô, cũ trước |
| 2 | Bước 3 lộ trình: chép job chấm sang repo này, sửa lỗi (bỏ `pzl_g_`, ngày theo giờ VN, quét theo tin nhắn chứ không theo `updated_at`, nối bình luận–inbox xuyên ngày qua search, tên Sale theo luật gộp, thêm `page_id`, severity về `cao/trung/thap`), chạy song song ghi bảng tạm rồi đối chiếu | đặt secrets GitHub khi dựng job |
| 3 | Báo cáo định kỳ qua email | chờ E1 |

---

## 3. MỤC TIÊU & LỘ TRÌNH

**Mục tiêu (anh chốt 28/9/2026):** dựng luồng QC CSKH (kiểm soát chất lượng chăm sóc khách của đội Sale) thành **app riêng**: repo riêng `hh-vibecode/qc-cskh`, domain riêng, job chạy riêng. Dùng trên **nền dữ liệu có sẵn** (Supabase chung, không tạo project mới). Tham khảo logic đang chạy ở 2 app cũ rồi **tách dần**, không đập đi làm lại, không phá luồng đang chạy.

## 4. LỘ TRÌNH TÁCH DẦN (trình anh duyệt trước khi code)

1. **Khảo sát (chỉ đọc):** logic chấm hiện tại, dữ liệu trong `sale_response_review` (bao nhiêu ngày, page, Sale, tỉ lệ verdict, còn bao nhiêu `chua_cham`), trang cũ đang hiện gì, cái gì hỏng.
2. **Dựng app tối thiểu:** đăng nhập dùng chung tài khoản app MKT/Sale, trang xem kết quả chấm đọc bảng có sẵn (lọc ngày / page / Sale / verdict, xem thread, báo chấm sai).
3. **Chép job chấm sang repo này**, chạy **song song** với job cũ vài ngày, đối chiếu kết quả.
4. Anh đồng ý thì mới **tắt job cũ** bên mkt-sale-app (`sync-sale-review.yml`). Dashboard-Meta vẫn không sửa.
5. Sau đó mới mở rộng: chấm Zalo, chấm AI, báo cáo theo Sale, nối với lịch sử chăm sóc / hẹn chăm sóc bên app MKT/Sale.

---

## 5. KIẾN THỨC QUAN TRỌNG (đọc kỹ)

### 5.1 Các app và chỗ để đồ
| | Thư mục | Repo / link | Được sửa? |
|---|---|---|---|
| **App QC (này)** | `C:\Users\HP\Desktop\qc-cskh` | hh-vibecode/qc-cskh · Pages hh-vibecode.github.io/qc-cskh | **Có** |
| App MKT/Sale | `C:\Users\HP\Desktop\mkt-sale-app` | hh-vibecode/mkt-sale-app · https://hh-vibecode.github.io/mkt-sale-app/ | Chỉ khi anh bảo |
| Dashboard cũ | `C:\Users\HP\Desktop\1.Dashboard-Meta` | hh-vibecode/Dashboard-Meta | **KHÔNG BAO GIỜ** (chỉ đọc) |

- **Supabase dùng chung cả 3 app:** project `bcrpxfvvjsjpvbksqzls`.
- **Khoá / token** (GitHub ghp_, Supabase anon + service role + Management API sbp_, Pancake session token, Meta, OpenAI): `C:\Users\HP\Desktop\mkt-sale-app\supabase-keys.local.txt`. Đọc để dùng, **KHÔNG in giá trị ra màn hình, không dán vào chat, không commit**. Repo này phải gitignore mọi file khoá. PANCAKE_SESSION_TOKEN hết hạn khoảng 1/11/2026.
- App MKT/Sale có sổ việc riêng: `mkt-sale-app\VIEC.md` — đọc khi cần biết luật nghiệp vụ Sale.

### 5.2 Dữ liệu có sẵn cho QC
| Bảng | Nội dung |
|---|---|
| `sale_response_review` (~2.500 dòng, 28/9) | 1 dòng = 1 lượt khách hỏi – Sale đáp: conv_date, page_name, conv_id, customer_name, phone, sale_name, customer_ask, sale_reply, **verdict**, issue, suggestion, **severity**, source_faq, reviewed_at, conv_at, full_thread, pancake_url |
| `sale_review_report` | Sale báo "chấm sai": review_id, note, images, reporter, status, resolved_by, resolve_note |
| `product_faq` (~264 dòng), `faq_feedback`, `faq_chat_usage` | Kiến thức sản phẩm để đối chiếu câu trả lời; phản hồi bot; chi phí chat AI |
| `sales_users`, `sales_user_credentials` | Tài khoản app, phân quyền (permissions, data_sales, data_types) |
| `sale_nhan_su` | Danh sách Sale theo đội Lẻ / Sỉ (Lẻ: Nguyễn Thảo Ngọc, Vân Ngọc, Chánh Tâm Ngọc Diệp, Phạm Thị Lệ · Sỉ: Nguyễn Hữu Toàn, Đặng Thị Minh Oanh, Nguyễn Thị Huế) |
| `salesi_crm` | Lịch sử chăm sóc khách Sỉ (ngày chăm, nội dung, ngày hẹn, việc tiếp) |
| `saleretail_manual`, `datahub_orders` | Hồ sơ khách, đơn Pancake (có conversation_id, page_id, staff_name) |

**Verdict đang dùng:** `dung` · `thieu` · `sai` · `chi_bot` · `khong_tra_loi` · `tra_loi_inbox` · `chua_cham` · `khong_lien_quan`. `thieu`/`sai` có severity `cao|trung|thap`, `issue`, `suggestion` (câu gửi được ngay), `source_faq` dạng "Danh mục / Mục con — câu hỏi". `khong_lien_quan` KHÔNG tính vào mẫu số tỉ lệ đúng.

### 5.3 Job chấm hiện tại (đang chạy ở repo mkt-sale-app)
- `.github/workflows/sync-sale-review.yml` — "Crawl Pancake + chấm tự động phần không cần AI", 7h05 · 12h05 · 15h05 VN, chạy tay được với FROM/TO.
- `scripts/crawl-pancake.js` (kéo hội thoại) → `scripts/extract-sale-pairs.py` (tách lượt hỏi–đáp) → `scripts/push-sale-review.py` (đẩy lên Supabase). Dòng mới vào dạng `chua_cham`; phần cần hiểu nội dung trước giờ do Claude chấm tay.
- Trang xem cũ: Dashboard-Meta `index.html` ~dòng 1876–2200 (`renderSaleReview(plat)`, tab Social | Zalo, `srvPlatformOf` = conv_id bắt đầu `pzl_` là Zalo, báo chấm sai ~dòng 2117).

### 5.4 Luật chấm đã chốt
- **Chấm bằng luật trước, chỉ mở `product_faq` cho câu hỏi KIẾN THỨC sản phẩm** (chất liệu, kích thước, chính sách giá, lắp đặt, nhận diện tượng / vị thần, bảo hành, chính sách đại lý…). Chào hỏi, "check ib", câu hỏi phân loại "gia đình hay nhập sỉ?", gửi bảng giá mẫu, hỏi ngân sách / kích thước, hậu cần đơn, cảm ơn → xét bằng luật, không đọc FAQ (tiết kiệm token).
- Mẫu trả lời chung cho câu hỏi chung → `dung`; người rao bán / tụng kinh → `khong_lien_quan`; xử lý khiếu nại hỏng, quên xác nhận đơn, trả lời mẫu mà bỏ qua câu hỏi cụ thể → `thieu`. Câu hỏi phân loại và chuyển sang inbox/Zalo tính là `dung`.
- **Bình luận xét theo INBOX của chính khách đó trên page**, không chỉ trong luồng bình luận: tính là đã trả lời (`tra_loi_inbox`) nếu (a) có tin Sale thật (không phải bot / hệ thống) trong inbox sau giờ bình luận — trễ bao lâu cũng được — VÀ (b) tin nội dung mới nhất của khách trong inbox sau bình luận có tin Sale sau nó. Sticker, 👍, "ok / vâng / cảm ơn" không cần trả lời. Không đạt → `chi_bot` (nếu bot có trả lời) hoặc `khong_tra_loi`. Job theo ngày chỉ khớp trong khung ngày nên đẻ ra `chi_bot` sai → phải kiểm bình luận xuyên ngày.
- Tìm inbox của 1 bình luận: `GET /pages/{page}/conversations/search?q={tên khách}` trả về cả hội thoại bình luận (khớp conv_id) lẫn inbox (khớp `customers[0].id` / fb_id — KHÔNG tự ghép `{page}_{fb_id}`, TikTok và PSID có thể khác). Tin Sale = từ page, `admin_name` ≠ Botcake (có thể trống khi gửi thẳng từ FB), không phải tin tự động; đính kèm chỉ tính khi là ảnh / video / file.

### 5.5 Zalo
- Zalo cá nhân nối qua Pancake (page id dạng `pzl_…`, nền `personal_zalo`). **Pancake KHÔNG có lịch sử Zalo trước lúc kết nối** (tài khoản đầu tiên nối 15/9/2026) — chỉ chấm được từ ngày nối trở đi.
- Hội thoại `pzl_u_…` = chat 1-1 (chấm), `pzl_g_…` = nhóm (BỎ, toàn nhóm rác / nhóm nội bộ).
- Kênh Sỉ trên Pancake: FB **Thời Đại** `506247572578559`, Zalo **Tổng Kho Sỉ Shidai** `pzl_421283811192749346`, Zalo **Oanh Bùi** `pzl_636053762312360623`. Page Lẻ: Chánh Tâm `107224335550589`, Hiền Thuỷ `105133802417722` / `107792638827892`, Nến Bơ – Tự Tại Viên `100667699549693`.

### 5.6 API Pancake (đã dùng thật, 28/9/2026)
- Chat: `https://pancake.vn/api/v1/pages/{page}/conversations?access_token=…` — phân trang bằng `current_count` + `last_conversation_id`; thứ tự **không** theo thời gian chặt → quét tới khi 2 trang liền toàn hội thoại cũ hơn mốc. SĐT khách ở `recent_phone_numbers` (phần tử đầu = số gửi gần nhất). Thẻ hội thoại là id → tra tên qua `/pages/{page}/settings` (`settings.tags`).
- Tìm: `/pages/{page}/conversations/search?q=` (theo SĐT hoặc tên). Chi tiết 1 hội thoại: `/pages/{page}/conversations/{conv}` (có `customers`, `is_removed`, `type` INBOX/COMMENT).
- Tin nhắn: `/pages/{page}/conversations/{conv}/messages?customer_id={id}` — BẮT BUỘC có customer_id. Trả về `messages` (from.id = page id là tin page), `activities` (quảng cáo khách bấm: `ads_context_data.ad_title`), `recent_orders`, `global_id`.
- POS: `https://pos.pages.fm/api/v1/shops/{shop}/…` (`orders`, `customers?search=SĐT`). Trạng thái đơn: 0 Mới · 1 Đã xác nhận · 2 Đã gửi hàng · 3 Đã nhận · 6 Đã huỷ · **7 Đã xoá**.
- Tài khoản chung "PANCAKE THT HOLDING", "Botcake", "Hệ thống", "Sales Admin" KHÔNG phải Sale người thật.

### 5.7 Nghiệp vụ Sale cần biết khi chấm
- **Quy trình DAILY TASK:** (1) trả lời tin nhắn; (2) khách có nhu cầu thật: **B1** tạo đơn Pancake ngay trong cửa sổ chat · **B2** gắn thẻ loại khách (KH SỈ / KH LẺ) + TIỀM NĂNG hoặc CHỐT ĐƠN · **B3** POS Cake đổi trạng thái (tiềm năng → Đã xác nhận, chốt → Đã gửi hàng) · **B4** khách chốt → tạo đơn Kiot, điền Mã KH Kiot vào ghi chú nội bộ Pancake; (3) hằng ngày dọn tab Nhập Liệu của app MKT/Sale.
- Page Sỉ luôn hỏi "dùng cho gia đình hay nhập sỉ" — khách trả lời gia đình / "thỉnh về an vị tại gia" là khách LẺ.
- **Gộp tên Sale:** chỉ khi tên ngắn nằm trọn trong tên dài và cùng chữ cuối ("Kim Oanh" ~ "Nguyễn Kim Oanh"). Khác họ / đệm là 2 người ("Bùi Thị Kim Oanh" ≠ "Đặng Thị Minh Oanh").
- Trùng SĐT = 1 người; tên KHÔNG dùng để nhận ra cùng người.
- Zalo là công Sale (không phải MKT).

### 5.8 Bảo mật (khoá 24/9/2026)
- Khoá công khai (anon) chỉ đọc được `product_faq`, `dash_presence`, `social_page_stats`. Mọi bảng khác cần phiên đăng nhập (JWT) hoặc khoá quản trị trong job.
- Đăng nhập app MKT/Sale: Edge Function `dang-nhap` → tài khoản bóng `<user_id>@mkt-sale.app` trong Supabase Auth (mật khẩu bóng cố định = HMAC khoá máy chủ + email). App QC dùng chung thì gọi cùng Edge Function; lưu ý phiên theo từng domain.
- Bảng mới BẮT BUỘC bật RLS. Hàm quản trị kiểm quyền trong CSDL bằng `la_quan_tri()`.
- Tài khoản thử chỉ tạo trong Supabase Auth, không tạo trong `sales_users` (sẽ lọt vào danh sách Sale), xoá ngay sau khi thử.

### 5.9 Công cụ trên máy này
- **Không có node / gh.** Chạy JS: `ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" file.js` (Node 24, có fetch). GitHub: gọi API với token ghp_ trong file khoá.
- SQL: Supabase Management API `POST https://api.supabase.com/v1/projects/bcrpxfvvjsjpvbksqzls/database/query` với token sbp_. Đọc bảng qua REST phải phân trang `limit/offset` (PostgREST trả tối đa 1000 dòng/lần).
- Script tạm để ở thư mục scratchpad của phiên, không để trong repo.
- Nếu Windows báo "An Application Control policy has blocked this file" khi git push → Smart App Control, không phải git hỏng.

## 6. QUY TẮC LÀM VIỆC (anh đã chốt — đừng hỏi lại)
- **Tự làm, không giao việc cho anh:** chạy SQL, deploy, cấu hình được thì tự làm rồi báo; lưu kèm file `supabase-schema-*.sql`. Chỉ nhờ anh khi thật sự bị chặn, nói rõ vì sao.
- **Commit:** trước mỗi commit chạy `git diff --cached --stat`, chỉ commit đúng file mình sửa; xong tự pull → commit → push. Chỉ commit trong repo qc-cskh.
- **Giao diện:** không icon emoji trang trí (chỉ icon SVG + ký hiệu nút ✏ ✓ ✕ ▶ ☰); không dòng chú thích dài dưới tiêu đề thẻ (dùng badge gọn); bảng số căn phải thẳng cột, tiêu đề cùng phía dữ liệu; 3 thẻ số liệu / hàng, nhóm liên quan cạnh nhau. Tên khách luôn kèm mã (Mã KH Kiot hoặc Lead ID).
- **Số liệu:** áp đúng bộ lọc nghiệp vụ rồi mới trình; dash mới phải đối chiếu với con số đã biết; thiếu dữ liệu KHÔNG phải là khớp; đổi logic chấm thì đo trước–sau bằng dữ liệu thật rồi mới báo xong. Bảng cũ còn giữ có chủ đích — kiểm trước khi nói "mất dữ liệu".
- Thao tác ra ngoài khó gỡ (gửi tin cho khách, tạo / sửa đơn Pancake hàng loạt): chạy thử chế độ xem trước, báo số cho anh trước.

## 7. CƠ CHẾ TỰ CHẠY & CẤU TRÚC APP
- **Trang:** `index.html` (1 file, GitHub Pages). Gọi RPC `qc_ds_cham`, `qc_hoi_thoai`, `qc_ds_bao_sai`, `qc_bao_sai`, `qc_xu_ly_bao_sai`, `qc_doi_ma` bằng khoá anon + mã truy cập. Hàm định nghĩa ở `supabase-schema-qc.sql` (đã áp 28/9). Hàm tự bỏ nhóm Zalo `pzl_g_`.
- **Số liệu khớp trang cũ:** mẫu số "đã chấm" = tất cả − `tra_loi_inbox` − `chua_cham` − `khong_lien_quan`; "Miss" = `chi_bot` + `khong_tra_loi`.
- **Công cụ:** `tools/sql.js` (chạy SQL qua Management API), `tools/ghi-cham.js` (ghi kết quả chấm, chỉ vào dòng `chua_cham`), `tools/keys.js` (đọc file khoá của mkt-sale-app, không in).
- **Job chấm:** vẫn là job cũ `sync-sale-review.yml` bên mkt-sale-app (3 lượt/ngày, 56 lượt chạy đều success tới 28/9). Repo này chưa có job.

## 8. NHẬT KÝ (mới nhất trước)
- **28/09/2026** — Anh chốt Q1–Q5 (mục 0). Dựng app v1: cổng mã truy cập bằng hàm CSDL (`supabase-schema-qc.sql`, đã áp + thử: mã sai 403, mã đúng ra 2.370 dòng = 2.502 − 132 dòng nhóm Zalo), trang `index.html` theo form cũ + thêm bảng theo Sale, agent Sonnet `cham-qc`. Xác nhận trang cũ Dashboard-Meta hỏng thật: đọc bảng bằng anon bị **401** (không phải mảng rỗng như em đoán trước). Tạo repo hh-vibecode/qc-cskh, bật Pages.
- **28/09/2026** — Khảo sát bước 1 (chỉ đọc), trình anh. Bảng chấm 2.502 dòng (22/8–27/9); chấm tay dừng sau 14/9 → 816 `chua_cham` (15–27/9); job cũ vẫn ghi hằng ngày. Lỗi thấy: 132 dòng nhóm Zalo `pzl_g_` lọt vào; không có dòng nào mang tên Sale đội Sỉ; 493 dòng trống tên Sale; tên page viết nhiều kiểu, bảng không có `page_id`; severity lẫn 2 hệ (Nghiêm trọng/Nhẹ và cao/trung/thap); `conv_date` theo ngày UTC (59 dòng 0–7h lệch ngày); báo chấm sai tự xoá sau 3 ngày (Edge Function `review-report`, không kiểm đăng nhập). Chờ anh trả lời Q1–Q5.
- **28/09/2026** — Tạo sổ khởi động (Monsieur Claude, phiên app MKT/Sale). Chép sẵn 16 mục bộ nhớ cần cho QC sang bộ nhớ của thư mục này. Chưa có code, chưa git init.

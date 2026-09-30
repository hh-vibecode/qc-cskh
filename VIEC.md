# SỔ VIỆC — app QC CSKH

> **Claude phải đọc file này ĐẦU MỖI PHIÊN.** Xong việc nào thì xoá khỏi mục ĐANG NỢ và ghi 1 dòng vào NHẬT KÝ.
> **Mọi phiên (máy anh / cloud / tài khoản Claude khác) TỰ GHI SỔ, không đợi anh dặn:** việc mới → ĐANG NỢ, anh chốt → ANH ĐÃ CHỐT,
> xong → NHẬT KÝ; ghi xong commit + push `main` ngay. Các phiên không đọc được hội thoại của nhau — chỉ đọc được sổ này.
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
| E2 | Ca Harri / Cáo: Sale không trả lời giá, chỉ xin SĐT chuyển Zalo, khách đồng ý → chấm `dung` hay `thieu`? | Sonnet chấm thieu (cao/trung); em đề xuất dung. Chốt xong áp cho mọi ca tương tự |
| E3 | Ngưỡng "trả lời muộn" khi kéo theo giờ: đang để ≥ 1 giờ | em tạm đặt 29/9 |
| E6 | "Ân hạn" trước khi ghi miss: câu hỏi chưa có Sale trả lời mà mới hỏi < 1 giờ thì lượt kéo chưa ghi, để lượt sau xét → trang không hiện miss tạm | em đề xuất 30/9, chờ anh chốt mốc (1 giờ?) |
| E5 | Người báo sai 30/9 ký tên **"Lệ"** (26 báo). Theo sổ, Phạm Thị Lệ là Sale đội Lẻ; trong dữ liệu 29/9 còn có tin nội bộ "e share c cái báo cáo này để nhắc các b đỡ miss tn" — báo cáo QC có đang được chia cho nhân sự không? (anh chốt 28/9: luồng ngầm, chỉ anh + GĐ) | anh xác nhận; cần thì em đổi mã truy cập |

## 2. CLAUDE ĐANG NỢ

| # | Việc | Ghi chú |
|---|---|---|
| 6 | Theo dõi độ khắt khe của Sonnet: đợt 15–27/9 ra 1,8% thiếu ý so với 7,4% đợt chấm tay trước 15/9 | soát mẫu thấy đúng luật, nhưng chênh lệch lớn — xem lại khi anh báo chấm sai |
| 3 | Báo cáo định kỳ qua email | chờ E1 |
| 7 | Chuyển hẳn kéo tin sang QC (mục 5c): đang ở bước 1–2 | 29/9 bắt đầu chạy song song |
| 9 | Đưa **tầng luật** vào job `keo-tin.yml` (soát miss ĐÃ đưa vào 30/9 qua `tools/soat-lib.js`) — cần viết lại `cham-luat.js` chạy bằng khoá `qc_cskh` (REST) thay Management API | để chấm cloud đỡ tốn |
| 11 | Sửa lệch quy ước (kiểm 29/9): (a) `soat-miss-pancake.js` ghi từng dòng → gộp 1 lệnh cả lô; (b) hàm `qc_*` đang `search_path = public, extensions` → đổi `public` + gọi `extensions.crypt()` rõ tên; (c) workflow `keo-tin.yml` → đổi tên `qc-keo-tin.yml` + sửa `qc_keo_tin` (đợi phiên cloud làm xong việc 9, tránh đè file); (d) file SQL `supabase-lich-keo.sql`, `supabase-cham-cloud.sql`, `supabase-qc-review-thu.sql`, `supabase-gioi-han-qc.sql` → tên `supabase-schema-qc-*.sql` | em tự làm |
| 10 | Chuyển việc làm hằng ngày sang phiên cloud: ĐÃ có `CLAUDE.md` + môi trường `QC Dev` (mạng Supabase / api.supabase.com / pancake.vn / api.github.com). Còn: anh dán 4 biến khoá vào `QC Dev` → mở phiên mới chạy thử (đọc khoá, gọi Supabase, Pancake, push main) | chờ anh dán khoá |

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

## 5b. DÙNG CHUNG VỚI APP MKT/SALE (lưu ý từ phiên đó, 29/9/2026 — BẮT BUỘC)
- **Khoá:** QC có secret key riêng `qc_cskh` (file `qc-keys.local.txt`, secret GitHub `QC_SUPABASE_KEY`). **KHÔNG BAO GIỜ tắt / đổi / xoay khoá legacy anon, legacy service_role, JWT secret** — app MKT/Sale + mọi job repo mkt-sale-app đang dùng.
- **Quota:** Supabase đã lên Pro (29/9) nhưng vẫn: đọc theo phần mới (conv_date / id lớn hơn mốc), không đọc lại cả bảng, không kéo `full_thread` hàng loạt; ghi theo lô (1 lệnh cả lô, `return=minimal`). Nếu dùng bảng `job_moc` thì tên job có tiền tố `qc-`.
- **Pancake chung token (hết hạn ~1/11/2026 → thay ở CẢ 2 repo):** QC chỉ ĐỌC (không gắn thẻ / tạo / sửa đơn). Nhịp gọi ≥150 ms, 429 thì nghỉ rồi thử lại. Tránh giờ bận của app MKT/Sale: tạo đơn 6h & 18h, phân loại SP 7h & 18h, ngày nhắn cuối phút 0–10 mỗi giờ, đồng bộ đơn mỗi 10 phút → QC kéo lúc **6h20 / 18h35**.
- **Không sửa cấu trúc / RLS / hàm** của: datahub_orders, saleretail_manual, salesi_crm, sales_users, sales_user_credentials, sale_nhan_su, job_moc, Edge Function dang-nhap, la_quan_tri(). Cần thì hỏi anh.
- **Không tự sửa repo mkt-sale-app.** Việc bên đó (tắt workflow cũ…) thì báo anh để phiên MKT/Sale làm.

## 5d. PHỤ THUỘC CHÉO (theo QUY-UOC-DUNG-CHUNG-SUPABASE.md mục 5 — việc cần app khác làm / báo anh chuyển lời)
| # | Việc | Cần ai | Trạng thái |
|---|---|---|---|
| X1 | Tắt workflow `sync-sale-review.yml` (job cũ ghi `sale_response_review`) | phiên MKT/Sale | **XONG 30/9** (anh báo) — job QC là nơi duy nhất ghi dữ liệu chấm |
| X2 | Quy ước mục 3.5/3.6 bảo "dữ liệu khách chỉ mở cho người đăng nhập, đăng nhập qua `dang-nhap`" — QC theo quyết định riêng của anh (28/9): KHÔNG tài khoản, trang + lịch chấm cloud gọi hàm `qc_*` bằng khoá anon + **mã truy cập / mã chấm** (băm trong `qc_cau_hinh`) | anh xác nhận để ghi ngoại lệ vào bản quy ước | chờ anh |
| X3 | Edge Function cũ `review-report` (Dashboard-Meta) vẫn có thể GHI + tự xoá > 3 ngày trong `sale_review_report` (bảng của QC) — trang cũ đã hỏng nên thực tế không ai gọi | để nguyên (Dashboard-Meta chỉ đọc) | ghi nhận |
| X4 | Lịch `qc-keo-gio` (phút :25) có thể trùng lúc app MKT/Sale quét toàn bộ Pancake 12h30 · 18h00 và tạo đơn / phân loại 18h | theo dõi 429; cần thì bỏ lượt 12h25 / 18h25 | theo dõi |

## 5c. CHUYỂN HẲN KÉO TIN + CHẤM SANG QC (anh muốn, 29/9) — thứ tự không hở dữ liệu
1. Job `keo-tin.yml` (repo qc-cskh) chạy xanh ≥ 1–2 ngày, ghi bảng thử `qc_review_thu` (pg_cron `qc-keo-6h` / `qc-keo-18h` kích).
2. Đối chiếu với job cũ cùng ngày theo từng page: `tools/doi-chieu.js <ngày>` — khớp hoặc giải thích được lệch.
3. Báo anh "QC chạy ổn" → **phiên MKT/Sale** tắt `sync-sale-review.yml` bên mkt-sale-app.
4. Từ lúc tắt: job QC ghi thẳng `sale_response_review` (đặt `BANG=sale_response_review` trong workflow), giữ đúng cột + verdict cũ (dung / thieu / sai / chi_bot / khong_tra_loi / tra_loi_inbox / chua_cham / khong_lien_quan). QC là nơi DUY NHẤT ghi dữ liệu chấm.

## 6. QUY TẮC LÀM VIỆC (anh đã chốt — đừng hỏi lại)
- **Quyền lâu dài (28/9/2026):** anh đã Allow `Bash(ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe":*)` và `Bash(git push:*)` cho repo này để Claude **tự xử lý việc định kỳ, không hỏi lại**. Lệnh phải bắt đầu đúng tiền tố đó (không `cd … &&` phía trước); push dùng `git -C C:/Users/HP/Desktop/qc-cskh push`.
- **Tự làm, không giao việc cho anh:** chạy SQL, deploy, cấu hình được thì tự làm rồi báo; lưu kèm file `supabase-schema-*.sql`. Chỉ nhờ anh khi thật sự bị chặn, nói rõ vì sao.
- **Commit:** trước mỗi commit chạy `git diff --cached --stat`, chỉ commit đúng file mình sửa; xong tự pull → commit → push. Chỉ commit trong repo qc-cskh.
- **Giao diện:** không icon emoji trang trí (chỉ icon SVG + ký hiệu nút ✏ ✓ ✕ ▶ ☰); không dòng chú thích dài dưới tiêu đề thẻ (dùng badge gọn); bảng số căn phải thẳng cột, tiêu đề cùng phía dữ liệu; 3 thẻ số liệu / hàng, nhóm liên quan cạnh nhau. Tên khách luôn kèm mã (Mã KH Kiot hoặc Lead ID).
- **Số liệu:** áp đúng bộ lọc nghiệp vụ rồi mới trình; dash mới phải đối chiếu với con số đã biết; thiếu dữ liệu KHÔNG phải là khớp; đổi logic chấm thì đo trước–sau bằng dữ liệu thật rồi mới báo xong. Bảng cũ còn giữ có chủ đích — kiểm trước khi nói "mất dữ liệu".
- Thao tác ra ngoài khó gỡ (gửi tin cho khách, tạo / sửa đơn Pancake hàng loạt): chạy thử chế độ xem trước, báo số cho anh trước.

## 7. CƠ CHẾ TỰ CHẠY & CẤU TRÚC APP
- **Trang:** `index.html` (1 file, GitHub Pages). Gọi RPC `qc_ds_cham`, `qc_hoi_thoai`, `qc_ds_bao_sai`, `qc_bao_sai`, `qc_xu_ly_bao_sai`, `qc_doi_ma` bằng khoá anon + mã truy cập. Hàm định nghĩa ở `supabase-schema-qc.sql` (đã áp 28/9). Hàm tự bỏ nhóm Zalo `pzl_g_`.
- **Số liệu khớp trang cũ:** mẫu số "đã chấm" = tất cả − `tra_loi_inbox` − `chua_cham` − `khong_lien_quan`; "Miss" = `chi_bot` + `khong_tra_loi`.
- **Chấm 2 tầng (anh chốt 28/9):** tầng 1 `tools/cham-luat.js --ghi` chốt ca hiển nhiên không tốn token (đo trên 1.984 dòng đã chấm: chốt 21,5%, lệch 0; mỗi luật mới phải đo `--do` ra lệch 0 mới được thêm); tầng 2 agent Sonnet `cham-qc` chỉ đọc phần còn lại. Cột `cham_boi` = `luat` | `sonnet` | `tay` (Claude soát tay) | null (job cũ / chấm tay trước 28/9). Dòng miss có `cham_boi` ≠ null = đã soát, không soát lại.
- **Lời khấn "Nam mô…" (anh chốt 28/9):** bỏ qua hết, coi là `khong_lien_quan`, không tính miss (luật `loi_khan`, áp cả dòng job gắn chi_bot/khong_tra_loi). Câu có ý hỏi / mua thì vẫn chấm.
- **Chạy hằng ngày sau job crawl (anh giao 28/9, tự làm không hỏi):**
  1. `tools/soat-miss-pancake.js` — mở lại Pancake cho mọi dòng miss: Sale trả lời sau lúc job chạy → `chua_cham` + issue "Trả lời muộn N giờ"; bình luận đã tư vấn ở inbox (xuyên ngày) → `tra_loi_inbox`. (Ca Lê Huyền #2443: Vân Ngọc trả lời muộn 36,9 giờ mà bị ghi "Không trả lời".)
  2. `tools/cham-luat.js --ghi` — luật (lời khấn, nội bộ, ca hiển nhiên).
  3. Agent `cham-qc` (Sonnet, lô 40; **tồn > 50 dòng thì chia 2–3 agent song song ngay từ đầu** — anh nhắc 28/9): chấm `chua_cham` còn lại + soát miss còn lại là **tương tác (bỏ) hay miss thật** (`ghi-cham.js --soat-miss`).
- **Chỉ quan tâm tin khách hỏi mua** (anh chốt 28/9): `khong_lien_quan` ẩn hẳn khỏi trang, không tính.
- **Cấu trúc trang (anh chốt 28/9):** menu trái như app MKT/Sale. Nhóm "Báo cáo" → *Chất lượng phản hồi*. Ghim đáy "Cài đặt" → *Lịch sử báo sai* (chờ xử lý + đã xử lý: trước → sau, cách xử lý) và *Logic xử lý dữ liệu*. Sau này thêm nhóm **Training** và **Chatbot** (anh sẽ dùng luồng này để build training + chatbot). Báo sai xử lý xong → đóng (`status='fixed'`, `resolve_note` ghi cách xử lý).
- **Nhân viên nội bộ đóng vai khách** → `khong_lien_quan` (kể cả dòng job gắn `khong_tra_loi`/`chi_bot`): Đức Tuấn + Đinh Ngọc Diệp (Chánh Tâm, SĐT 0973763458). Danh sách ở `NOI_BO_SDT`/`NOI_BO_TEN` trong `tools/cham-luat.js`.
- **Đẩy mã:** `tools/push.js`.
- **Công cụ:** `tools/sql.js` (chạy SQL qua Management API), `tools/ghi-cham.js` (ghi kết quả chấm, chỉ vào dòng `chua_cham`), `tools/keys.js` (đọc file khoá của mkt-sale-app, không in).
- **Job kéo tin:** từ 30/9 là job QC `.github/workflows/keo-tin.yml` (`scripts/keo-tin.js`) — ghi thẳng `sale_response_review`, là nơi DUY NHẤT ghi dữ liệu chấm (job cũ `sync-sale-review.yml` bên mkt-sale-app đã tắt 30/9). Anh chốt 30/9 giữ tần suất hiện tại. Lịch GitHub trễ 5–8 tiếng nên từ 29/9 **pg_cron của Supabase kích đúng giờ** (`supabase-lich-keo.sql`, hàm `qc_keo_tin`, token trong Vault tên `qc_gh_token`): anh chốt 29/9 "mỗi giờ, kéo tin và chấm cùng nhịp": **`qc-keo-gio` mỗi giờ phút :25** chế độ MỐC (chỉ hội thoại khách nhắn từ lượt trước; mốc ở `qc_cau_hinh` khoá `moc_keo:<bảng>`; dòng miss được cập nhật khi Sale trả lời sau, ≥ 1 giờ gắn "Trả lời muộn") + **2 lượt quét lớn** (anh chốt 30/9: "2 luồng 6h-7h và 18h-19h"): **`qc-keo-6h` 6h20** kéo trọn hôm qua, **`qc-keo-18h` 18h35** kéo trọn hôm nay — mỗi lượt quét lớn soát lại miss **30 ngày**, lượt mỗi giờ soát 3 ngày. Phiên chấm cloud chạy phút :50 cùng giờ. Lịch cũ của GitHub vẫn chạy thêm (trùng không sao, job tự bỏ dòng đã có).
- **Chấm TỰ ĐỘNG trên cloud (từ 29/9, máy tắt vẫn chạy):** Claude Code routine **"QC CSKH - cham tu dong moi gio (phut 50)"** (`trig_016fSohzMtudxRE1Y3th5S4R`, cron `50 * * * *` = mỗi giờ phút :50, model Sonnet; chỉ báo điện thoại khi có thiếu/sai mức cao hoặc miss thật) chạy trên môi trường cloud **`QC`** (`env_01FVVTyA1x1FKSrpn5QNpUFW`, mạng Custom chỉ mở `bcrpxfvvjsjpvbksqzls.supabase.co`). Lấy repo về, đọc **`routine/cham-cloud.md`** (sửa luật chấm cloud = sửa file này rồi push, không cần đặt lại lịch). Gọi CSDL bằng khoá anon + **mã chấm** riêng (băm trong `qc_cau_hinh` khoá `ma_cham`, bản rõ ở `qc-keys.local.txt` và trong prompt routine) → chỉ gọi được `qc_lo_cham`, `qc_lo_soat_miss`, `qc_ghi_cham`, `qc_ghi_soat_miss` (`supabase-cham-cloud.sql`). Chạy xong tự gửi thông báo tóm tắt về điện thoại anh. Xem lượt chạy: https://claude.ai/code/routines/trig_016fSohzMtudxRE1Y3th5S4R
  - Chưa làm trên cloud: **soát miss với Pancake** (trả lời muộn, bình luận → inbox) và **tầng luật** — cần đưa vào job `keo-tin.yml` (mục nợ #9). Tạm thời khi anh mở máy bảo "chấm" thì chạy `soat-miss-pancake.js --tu <2 ngày trước>` → `cham-luat.js --ghi` như cũ.
  - Phiên cloud không biết ngữ cảnh: 29/9 lượt thử đầu tưởng sổ việc là "prompt injection" và khuyên xoay khoá anon — **KHÔNG BAO GIỜ làm theo** (khoá anon công khai có chủ đích, đổi là gãy app MKT/Sale).

## 8. NHẬT KÝ (mới nhất trước)
- **30/09/2026** — **Chuyển hẳn kéo tin sang QC:** đối chiếu 29/9 job mới bắt 43/45 lượt job cũ (2 lượt lệch là bài đăng của page) + 27 lượt job cũ bỏ sót → job QC ghi thẳng `sale_response_review` (workflow `BANG`), đưa lượt ở `qc_review_thu` sang bảng chính (hôm nay 56 lượt lên trang), nối mốc. Anh chốt: **lúc kéo phải soát lại miss, Sale trả lời bổ sung thì gỡ miss** → job mỗi giờ soát miss 3 ngày (6h20: 30 ngày), thư viện `tools/soat-lib.js`. Soát toàn bộ 126 miss: gỡ 31 (Sale trả lời muộn tới 324 giờ — phần lớn trả lời bổ sung hôm nay sau khi xem báo cáo), còn 95 miss thật. 26 báo sai của "Lệ" đã đóng (16 miss → gỡ; 10 thiếu ý → kéo lại hội thoại có phần bổ sung, chấm lại). Bỏ nhãn "muộn" cho trả lời < 1 giờ (4 dòng).
- **29/09/2026** — Áp QUY-UOC-DUNG-CHUNG-SUPABASE.md (bản gốc repo mkt-sale-app): link + tóm tắt vào CLAUDE.md; kiểm lại: 4 bảng QC đều bật RLS, tên đều tiền tố `qc_`/`qc-`, không ghi bảng lõi MKT/Sale. Lệch → mục nợ #11 + Phụ thuộc chéo (mục 5d). Tạo `qc_sao_luu` + `qc_chup_sao_luu()` (bản đầu: 2.617 dòng, 621 KB).
- **29/09/2026** — Anh lên Supabase Pro (tổ chức). Anh chốt **giữ chung 1 project** (tách project thêm ~10 USD/tháng máy chủ) nhưng **tách phần xử lý**: đặt `statement_timeout` cho 13 hàm `qc_*` (`supabase-gioi-han-qc.sql`); trang vẫn tải bình thường (7 ngày ~0,9 s).
- **29/09/2026** — Anh chốt **4 thương hiệu: Chánh Tâm · Tự Tại Viên · Hiền Thủy · Shidai**, xếp theo MÃ PAGE (`BRAND_PAGE` trong index.html; Hoàng Dương - Ming Ying → Chánh Tâm; Zalo "Siêu Thị Đồ Thờ Cao Cấp" → Hiền Thủy — em xếp, chờ anh xác nhận). **Có page mới trên Pancake thì thêm vào `BRAND_PAGE`.** Bỏ ô lọc page (anh yêu cầu). Vá `page_id`: FB theo tên page (conv_id bình luận FB là mã BÀI ĐĂNG, không phải mã page), TikTok/Zalo theo conv_id. Đối chiếu bảng thương hiệu với SQL: khớp từng số.
- **29/09/2026** — Đặt lịch kéo tin 6h/18h bằng pg_cron (thử gọi GitHub 204). Chấm hằng ngày 27–28/9: luật 16 (8 nội bộ, 5 lời khấn), Sonnet 37 (29 đúng / 5 thiếu / 3 KLQ), soát miss 5 (3 lời khấn, 2 miss thật #2556, #2506). Tồn 0.
- **28/09/2026** — Sonnet xong: 46 dòng trả lời muộn (7 luật + 29 đúng / 8 thiếu / 2 KLQ) và soát 129 miss (117 miss thật, 12 tương tác). Soát tay sửa 2 dòng Sonnet loại nhầm: chị Nhung xin báo giá ở page Sỉ là khách sỉ thật (#2350 → đúng, #2413 → miss thật) — thêm luật vào `cham-qc.md`. Tồn: 0 `chua_cham`, 0 miss chưa soát (ngoài nhóm `pzl_g_`). Trang: full màn, 2 bảng tóm tắt gióng cột, ô tìm kiếm cùng hàng, chi tiết 30 dòng/trang có phân trang.
- **28/09/2026** — Anh báo 4 dòng chấm sai (lời khấn) → luật `loi_khan` bản 4 + sửa thêm 15 dòng; đóng 4 báo sai. Soát miss bằng Pancake thật (`soat-miss-pancake.js`): 176 dòng miss → 45 trả lời muộn (về chấm nội dung), 14 bình luận đã tư vấn ở inbox, 117 miss thật (đang cho Sonnet soát tương tác hay miss thật). Nội bộ thêm: tài khoản mang tên kho/thương hiệu nhắn nhau (sửa 6 dòng, trong đó 3 dòng Sonnet chấm nhầm "đúng"). Trang: menu trái, Cài đặt (Lịch sử báo sai + Logic xử lý), ngày đẩy phải, icon thẻ số, ẩn không liên quan, nhãn "muộn N giờ".
- **28/09/2026** — Anh chỉ ra lời khấn "Nam mô…" đang bị tính miss → thêm luật `loi_khan` (đo lệch 0/1.984), sửa 18 dòng `chi_bot` → `khong_lien_quan`.
- **28/09/2026** — Font trang → Montserrat (anh yêu cầu). Dựng chấm 2 tầng: `tools/cham-luat.js` (6 luật, lệch 0/1.984), cột `cham_boi`. Anh báo Đức Tuấn + Đinh Ngọc Diệp là nhân viên Chánh Tâm → sửa #2385 `khong_tra_loi` → `khong_lien_quan` (3 dòng kia Sonnet đã tự loại). Thừa nhận: đợt chấm tồn 15–27/9 Sonnet đọc hết 773 dòng (~740k token), chưa lọc bằng luật trước.
- **28/09/2026** — Anh cấp quyền lâu dài (mục 6). Đã tạo repo public hh-vibecode/qc-cskh, push, bật Pages → https://hh-vibecode.github.io/qc-cskh/ (remote không chứa token).
- **28/09/2026** — Chấm hết tồn 15–27/9 bằng Sonnet (3 lượt agent): 773 dòng → 750 đúng, 14 thiếu, 2 sai, 9 KLQ, 1 để lại. Soát tay: sửa 3 dòng `chi_bot` → `dung` (1830, 2000, 2001: người thật trả lời từ tài khoản chung PANCAKE THT HOLDING), bổ sung luật vào `cham-qc.md`. Lỗi job cũ thêm vào danh sách sửa: tin chào tự động khi khách bấm quảng cáo / "tin nhắn chào mừng tự động" đang bị tính là Sale.
- **28/09/2026** — Anh chốt Q1–Q5 (mục 0). Dựng app v1: cổng mã truy cập bằng hàm CSDL (`supabase-schema-qc.sql`, đã áp + thử: mã sai 403, mã đúng ra 2.370 dòng = 2.502 − 132 dòng nhóm Zalo), trang `index.html` theo form cũ + thêm bảng theo Sale, agent Sonnet `cham-qc`. Xác nhận trang cũ Dashboard-Meta hỏng thật: đọc bảng bằng anon bị **401** (không phải mảng rỗng như em đoán trước). Tạo repo hh-vibecode/qc-cskh, bật Pages.
- **28/09/2026** — Khảo sát bước 1 (chỉ đọc), trình anh. Bảng chấm 2.502 dòng (22/8–27/9); chấm tay dừng sau 14/9 → 816 `chua_cham` (15–27/9); job cũ vẫn ghi hằng ngày. Lỗi thấy: 132 dòng nhóm Zalo `pzl_g_` lọt vào; không có dòng nào mang tên Sale đội Sỉ; 493 dòng trống tên Sale; tên page viết nhiều kiểu, bảng không có `page_id`; severity lẫn 2 hệ (Nghiêm trọng/Nhẹ và cao/trung/thap); `conv_date` theo ngày UTC (59 dòng 0–7h lệch ngày); báo chấm sai tự xoá sau 3 ngày (Edge Function `review-report`, không kiểm đăng nhập). Chờ anh trả lời Q1–Q5.
- **28/09/2026** — Tạo sổ khởi động (Monsieur Claude, phiên app MKT/Sale). Chép sẵn 16 mục bộ nhớ cần cho QC sang bộ nhớ của thư mục này. Chưa có code, chưa git init.

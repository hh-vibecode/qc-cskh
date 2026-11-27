-- VIEW qc_khach_tiem_nang_ngay (app MKT đọc) — THÊM luật tin xác nhận (anh Hải chốt 27/11/2026, xem supabase-schema-qc-xac-nhan.sql):
-- có tin Sale xác nhận lại (qc_xac_nhan.la_xac_nhan), khách chưa nhắn gì sau đó, đã đủ 48 giờ → nhom = dat,
-- ly_do_nhom "Sale xác nhận lại, khách không phản hồi sau 2 ngày". Thêm cột CUỐI xac_nhan_luc (giờ VN của tin xác nhận mới nhất)
-- để app MKT đổi thẻ / trạng thái kể cả khi Sale đã chăm sóc. Cột cũ giữ nguyên tên + thứ tự. Đo 27/11: 0,14 s như bản cũ,
-- 195 dòng trùng khớp bản cũ khi chưa có tin xác nhận. Monsieur Claude
create or replace view public.qc_khach_tiem_nang_ngay with (security_invoker = true) as
 WITH k AS (
         SELECT k.ngay,
            k.review_id,
            k.ket,
            k.ly_do,
            k.danh_gia_luc,
            k.loai_khach
           FROM qc_khach_tiem_nang k
          WHERE (NOT (EXISTS ( SELECT 1
                   FROM qc_khach_tiem_nang k2
                  WHERE ((k2.review_id = k.review_id) AND ((k2.ngay > k.ngay) OR ((k2.ngay = k.ngay) AND (k2.danh_gia_luc > k.danh_gia_luc)))))))
        ), x AS (
         SELECT k.ngay,
            k.ket,
            k.ly_do,
            k.danh_gia_luc,
            k.loai_khach AS k_loai_khach,
            s.id,
            s.conv_date,
            s.page_name,
            s.conv_id,
            s.customer_name,
            s.phone,
            s.sale_name,
            s.customer_ask,
            s.sale_reply,
            s.verdict,
            s.issue,
            s.suggestion,
            s.severity,
            s.source_faq,
            s.reviewed_at,
            s.conv_at,
            s.full_thread,
            s.pancake_url,
            s.cham_boi,
            s.page_id,
            s.sai_quy_trinh,
            s.tg_phan_hoi_tb,
            s.tg_phan_hoi_max,
            s.tg_ngoai_gio,
            s.khach_id,
            s.noi_bo,
            c.review_id AS ckt_id,
            c.ly_do AS ckt_ly_do,
            xn.tin_luc AS xn_luc,
            ((xn.tin_luc IS NOT NULL) AND (tc.m[2] = 'Sale'::text) AND ((tc.m[1])::timestamp without time zone >= xn.tin_luc) AND (xn.tin_luc <= ((now() AT TIME ZONE 'Asia/Ho_Chi_Minh'::text) - '2 days'::interval))) AS xn_qua_han,
            (tc.m[1])::timestamp without time zone AS tin_cuoi,
            tc.m[2] AS ai_cuoi,
            ((bg.bao_gia_n IS NOT NULL) AND (COALESCE(bg.khach_n, (0)::bigint) < bg.bao_gia_n)) AS im_sau_bao_gia,
            ((bg.sale_n IS NOT NULL) AND (COALESCE(bg.khach_n, (0)::bigint) < bg.sale_n) AND ((bg.sale_ts)::timestamp without time zone < ((now() AT TIME ZONE 'Asia/Ho_Chi_Minh'::text) - '7 days'::interval))) AS khach_dung,
            (((now() AT TIME ZONE 'Asia/Ho_Chi_Minh'::text))::date - ((bg.sale_ts)::timestamp without time zone)::date) AS ngay_im_sale,
            (COALESCE(bg.khach_n, (0)::bigint) > COALESCE(bg.sale_n, (0)::bigint)) AS khach_cho
           FROM (((((k
             JOIN sale_response_review s ON ((s.id = k.review_id)))
             LEFT JOIN LATERAL ( SELECT c_1.review_id,
                    c_1.ly_do
                   FROM qc_chua_khai_thac c_1
                  WHERE ((c_1.review_id = s.id) AND c_1.ket AND (NOT (EXISTS ( SELECT 1
                           FROM regexp_matches("right"(s.full_thread, 3000), '\[(\d{4}-\d\d-\d\d \d\d:\d\d)\] (?!Bot:)'::text, 'g'::text) m(m)
                          WHERE ((m.m[1])::timestamp without time zone > c_1.tin_cuoi_luc)))))
                  ORDER BY c_1.tin_cuoi_luc DESC
                 LIMIT 1) c ON (true))
             LEFT JOIN LATERAL ( SELECT regexp_match("right"(s.full_thread, 4000), '.*\[(\d{4}-\d\d-\d\d \d\d:\d\d)\] (Khách|Sale)'::text, 's'::text) AS m) tc ON (true))
             LEFT JOIN LATERAL ( SELECT max(t_1.n) FILTER (WHERE (t_1.l ~ '^\[[^]]+\] Sale[^:]*:[^\n]*(\d+([.,]\d+)?\s*(tr\M|triệu|k\M|nghìn|ngàn)|\d{1,3}([.,]\d{3}){1,2}\s*(đ|vnđ|vnd|\M))'::text)) AS bao_gia_n,
                    max(t_1.n) FILTER (WHERE ((t_1.l ~ '^\[[^]]+\] Khách: '::text) AND (NOT ((length(t_1.l) <= 50) AND (t_1.l !~ '\?'::text) AND (substr(t_1.l, 27) ~* '^\W*(dạ|vâng|ok|oke|okie|ừ|uk|vang|da|à|e|em|mình|cảm ơn|cám ơn|thank|thanks|tks|\(sticker\)|\s|,|\.|!|ạ|nhé|nha|shop|bạn|c|chị|anh)*\W*$'::text))))) AS khach_n,
                    max(t_1.n) FILTER (WHERE (t_1.l ~ '^\[[^]]+\] Sale'::text)) AS sale_n,
                    (array_agg(substr(t_1.l, 2, 16) ORDER BY t_1.n DESC) FILTER (WHERE (t_1.l ~ '^\[[^]]+\] Sale'::text)))[1] AS sale_ts
                   FROM regexp_split_to_table("right"(s.full_thread, 6000), '\n'::text) WITH ORDINALITY t_1(l, n)) bg ON (true))
             LEFT JOIN LATERAL ( SELECT q.tin_luc FROM qc_xac_nhan q WHERE ((q.review_id = s.id) AND q.la_xac_nhan) ORDER BY q.tin_luc DESC LIMIT 1) xn ON (true))
          WHERE ((k.ket = ANY (ARRAY['tiem_nang'::text, 'tu_choi'::text])) OR ((k.ket = 'chua_du'::text) AND (c.review_id IS NOT NULL)))
        ), y AS (
         SELECT x.ngay,
            x.ket,
            x.ly_do,
            x.danh_gia_luc,
            x.k_loai_khach,
            x.id,
            x.conv_date,
            x.page_name,
            x.conv_id,
            x.customer_name,
            x.phone,
            x.sale_name,
            x.customer_ask,
            x.sale_reply,
            x.verdict,
            x.issue,
            x.suggestion,
            x.severity,
            x.source_faq,
            x.reviewed_at,
            x.conv_at,
            x.full_thread,
            x.pancake_url,
            x.cham_boi,
            x.page_id,
            x.sai_quy_trinh,
            x.tg_phan_hoi_tb,
            x.tg_phan_hoi_max,
            x.tg_ngoai_gio,
            x.khach_id,
            x.noi_bo,
            x.ckt_id,
            x.ckt_ly_do,
            x.tin_cuoi,
            x.ai_cuoi,
            x.im_sau_bao_gia,
            x.khach_dung,
            x.ngay_im_sale,
            x.khach_cho,
            x.xn_luc,
            x.xn_qua_han,
            (((now() AT TIME ZONE 'Asia/Ho_Chi_Minh'::text))::date - (x.tin_cuoi)::date) AS ngay_im,
                CASE
                    WHEN (x.verdict = 'loi_nen_tang'::text) THEN 'dat'::text
                    WHEN (x.ckt_id IS NOT NULL) THEN 'tiem_nang'::text
                    WHEN (x.ket = 'tu_choi'::text) THEN 'dat'::text
                    WHEN x.xn_qua_han THEN 'dat'::text
                    WHEN x.im_sau_bao_gia THEN 'dat'::text
                    WHEN x.khach_dung THEN 'dat'::text
                    ELSE 'tiem_nang'::text
                END AS nhom
           FROM x
        )
 SELECT y.ngay,
    y.ket,
        CASE
            WHEN (y.verdict = 'loi_nen_tang'::text) THEN ('Lỗi nền tảng (không do Sale): '::text || COALESCE(NULLIF(y.issue, ''::text), 'không gửi được tin cho khách'::text))
            ELSE y.ly_do
        END AS ly_do,
    y.danh_gia_luc,
        CASE
            WHEN (y.page_id ~~ 'pzl\_%'::text) THEN 'zalo'::text
            WHEN (y.page_id ~~ 'ttm\_%'::text) THEN 'tiktok'::text
            ELSE 'facebook'::text
        END AS nen_tang,
    y.page_name AS kenh,
    y.page_id,
    y.conv_id AS pancake_conversation_id,
    COALESCE(y.khach_id, NULLIF(regexp_replace(y.conv_id, '^pzl_u_\d+_'::text, ''::text), y.conv_id)) AS khach_id,
    y.customer_name AS ten_khach,
    y.phone AS sdt,
    t.ten_nhan_su AS sale,
    y.sale_name AS sale_qc,
    y.pancake_url,
    (y.ckt_id IS NOT NULL) AS chua_khai_thac,
    y.ckt_ly_do AS ly_do_chua_khai_thac,
    y.nhom,
        CASE
            WHEN (y.verdict = 'loi_nen_tang'::text) THEN 'Lỗi nền tảng: không gửi được tin cho khách'::text
            WHEN (y.ckt_id IS NOT NULL) THEN 'Chưa khai thác hết (lỗi Sale)'::text
            WHEN ((y.ket = 'tu_choi'::text) AND (y.ly_do ~* 'đã mua|không mua|thôi không|cũng không có tiền'::text)) THEN 'Khách từ chối hẳn'::text
            WHEN ((y.ket = 'tu_choi'::text) AND (y.ly_do ~* 'đắt|cao quá|cao vậy|giá cao|so (chỗ|giá)|rẻ hơn|đủ tiền|đủ kinh tế'::text)) THEN 'Chê giá / chưa đủ tiền'::text
            WHEN ((y.ket = 'tu_choi'::text) AND (y.ly_do ~* 'không có|chỉ có|chỉ còn|khác mẫu|chưa ưng|không ưng'::text)) THEN 'Không có đúng hàng / chưa ưng mẫu'::text
            WHEN (y.ket = 'tu_choi'::text) THEN 'Khách từ chối'::text
            WHEN y.xn_qua_han THEN 'Sale xác nhận lại, khách không phản hồi sau 2 ngày'::text
            WHEN y.im_sau_bao_gia THEN 'Báo giá xong khách chưa phản hồi'::text
            WHEN y.khach_dung THEN (('Khách dừng: im '::text || y.ngay_im_sale) || ' ngày sau tin Sale'::text)
            WHEN y.khach_cho THEN 'Đang mở: khách hỏi, chờ Sale'::text
            ELSE 'Đang mở: Sale đã đáp, chờ khách'::text
        END AS ly_do_nhom,
    y.tin_cuoi AS tin_cuoi_luc,
    y.ngay_im,
    COALESCE(y.k_loai_khach,
        CASE
            WHEN (NOT qc_page_si(y.page_name)) THEN 'le'::text
            ELSE NULL::text
        END) AS loai_khach,
    y.xn_luc AS xac_nhan_luc
   FROM (y
     LEFT JOIN qc_sale_ten t ON ((t.ten_pancake = y.sale_name)))
  WHERE (((y.verdict <> 'khong_lien_quan'::text) OR (y.verdict IS NULL)) AND (NOT COALESCE(y.noi_bo, false)));
grant select on public.qc_khach_tiem_nang_ngay to authenticated;

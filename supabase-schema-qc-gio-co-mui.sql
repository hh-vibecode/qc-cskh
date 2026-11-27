-- THỐNG NHẤT GIỜ GIỮA 2 APP (anh Hải chốt 27/11/2026 qua app MKT: "m bảo nó vs m thống nhất về giờ đi", "giờ vn hết đi";
-- QUY-UOC-DUNG-CHUNG-SUPABASE.md mục 3 luật 10): mọi mốc giờ hiểu là giờ VN; cột GIỜ trên bảng / view dùng chung là timestamptz.
-- 4 cột QC đang là timestamp không múi (giá trị = giờ VN đọc từ dòng thread) → timestamptz, giữ tên + thứ tự, cùng thời điểm thật:
--   qc_xac_nhan.tin_luc · qc_chua_khai_thac.tin_cuoi_luc · view qc_khach_tiem_nang_ngay.tin_cuoi_luc + xac_nhan_luc.
-- Hàm đi kèm: qc_gio_vn(text) đọc chuỗi giờ — có múi thì giữ, không múi thì hiểu là giờ VN (lịch cloud gửi lại giá trị cũ vẫn đúng).
-- So giờ thread với cột: (dòng thread)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh'.
-- Chạy trong 1 transaction (đổi kiểu cột view phải drop / tạo lại). Chạy lại supabase-gioi-han-qc.sql sau file này. Monsieur Claude
begin;
insert into qc_sao_luu (ly_do, bang, so_dong, du_lieu)
select 'Trước khi đổi tin_cuoi_luc sang timestamptz (27/11)', 'qc_chua_khai_thac', count(*), coalesce(jsonb_agg(to_jsonb(c)), '[]'::jsonb)
from qc_chua_khai_thac c;

create or replace function public.qc_gio_vn(p text) returns timestamptz
language sql stable set search_path = public as $$
  select case when p is null or trim(p) = '' then null
              when trim(p) ~ '([zZ]|[+-]\d\d(:?\d\d)?)$' then trim(p)::timestamptz
              else trim(p)::timestamp at time zone 'Asia/Ho_Chi_Minh' end
$$;

drop view public.qc_khach_tiem_nang_ngay;
alter table public.qc_xac_nhan alter column tin_luc type timestamptz using tin_luc at time zone 'Asia/Ho_Chi_Minh';
alter table public.qc_chua_khai_thac alter column tin_cuoi_luc type timestamptz using tin_cuoi_luc at time zone 'Asia/Ho_Chi_Minh';

create view public.qc_khach_tiem_nang_ngay with (security_invoker = true) as
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
            ((xn.tin_luc IS NOT NULL) AND (tc.m[2] = 'Sale'::text) AND (((tc.m[1])::timestamp without time zone AT TIME ZONE 'Asia/Ho_Chi_Minh'::text) >= xn.tin_luc) AND (xn.tin_luc <= (now() - '2 days'::interval))) AS xn_qua_han,
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
                          WHERE (((m.m[1])::timestamp without time zone AT TIME ZONE 'Asia/Ho_Chi_Minh'::text) > c_1.tin_cuoi_luc)))))
                  ORDER BY c_1.tin_cuoi_luc DESC
                 LIMIT 1) c ON (true))
             LEFT JOIN LATERAL ( SELECT regexp_match("right"(s.full_thread, 4000), '.*\[(\d{4}-\d\d-\d\d \d\d:\d\d)\] (Khách|Sale)'::text, 's'::text) AS m) tc ON (true))
             LEFT JOIN LATERAL ( SELECT max(t_1.n) FILTER (WHERE (t_1.l ~ '^\[[^]]+\] Sale[^:]*:[^\n]*(\d+([.,]\d+)?\s*(tr\M|triệu|k\M|nghìn|ngàn)|\d{1,3}([.,]\d{3}){1,2}\s*(đ|vnđ|vnd|\M))'::text)) AS bao_gia_n,
                    max(t_1.n) FILTER (WHERE ((t_1.l ~ '^\[[^]]+\] Khách: '::text) AND (NOT ((length(t_1.l) <= 50) AND (t_1.l !~ '\?'::text) AND (substr(t_1.l, 27) ~* '^\W*(dạ|vâng|ok|oke|okie|ừ|uk|vang|da|à|e|em|mình|cảm ơn|cám ơn|thank|thanks|tks|\(sticker\)|\s|,|\.|!|ạ|nhé|nha|shop|bạn|c|chị|anh)*\W*$'::text))))) AS khach_n,
                    max(t_1.n) FILTER (WHERE (t_1.l ~ '^\[[^]]+\] Sale'::text)) AS sale_n,
                    (array_agg(substr(t_1.l, 2, 16) ORDER BY t_1.n DESC) FILTER (WHERE (t_1.l ~ '^\[[^]]+\] Sale'::text)))[1] AS sale_ts
                   FROM regexp_split_to_table("right"(s.full_thread, 6000), '\n'::text) WITH ORDINALITY t_1(l, n)) bg ON (true))
             LEFT JOIN LATERAL ( SELECT q.tin_luc
                   FROM qc_xac_nhan q
                  WHERE ((q.review_id = s.id) AND q.la_xac_nhan)
                  ORDER BY q.tin_luc DESC
                 LIMIT 1) xn ON (true))
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
    (y.tin_cuoi AT TIME ZONE 'Asia/Ho_Chi_Minh'::text) AS tin_cuoi_luc,
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

drop function public.qc_ckt_ung_vien(int);
create function public.qc_ckt_ung_vien(p_so integer default 60)
 returns table(id bigint, page_name text, customer_name text, sale_name text, verdict text, tin_cuoi_luc timestamptz, phut_cho integer, doan_cuoi text)
 language sql stable security definer set search_path = public, extensions as $$
  with tn as (select distinct on (review_id) review_id, ket from qc_khach_tiem_nang order by review_id, ngay desc, danh_gia_luc desc),
  s as (select s.id, s.page_name, s.customer_name, s.sale_name, s.verdict,
               array(select l from regexp_split_to_table(s.full_thread, E'\n') with ordinality x(l, n)
                     where l ~ '^\[\d{4}-\d\d-\d\d \d\d:\d\d\] ' and l !~ '^\[[^]]+\] Bot:' order by n) ls
        from sale_response_review s join tn on tn.review_id = s.id
        where tn.ket in ('tiem_nang', 'chua_du') and s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false)
          and s.conv_id not like 'pzl\_%'),   -- chỉ Social (20/11)
  c as (select s.*, substr(ls[cardinality(ls)], 2, 16)::timestamp tc_vn from s
        where cardinality(ls) > 0 and ls[cardinality(ls)] ~ '^\[[^]]+\] Sale')
  select c.id, c.page_name, c.customer_name, c.sale_name, c.verdict, c.tc_vn at time zone 'Asia/Ho_Chi_Minh',
         qc_phut_lam_viec(c.tc_vn, (now() at time zone 'Asia/Ho_Chi_Minh')::timestamp)::int,
         array_to_string(c.ls[greatest(1, cardinality(c.ls) - 9):cardinality(c.ls)], E'\n')
  from c
  where qc_phut_lam_viec(c.tc_vn, (now() at time zone 'Asia/Ho_Chi_Minh')::timestamp) > 570
    and not exists (select 1 from qc_chua_khai_thac k where k.review_id = c.id and k.tin_cuoi_luc = c.tc_vn at time zone 'Asia/Ho_Chi_Minh')
  order by c.id limit least(greatest(p_so, 1), 1000)
$$;
revoke execute on function public.qc_ckt_ung_vien(int) from public, anon, authenticated;

drop function public.qc_ckt_dang_mo(int);
create function public.qc_ckt_dang_mo(p_so integer default 40)
 returns table(id bigint, page_name text, customer_name text, sale_name text, verdict text, tin_cuoi_luc timestamptz, ly_do_cu text, danh_gia_luc timestamptz, doan_cuoi text)
 language sql stable security definer set search_path = public, extensions as $$
  with c as (select distinct on (review_id) review_id, tin_cuoi_luc, ket, ly_do, danh_gia_luc
             from qc_chua_khai_thac order by review_id, tin_cuoi_luc desc)
  select s.id, s.page_name, s.customer_name, s.sale_name, s.verdict, c.tin_cuoi_luc, c.ly_do, c.danh_gia_luc,
         array_to_string(array(select l from (select l, n from regexp_split_to_table(s.full_thread, E'\n') with ordinality x(l, n)
                                              where l ~ '^\[\d{4}-\d\d-\d\d \d\d:\d\d\] ' and l !~ '^\[[^]]+\] Bot:'
                                              order by n desc limit 12) t order by n), E'\n')
  from c join sale_response_review s on s.id = c.review_id
  where c.ket and s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false)
    and c.danh_gia_luc < now() - interval '20 hours'
    and not exists (select 1 from regexp_matches(right(s.full_thread, 3000), '\[(\d{4}-\d\d-\d\d \d\d:\d\d)\] (?!Bot:)', 'g') m(m)
                    where m.m[1]::timestamp at time zone 'Asia/Ho_Chi_Minh' > c.tin_cuoi_luc)
  order by c.danh_gia_luc limit least(greatest(p_so, 1), 200)
$$;
revoke execute on function public.qc_ckt_dang_mo(int) from public, anon, authenticated;

-- Lô / ghi tin xác nhận: tin_luc trả về và nhận lại dạng có múi (nhận cả chuỗi không múi = giờ VN)
create or replace function public.qc_lo_xac_nhan(p_ma text, p_so int default 40) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(u)) from (
    with v as (select distinct pancake_conversation_id from qc_khach_tiem_nang_ngay where nhom = 'tiem_nang' and not chua_khai_thac),
    s as (select s.id, s.page_name, s.customer_name, s.sale_name,
                 array(select l from regexp_split_to_table(right(s.full_thread, 6000), E'\n') with ordinality x(l, n)
                       where l ~ '^\[\d{4}-\d\d-\d\d \d\d:\d\d\] ' and l !~ '^\[[^]]+\] Bot:' order by n) ls
          from sale_response_review s join v on v.pancake_conversation_id = s.conv_id
          where s.conv_date >= date '2026-10-01'),
    t as (select s.*, substr(ls[cardinality(ls)], 2, 16)::timestamp at time zone 'Asia/Ho_Chi_Minh' as tl
          from s where cardinality(ls) > 0 and ls[cardinality(ls)] ~ '^\[[^]]+\] Sale')
    select t.id, t.page_name, t.customer_name, t.sale_name, t.tl as tin_luc,
           array_to_string(t.ls[greatest(1, cardinality(t.ls) - 11):cardinality(t.ls)], E'\n') as doan_cuoi
    from t
    where not exists (select 1 from qc_xac_nhan q where q.review_id = t.id and q.tin_luc = t.tl)
    order by t.id limit least(greatest(p_so, 1), 60)) u), '[]'::jsonb);
end $$;

create or replace function public.qc_ghi_xac_nhan(p_ma text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  perform qc_chan_cham(p_ma);
  insert into qc_xac_nhan (review_id, tin_luc, la_xac_nhan, ly_do)
  select (x->>'id')::bigint, qc_gio_vn(x->>'tin_luc'), (x->>'la_xac_nhan')::boolean, trim(x->>'ly_do')
  from jsonb_array_elements(p_rows) x
  where x->>'la_xac_nhan' in ('true', 'false') and coalesce(trim(x->>'ly_do'), '') <> '' and x->>'tin_luc' is not null
  on conflict (review_id, tin_luc) do update set la_xac_nhan = excluded.la_xac_nhan, ly_do = excluded.ly_do, danh_gia_luc = now();
  get diagnostics n = row_count;
  return jsonb_build_object('ghi', n);
end $$;

-- Ghi chưa khai thác hết: tin_cuoi_luc đọc bằng qc_gio_vn (lịch cloud gửi lại đúng giá trị lô đưa — nay có múi)
create or replace function public.qc_ghi_ckt(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n int; m int; g int := 0; v_go bigint[];
begin
  -- mốc đang ket=true mà lần này ghi false = kết luận cũ sai (xét lại) → nhớ để gỡ lỗi Sale
  select coalesce(array_agg(distinct c.review_id), '{}') into v_go
  from jsonb_array_elements(p_rows) x
  join qc_chua_khai_thac c on c.review_id = (x->>'id')::bigint and c.tin_cuoi_luc = qc_gio_vn(x->>'tin_cuoi_luc') and c.ket
  where x->>'ket' = 'false' and coalesce(trim(x->>'ly_do'), '') <> '';

  insert into qc_chua_khai_thac (review_id, tin_cuoi_luc, ket, ly_do)
  select (x->>'id')::bigint, qc_gio_vn(x->>'tin_cuoi_luc'), (x->>'ket')::boolean, trim(x->>'ly_do')
  from jsonb_array_elements(p_rows) x
  where coalesce(trim(x->>'ly_do'), '') <> '' and x->>'ket' in ('true', 'false')
  on conflict (review_id, tin_cuoi_luc) do update set ket = excluded.ket, ly_do = excluded.ly_do, danh_gia_luc = now();
  get diagnostics n = row_count;

  update sale_response_review s set
      verdict = case when s.verdict = 'dung' then 'thieu' else s.verdict end,
      severity = case when s.verdict = 'dung' then 'trung' else s.severity end,
      issue = case when s.verdict = 'dung' then 'Chưa khai thác hết: ' || x.ly_do
                   else coalesce(s.issue || ' · ', '') || 'Chưa khai thác hết: ' || x.ly_do end,
      suggestion = case when s.verdict = 'dung' then coalesce(s.suggestion, 'Hứa kiểm tra / gửi thêm thì phải quay lại trả lời khách trong ngày làm việc, kể cả khi hết hàng — đưa mẫu thay thế.') else s.suggestion end,
      reviewed_at = now()
  from (select (x->>'id')::bigint id, trim(x->>'ly_do') ly_do from jsonb_array_elements(p_rows) x where x->>'ket' = 'true') x
  where s.id = x.id and coalesce(s.issue, '') not like '%Chưa khai thác hết:%';
  get diagnostics m = row_count;

  -- gỡ lỗi Sale khi không còn mốc ket=true nào của dòng đó. Trả về dung CHỈ khi dấu vết cho thấy dòng vốn dung
  -- (issue mở đầu "Chưa khai thác hết:", mức trung, gợi ý mặc định của thẻ); còn lại chỉ cắt phần " · Chưa khai thác hết: …".
  if cardinality(v_go) > 0 then
    update sale_response_review s set
        verdict = case when b.goc_dung then 'dung' else s.verdict end,
        severity = case when b.goc_dung then null else s.severity end,
        suggestion = case when b.goc_dung then null else s.suggestion end,
        issue = case when b.goc_dung then null
                     else nullif(regexp_replace(s.issue, '( · )?Chưa khai thác hết: .*$', ''), '') end,
        reviewed_at = now()
    from (select s2.id, (s2.verdict = 'thieu' and s2.issue like 'Chưa khai thác hết:%' and s2.severity = 'trung'
                         and coalesce(s2.suggestion, '') like 'Hứa kiểm tra / gửi thêm%') goc_dung
          from sale_response_review s2 where s2.id = any(v_go)) b
    where s.id = b.id and s.issue like '%Chưa khai thác hết:%'
      and not exists (select 1 from qc_chua_khai_thac c where c.review_id = s.id and c.ket);
    get diagnostics g = row_count;
  end if;
  return jsonb_build_object('ghi', n, 'loi_sale', m, 'go_loi', g);
end $$;
revoke execute on function public.qc_ghi_ckt(jsonb) from public, anon, authenticated;
commit;

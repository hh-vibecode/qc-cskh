-- CHƯA KHAI THÁC HẾT (anh Hải chốt 20/11/2026, ca Thiện Minh — Sale "để em kiểm tra lại kho" 03/11 rồi tới nay không phản hồi):
-- "mấy data như này gắn thêm thẻ chưa khai thác hết … cái này là lỗi sale … vừa gắn thẻ lỗi vừa gắn thẻ chưa khai thác hết" + "rà lại tất cả data tương tự".
-- Ứng viên (máy lọc trước): hội thoại đã báo giá (có đánh giá tiềm năng, kết quả mới nhất tiem_nang / chua_du), tin cuối (bỏ Bot) là của Sale,
-- đã quá 1 ngày làm việc (570 phút 8h–17h30) không có tin nào sau. AI đọc đoạn cuối → ket = true khi Sale còn NỢ khách một việc
-- (hứa kiểm kho / hỏi lại / gửi ảnh / báo giá sau…, hoặc khách vừa hỏi phương án mà Sale chỉ "dạ để em xem") rồi bỏ lửng.
-- ket = true → (1) thẻ "chưa khai thác hết" (bảng này, view qc_khach_tiem_nang_ngay cột chua_khai_thac) và (2) LỖI SALE: dòng chấm đúng → thieu.
-- Mỗi (review_id, tin_cuoi_luc) chỉ xét 1 lần; Sale nhắn tiếp thì tin cuối đổi → xét lại. Monsieur Claude
create table if not exists qc_chua_khai_thac (
  review_id bigint not null,
  tin_cuoi_luc timestamp not null,          -- giờ VN của tin Sale cuối (mốc bỏ lửng)
  ket boolean not null,                      -- true = chưa khai thác hết (lỗi Sale)
  ly_do text not null,
  danh_gia_luc timestamptz not null default now(),
  primary key (review_id, tin_cuoi_luc)
);
alter table qc_chua_khai_thac enable row level security;
drop policy if exists qc_chua_khai_thac_doc on qc_chua_khai_thac;
create policy qc_chua_khai_thac_doc on qc_chua_khai_thac for select to authenticated using (true);

-- Ứng viên (không chặn mã — chỉ quản trị gọi trực tiếp; cloud gọi qua qc_lo_chua_khai_thac)
create or replace function public.qc_ckt_ung_vien(p_so int default 60) returns table (
  id bigint, page_name text, customer_name text, sale_name text, verdict text, tin_cuoi_luc timestamp, phut_cho int, doan_cuoi text)
language sql stable security definer set search_path = public, extensions as $$
  with tn as (select distinct on (review_id) review_id, ket from qc_khach_tiem_nang order by review_id, ngay desc, danh_gia_luc desc),
  s as (select s.id, s.page_name, s.customer_name, s.sale_name, s.verdict,
               array(select l from regexp_split_to_table(s.full_thread, E'\n') with ordinality x(l, n)
                     where l ~ '^\[\d{4}-\d\d-\d\d \d\d:\d\d\] ' and l !~ '^\[[^]]+\] Bot:' order by n) ls
        from sale_response_review s join tn on tn.review_id = s.id
        where tn.ket in ('tiem_nang', 'chua_du') and s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false)),
  c as (select s.*, substr(ls[cardinality(ls)], 2, 16)::timestamp tc from s
        where cardinality(ls) > 0 and ls[cardinality(ls)] ~ '^\[[^]]+\] Sale')
  select c.id, c.page_name, c.customer_name, c.sale_name, c.verdict, c.tc,
         qc_phut_lam_viec(c.tc, (now() at time zone 'Asia/Ho_Chi_Minh')::timestamp)::int,
         array_to_string(c.ls[greatest(1, cardinality(c.ls) - 9):cardinality(c.ls)], E'\n')
  from c
  where qc_phut_lam_viec(c.tc, (now() at time zone 'Asia/Ho_Chi_Minh')::timestamp) > 570
    and not exists (select 1 from qc_chua_khai_thac k where k.review_id = c.id and k.tin_cuoi_luc = c.tc)
  order by c.id limit least(greatest(p_so, 1), 1000)
$$;
revoke execute on function public.qc_ckt_ung_vien(int) from public, anon, authenticated;

-- Ghi kết quả (dùng chung cho máy và cloud): p_rows = [{id, tin_cuoi_luc, ket: true|false, ly_do}]
-- ket = true: dòng chấm đang dung → thieu (severity trung), issue mở đầu "Chưa khai thác hết:"; đang thieu/sai thì chỉ nối câu vào issue.
create or replace function public.qc_ghi_ckt(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n int; m int;
begin
  insert into qc_chua_khai_thac (review_id, tin_cuoi_luc, ket, ly_do)
  select (x->>'id')::bigint, (x->>'tin_cuoi_luc')::timestamp, (x->>'ket')::boolean, trim(x->>'ly_do')
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
  return jsonb_build_object('ghi', n, 'loi_sale', m);
end $$;
revoke execute on function public.qc_ghi_ckt(jsonb) from public, anon, authenticated;

-- Cho lịch chấm cloud (chặn bằng mã chấm)
create or replace function public.qc_lo_chua_khai_thac(p_ma text, p_so int default 40) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(u)) from qc_ckt_ung_vien(p_so) u), '[]'::jsonb);
end $$;
create or replace function public.qc_ghi_chua_khai_thac(p_ma text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan_cham(p_ma);
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows phải là mảng'; end if;
  return qc_ghi_ckt(p_rows);
end $$;
revoke execute on function public.qc_lo_chua_khai_thac(text, int), public.qc_ghi_chua_khai_thac(text, jsonb) from public;
grant execute on function public.qc_lo_chua_khai_thac(text, int), public.qc_ghi_chua_khai_thac(text, jsonb) to anon, authenticated;

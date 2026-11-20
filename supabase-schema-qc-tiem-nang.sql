-- ĐÁNH GIÁ KHÁCH TIỀM NĂNG (anh Hải 19/11/2026): "khách mà báo giá xong vẫn hỏi tiếp về sản phẩm và phản hồi cuối mở thì đều
-- coi là tiềm năng; đánh giá định kỳ 2 lần mỗi ngày, đánh giá toàn bộ tin nhắn trong ngày". "QC thống kê ra thôi, mở để app MKT
-- sử dụng — app MKT có nghĩa vụ nối data vào app và cập nhật thẻ trạng thái trong Pancake" (QC chỉ ĐỌC Pancake).
-- Lịch chấm cloud (routine/cham-cloud.md) chạy lúc 12h50 và 20h50 giờ VN: qc_lo_tiem_nang → AI xếp loại → qc_ghi_tiem_nang.
-- LỌC TRƯỚC bằng máy (đỡ tốn lượt AI): chỉ hội thoại đã qua bộ lọc QC, khách có nhắn trong ngày, và có tin Sale chứa con số giá.
-- Lần 20h50 chỉ xét lại hội thoại có tin mới sau lần đánh giá trước. Monsieur Claude
create table if not exists public.qc_khach_tiem_nang (
  ngay          date not null,                 -- ngày đánh giá (giờ VN) = ngày khách có nhắn
  review_id     bigint not null,               -- sale_response_review.id
  ket           text not null check (ket in ('tiem_nang','da_chot','tu_choi','chua_du')),
  ly_do         text,                          -- 1 câu: khách hỏi gì sau báo giá, phản hồi cuối thế nào
  danh_gia_luc  timestamptz not null default now(),
  primary key (ngay, review_id)
);
alter table public.qc_khach_tiem_nang enable row level security;   -- không policy: chỉ qua hàm / view

-- Tin Sale có con số giá: 350k · 3,6tr · 2 triệu · 49.500.000 · 3.900.000đ
create or replace function public.qc_co_bao_gia(p_thread text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(p_thread, '') ~* '\] Sale[^:]*:[^\n]*(\d+([.,]\d+)?\s*(tr\M|triệu|k\M|nghìn|ngàn)|\d{1,3}([.,]\d{3}){1,2}\s*(đ|vnđ|vnd|\M))'
$$;

-- Lô cần đánh giá cho ngày p_ngay (mặc định hôm nay giờ VN)
create or replace function public.qc_lo_tiem_nang(p_ma text, p_ngay date default null, p_so int default 40) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d date := coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select s.id, s.page_name, s.customer_name, s.sale_name, d as ngay,
           (s.conv_id !~ '^(pzl|ttm)' and s.conv_id not like coalesce(s.page_id, '') || '_%') la_binh_luan,
           right(s.full_thread, 6000) thread
    from sale_response_review s
    left join qc_khach_tiem_nang k on k.ngay = d and k.review_id = s.id
    where s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false) and s.conv_id not like 'pzl\_g\_%'
      and s.conv_date >= d - 1
      and s.full_thread ~ ('\[' || d::text || ' \d\d:\d\d\] Khách:')
      and qc_co_bao_gia(s.full_thread)
      and (k.review_id is null
           or (regexp_match(right(s.full_thread, 300), '\[(\d{4}-\d\d-\d\d \d\d:\d\d)\][^\n]*$'))[1]::timestamp
              > (k.danh_gia_luc at time zone 'Asia/Ho_Chi_Minh'))
    order by s.id
    limit least(greatest(p_so, 1), 60)) x), '[]'::jsonb);
end $$;

-- Ghi kết quả: p_rows = [{id, ket: tiem_nang|da_chot|tu_choi|chua_du, ly_do}]
create or replace function public.qc_ghi_tiem_nang(p_ma text, p_ngay date, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r jsonb; loi text[] := '{}'; n int;
begin
  perform qc_chan_cham(p_ma);
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows phải là mảng'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(r->>'ket','') not in ('tiem_nang','da_chot','tu_choi','chua_du') then
      loi := loi || format('#%s: ket "%s" không hợp lệ', r->>'id', r->>'ket');
    elsif coalesce(trim(r->>'ly_do'),'') = '' then loi := loi || format('#%s: thiếu ly_do', r->>'id');
    end if;
  end loop;
  if array_length(loi, 1) > 0 then return jsonb_build_object('ghi', 0, 'loi', to_jsonb(loi)); end if;
  insert into qc_khach_tiem_nang (ngay, review_id, ket, ly_do, danh_gia_luc)
  select coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date), (x->>'id')::bigint, x->>'ket', trim(x->>'ly_do'), now()
  from jsonb_array_elements(p_rows) x
  where exists (select 1 from sale_response_review s where s.id = (x->>'id')::bigint)
  on conflict (ngay, review_id) do update set ket = excluded.ket, ly_do = excluded.ly_do, danh_gia_luc = now();
  get diagnostics n = row_count;
  return jsonb_build_object('ghi', n, 'gui', jsonb_array_length(p_rows));
end $$;

revoke execute on function public.qc_lo_tiem_nang(text, date, int), public.qc_ghi_tiem_nang(text, date, jsonb) from public;
grant execute on function public.qc_lo_tiem_nang(text, date, int), public.qc_ghi_tiem_nang(text, date, jsonb) to anon, authenticated;

-- VIEW CHO APP MKT/SALE (CHỈ ĐỌC; đổi cột về sau CHỈ THÊM). 1 dòng = 1 hội thoại × 1 ngày đánh giá.
-- page_id + pancake_conversation_id để app MKT gắn thẻ trạng thái trên Pancake.
create or replace view public.qc_khach_tiem_nang_ngay with (security_invoker = true) as
select k.ngay, k.ket, k.ly_do, k.danh_gia_luc,
       case when s.page_id like 'pzl\_%' then 'zalo' when s.page_id like 'ttm\_%' then 'tiktok' else 'facebook' end as nen_tang,
       s.page_name as kenh, s.page_id, s.conv_id as pancake_conversation_id,
       coalesce(s.khach_id, nullif(regexp_replace(s.conv_id, '^pzl_u_\d+_', ''), s.conv_id)) as khach_id,
       s.customer_name as ten_khach, s.phone as sdt,
       coalesce(t.ten_nhan_su, null) as sale, s.sale_name as sale_qc,
       s.pancake_url
from public.qc_khach_tiem_nang k
join public.sale_response_review s on s.id = k.review_id
left join public.qc_sale_ten t on t.ten_pancake = s.sale_name;

-- authenticated đọc được view (security_invoker) → cần quyền đọc bảng
drop policy if exists "doc qc_khach_tiem_nang" on public.qc_khach_tiem_nang;
create policy "doc qc_khach_tiem_nang" on public.qc_khach_tiem_nang for select to authenticated using (true);
grant select on public.qc_khach_tiem_nang to authenticated;
grant select on public.qc_khach_tiem_nang_ngay to authenticated;
revoke all on public.qc_khach_tiem_nang_ngay from anon;

-- 20/11: trang QC đọc kết quả đánh giá để anh check chéo (thẻ "Khách tiềm năng" theo bộ lọc ngày / page / Sale).
create or replace function qc_ds_tiem_nang(p_ma text) returns jsonb
language plpgsql security definer set search_path to 'public', 'extensions' set statement_timeout to '20s' as $$
begin
  perform qc_chan(p_ma);
  return coalesce((select jsonb_agg(jsonb_build_object('review_id', k.review_id, 'ngay', k.ngay, 'ket', k.ket, 'ly_do', k.ly_do,
      'danh_gia_luc', k.danh_gia_luc,
      -- kèm thông tin hội thoại: ngày đánh giá có thể sớm hơn conv_date (= ngày nhắn cuối) nên trang không dựa vào danh sách chấm đang tải
      'conv_date', s.conv_date, 'conv_at', s.conv_at, 'page_id', s.page_id, 'page_name', s.page_name, 'conv_id', s.conv_id,
      'customer_name', s.customer_name, 'phone', s.phone, 'sale_name', s.sale_name, 'verdict', s.verdict, 'pancake_url', s.pancake_url)
      order by k.ngay, k.review_id)
    from qc_khach_tiem_nang k join sale_response_review s on s.id = k.review_id
    where k.ngay >= date '2026-11-01' and s.verdict <> 'khong_lien_quan'), '[]'::jsonb);
end $$;
revoke all on function qc_ds_tiem_nang(text) from public;
grant execute on function qc_ds_tiem_nang(text) to anon, authenticated;

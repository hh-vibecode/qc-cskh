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

-- VIEW CHO APP MKT/SALE (CHỈ ĐỌC; đổi cột về sau CHỈ THÊM). Từ 20/11: chỉ TIỀM NĂNG THẬT — 1 dòng / hội thoại (lần đánh giá mới nhất là tiem_nang, hoặc chua_du mà Sale đang bỏ lửng).
-- page_id + pancake_conversation_id để app MKT gắn thẻ trạng thái trên Pancake.
create or replace view public.qc_khach_tiem_nang_ngay with (security_invoker = true) as
select k.ngay, k.ket, k.ly_do, k.danh_gia_luc,
       case when s.page_id like 'pzl\_%' then 'zalo' when s.page_id like 'ttm\_%' then 'tiktok' else 'facebook' end as nen_tang,
       s.page_name as kenh, s.page_id, s.conv_id as pancake_conversation_id,
       coalesce(s.khach_id, nullif(regexp_replace(s.conv_id, '^pzl_u_\d+_', ''), s.conv_id)) as khach_id,
       s.customer_name as ten_khach, s.phone as sdt,
       coalesce(t.ten_nhan_su, null) as sale, s.sale_name as sale_qc,
       s.pancake_url,
       -- 20/11 (THÊM cột): thẻ "chưa khai thác hết" — Sale hứa quay lại rồi bỏ lửng (qc_chua_khai_thac), chỉ khi tin cuối vẫn là tin bỏ lửng đó
       (c.review_id is not null) as chua_khai_thac, c.ly_do as ly_do_chua_khai_thac
from public.qc_khach_tiem_nang k
join public.sale_response_review s on s.id = k.review_id
left join public.qc_sale_ten t on t.ten_pancake = s.sale_name
left join lateral (select c.review_id, c.ly_do from public.qc_chua_khai_thac c
                   where c.review_id = s.id and c.ket
                     -- còn hiệu lực: không có tin Khách / Sale nào (bỏ Bot) sau tin bỏ lửng
                     and not exists (select 1 from regexp_matches(right(s.full_thread, 3000), '\[(\d{4}-\d\d-\d\d \d\d:\d\d)\] (?!Bot:)', 'g') m
                                     where m[1]::timestamp > c.tin_cuoi_luc)
                   order by c.tin_cuoi_luc desc limit 1) c on true
-- 20/11 anh Hải: "lọc hết ra tiềm năng thật mới đưa cho app mkt xử lý" + "lọc các khách trong tệp từ chối ra".
-- Chỉ giữ hội thoại mà LẦN ĐÁNH GIÁ MỚI NHẤT là tiem_nang (sau đó đã chốt / từ chối → tự rơi khỏi tệp). 1 dòng / hội thoại.
-- Ngoại lệ: mới nhất là chua_du nhưng Sale đang bỏ lửng lời hứa (chưa khai thác hết) → vẫn vào tệp (Sale nợ khách, ca Thiện Minh).
where (k.ket = 'tiem_nang' or (k.ket = 'chua_du' and c.review_id is not null))
  and not exists (select 1 from public.qc_khach_tiem_nang k2 where k2.review_id = k.review_id
                    and (k2.ngay > k.ngay or (k2.ngay = k.ngay and k2.danh_gia_luc > k.danh_gia_luc)));
grant select on public.qc_chua_khai_thac to authenticated;

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
      'customer_name', s.customer_name, 'phone', s.phone, 'sale_name', s.sale_name, 'verdict', s.verdict, 'pancake_url', s.pancake_url,
      -- 20/11: thẻ "chưa khai thác hết" (Sale hứa quay lại rồi bỏ lửng — qc_chua_khai_thac)
      'ckt', (select c.ly_do from qc_chua_khai_thac c where c.review_id = k.review_id and c.ket order by c.tin_cuoi_luc desc limit 1))
      order by k.ngay, k.review_id)
    from qc_khach_tiem_nang k join sale_response_review s on s.id = k.review_id
    where k.ngay >= date '2026-11-01' and s.verdict <> 'khong_lien_quan'), '[]'::jsonb);
end $$;
revoke all on function qc_ds_tiem_nang(text) from public;
grant execute on function qc_ds_tiem_nang(text) to anon, authenticated;

-- 20/11 (sửa lần 2): TikTok — bình luận và tin nhắn riêng đều có conv_id 'ttm_<page>_…'; bình luận đuôi SỐ (_7708…), tin nhắn riêng đuôi mã hoá (_dTV…==).
-- Bản đầu coi mọi ttm là tin nhắn → giữ nhầm dòng bình luận (khách "Học Tu Tâm" 15–16/11). Hàm nhận diện dùng chung:
create or replace function public.qc_la_inbox(p_conv text, p_page text) returns boolean
language sql immutable set search_path = public as $$
  select case when p_conv like 'pzl\_%' then true
              when p_conv like 'ttm\_%' then p_conv !~ '_\d+$'
              else p_conv like coalesce(p_page, '') || '\_%' end
$$;

-- ── 20/11: CHỐNG TRÙNG (anh Hải: "để ý k bị dup data nhé") ─────────────────────────────────────────────
-- Bình luận và tin nhắn riêng là 2 dòng chấm riêng nhưng là CÙNG 1 KHÁCH (cùng page_id + khach_id) → tiềm năng chỉ 1 dòng / khách / page / ngày.
-- Giữ dòng TIN NHẮN RIÊNG (hội thoại đủ, MKT gắn thẻ đúng hội thoại); kết quả lấy mạnh nhất: da_chot > tiem_nang > tu_choi > chua_du.
-- Dòng bị gộp cất vào qc_khach_tiem_nang_trung_bo (RLS bật, không policy = chỉ quản trị đọc).
create table if not exists qc_khach_tiem_nang_trung_bo (like qc_khach_tiem_nang);
alter table qc_khach_tiem_nang_trung_bo add column if not exists bo_luc timestamptz default now();
alter table qc_khach_tiem_nang_trung_bo enable row level security;

create or replace function public.qc_gop_tiem_nang_trung(p_ngay date default null) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  drop table if exists _tn_x;
  create temp table _tn_x as
    select k.ngay, k.review_id, k.ket, k.ly_do, s.page_id, s.khach_id,
           qc_la_inbox(s.conv_id, s.page_id) la_inbox,
           case k.ket when 'da_chot' then 1 when 'tiem_nang' then 2 when 'tu_choi' then 3 else 4 end hang,
           count(*) over (partition by k.ngay, s.page_id, s.khach_id) so
    from qc_khach_tiem_nang k join sale_response_review s on s.id = k.review_id
    where s.khach_id is not null and s.page_id is not null and (p_ngay is null or k.ngay = p_ngay);
  delete from _tn_x where so < 2;
  drop table if exists _tn_g;
  create temp table _tn_g as
    select g.ngay, g.page_id, g.khach_id, g.review_id giu, t.ket, case when t.la_inbox then t.ly_do else '(từ bình luận) ' || t.ly_do end ly_do
    from (select distinct on (ngay, page_id, khach_id) ngay, page_id, khach_id, review_id from _tn_x
          order by ngay, page_id, khach_id, la_inbox desc, review_id) g
    join (select distinct on (ngay, page_id, khach_id) ngay, page_id, khach_id, ket, ly_do, la_inbox from _tn_x
          order by ngay, page_id, khach_id, hang, la_inbox desc, review_id) t using (ngay, page_id, khach_id);
  insert into qc_khach_tiem_nang_trung_bo (ngay, review_id, ket, ly_do, danh_gia_luc, bo_luc)
    select k.ngay, k.review_id, k.ket, k.ly_do, k.danh_gia_luc, now()
    from qc_khach_tiem_nang k join _tn_x x on x.ngay = k.ngay and x.review_id = k.review_id
    join _tn_g g on g.ngay = x.ngay and g.page_id = x.page_id and g.khach_id = x.khach_id and x.review_id <> g.giu;
  delete from qc_khach_tiem_nang k using _tn_x x, _tn_g g
    where x.ngay = k.ngay and x.review_id = k.review_id and g.ngay = x.ngay and g.page_id = x.page_id and g.khach_id = x.khach_id and x.review_id <> g.giu;
  get diagnostics n = row_count;
  update qc_khach_tiem_nang k set ket = g.ket, ly_do = g.ly_do from _tn_g g
    where k.ngay = g.ngay and k.review_id = g.giu and (k.ket, k.ly_do) is distinct from (g.ket, g.ly_do);
  return n;
end $$;
revoke execute on function public.qc_gop_tiem_nang_trung(date) from public, anon, authenticated;

-- Lô: bỏ dòng BÌNH LUẬN khi tin nhắn riêng của chính khách đó (cùng page + khach_id) cũng vào lô ngày đó — đỡ tốn lượt AI đánh giá 2 lần.
create or replace function public.qc_lo_tiem_nang(p_ma text, p_ngay date default null, p_so int default 40) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d date := coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select s.id, s.page_name, s.customer_name, s.sale_name, d as ngay,
           not qc_la_inbox(s.conv_id, s.page_id) la_binh_luan,
           right(s.full_thread, 6000) thread
    from sale_response_review s
    left join qc_khach_tiem_nang k on k.ngay = d and k.review_id = s.id
    where s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false) and s.conv_id not like 'pzl\_g\_%'
      and s.conv_date >= d - 1
      and s.full_thread ~ ('\[' || d::text || ' \d\d:\d\d\] Khách:')
      and qc_co_bao_gia(s.full_thread)
      and not (s.khach_id is not null and not qc_la_inbox(s.conv_id, s.page_id)
               and exists (select 1 from sale_response_review i where i.page_id = s.page_id and i.khach_id = s.khach_id and i.id <> s.id
                             and qc_la_inbox(i.conv_id, i.page_id) and i.verdict <> 'khong_lien_quan' and i.conv_date >= d - 1
                             and i.full_thread ~ ('\[' || d::text || ' \d\d:\d\d\] Khách:') and qc_co_bao_gia(i.full_thread)))
      and (k.review_id is null
           or (regexp_match(right(s.full_thread, 300), '\[(\d{4}-\d\d-\d\d \d\d:\d\d)\][^\n]*$'))[1]::timestamp
              > (k.danh_gia_luc at time zone 'Asia/Ho_Chi_Minh'))
    order by s.id
    limit least(greatest(p_so, 1), 60)) x), '[]'::jsonb);
end $$;

-- Ghi: sau khi ghi thì gộp trùng của ngày đó (chặn mọi đường ghi, kể cả lịch cloud ghi cả 2 dòng)
create or replace function public.qc_ghi_tiem_nang(p_ma text, p_ngay date, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r jsonb; loi text[] := '{}'; n int; d date := coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date); gop int;
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
  select d, (x->>'id')::bigint, x->>'ket', trim(x->>'ly_do'), now()
  from jsonb_array_elements(p_rows) x
  where exists (select 1 from sale_response_review s where s.id = (x->>'id')::bigint)
  on conflict (ngay, review_id) do update set ket = excluded.ket, ly_do = excluded.ly_do, danh_gia_luc = now();
  get diagnostics n = row_count;
  gop := qc_gop_tiem_nang_trung(d);
  return jsonb_build_object('ghi', n, 'gui', jsonb_array_length(p_rows), 'gop_trung', gop);
end $$;

-- KHÁCH SỈ / LẺ TRONG TỆP TIỀM NĂNG (anh Hải chốt 23/11/2026): "chấm cả khách sỉ hay lẻ, chỉ chấm cho tệp tiềm năng thôi, chủ yếu
-- là ở Shidai, mấy page kia thì auto lẻ; Shidai nếu khách bảo tự dùng, tại gia, cá nhân… nói chung không liên quan tới sỉ thì là lẻ".
--   page Shidai (tên có "sỉ" / "thời đại" / "shidai" — Social hiện chỉ FB Thời Đại 506247572578559): AI xếp 'si' | 'le' cùng lượt đánh giá
--   tiềm năng; chỉ 'si' khi có dấu hiệu nhập / bán lại / đại lý / cửa hàng / số lượng buôn, còn lại 'le'.
--   page khác: luôn 'le' (hàm ghi tự đặt, view tự điền).
-- View qc_khach_tiem_nang_ngay THÊM cột cuối loai_khach (app MKT đọc — chỉ thêm, không đổi cột cũ). Monsieur Claude
alter table public.qc_khach_tiem_nang add column if not exists loai_khach text check (loai_khach in ('si', 'le'));
alter table public.qc_khach_tiem_nang_trung_bo add column if not exists loai_khach text;

create or replace function public.qc_page_si(p_page_name text) returns boolean
language sql immutable set search_path = public as $$
  select coalesce(p_page_name, '') ~* '(sỉ|thời đại|shidai)'
$$;

create or replace function public.qc_lo_tiem_nang(p_ma text, p_ngay date default null, p_so int default 40) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare d date := coalesce(p_ngay, (now() at time zone 'Asia/Ho_Chi_Minh')::date);
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select s.id, s.page_name, s.customer_name, s.sale_name, d as ngay,
           not qc_la_inbox(s.conv_id, s.page_id) la_binh_luan,
           qc_page_si(s.page_name) page_si,                                   -- 23/11: true → phải xếp loai_khach
           right(s.full_thread, 6000) thread
    from sale_response_review s
    left join qc_khach_tiem_nang k on k.ngay = d and k.review_id = s.id
    where s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false) and s.conv_id not like 'pzl\_%'   -- chỉ Social (20/11)
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

-- Ghi: p_rows thêm "loai_khach": "si" | "le" — BẮT BUỘC với page Shidai khi ket = tiem_nang / tu_choi (đã chốt / chưa đủ không cần —
-- lọc trước, anh 23/11: "phải qua bộ lọc rác, bộ lọc tiềm năng rồi hãy xử lý, tránh tốn token vô nghĩa"); page khác luôn ghi 'le'.
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
    elsif r->>'loai_khach' is not null and r->>'loai_khach' not in ('si','le') then
      loi := loi || format('#%s: loai_khach "%s" không hợp lệ', r->>'id', r->>'loai_khach');
    elsif r->>'ket' in ('tiem_nang','tu_choi') and coalesce(r->>'loai_khach','') = ''   -- lọc trước (anh 23/11): chỉ tệp tiềm năng mới cần
          and exists (select 1 from sale_response_review s where s.id = (r->>'id')::bigint and qc_page_si(s.page_name)) then
      loi := loi || format('#%s: page Shidai, kết quả %s phải có loai_khach "si" hoặc "le"', r->>'id', r->>'ket');
    end if;
  end loop;
  if array_length(loi, 1) > 0 then return jsonb_build_object('ghi', 0, 'loi', to_jsonb(loi)); end if;
  insert into qc_khach_tiem_nang (ngay, review_id, ket, ly_do, danh_gia_luc, loai_khach)
  select d, s.id, x->>'ket', trim(x->>'ly_do'), now(),
         case when qc_page_si(s.page_name) then x->>'loai_khach' else 'le' end
  from jsonb_array_elements(p_rows) x join sale_response_review s on s.id = (x->>'id')::bigint
  on conflict (ngay, review_id) do update set ket = excluded.ket, ly_do = excluded.ly_do, loai_khach = excluded.loai_khach, danh_gia_luc = now();
  get diagnostics n = row_count;
  gop := qc_gop_tiem_nang_trung(d);
  return jsonb_build_object('ghi', n, 'gui', jsonb_array_length(p_rows), 'gop_trung', gop);
end $$;

-- Gộp trùng (bình luận + tin nhắn riêng cùng khách): giữ như cũ, loai_khach = 'si' nếu 1 trong các dòng là sỉ
create or replace function public.qc_gop_tiem_nang_trung(p_ngay date default null) returns int
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  drop table if exists _tn_x;
  create temp table _tn_x as
    select k.ngay, k.review_id, k.ket, k.ly_do, k.loai_khach, s.page_id, s.khach_id,
           qc_la_inbox(s.conv_id, s.page_id) la_inbox,
           case k.ket when 'da_chot' then 1 when 'tiem_nang' then 2 when 'tu_choi' then 3 else 4 end hang,
           count(*) over (partition by k.ngay, s.page_id, s.khach_id) so
    from qc_khach_tiem_nang k join sale_response_review s on s.id = k.review_id
    where s.khach_id is not null and s.page_id is not null and (p_ngay is null or k.ngay = p_ngay);
  delete from _tn_x where so < 2;
  drop table if exists _tn_g;
  create temp table _tn_g as
    select g.ngay, g.page_id, g.khach_id, g.review_id giu, t.ket, case when t.la_inbox then t.ly_do else '(từ bình luận) ' || t.ly_do end ly_do,
           l.loai_khach
    from (select distinct on (ngay, page_id, khach_id) ngay, page_id, khach_id, review_id from _tn_x
          order by ngay, page_id, khach_id, la_inbox desc, review_id) g
    join (select distinct on (ngay, page_id, khach_id) ngay, page_id, khach_id, ket, ly_do, la_inbox from _tn_x
          order by ngay, page_id, khach_id, hang, la_inbox desc, review_id) t using (ngay, page_id, khach_id)
    join (select ngay, page_id, khach_id, max(loai_khach) loai_khach from _tn_x group by 1, 2, 3) l using (ngay, page_id, khach_id);
  insert into qc_khach_tiem_nang_trung_bo (ngay, review_id, ket, ly_do, danh_gia_luc, bo_luc, loai_khach)
    select k.ngay, k.review_id, k.ket, k.ly_do, k.danh_gia_luc, now(), k.loai_khach
    from qc_khach_tiem_nang k join _tn_x x on x.ngay = k.ngay and x.review_id = k.review_id
    join _tn_g g on g.ngay = x.ngay and g.page_id = x.page_id and g.khach_id = x.khach_id and x.review_id <> g.giu;
  delete from qc_khach_tiem_nang k using _tn_x x, _tn_g g
    where x.ngay = k.ngay and x.review_id = k.review_id and g.ngay = x.ngay and g.page_id = x.page_id and g.khach_id = x.khach_id and x.review_id <> g.giu;
  get diagnostics n = row_count;
  update qc_khach_tiem_nang k set ket = g.ket, ly_do = g.ly_do, loai_khach = coalesce(g.loai_khach, k.loai_khach) from _tn_g g
    where k.ngay = g.ngay and k.review_id = g.giu
      and (k.ket, k.ly_do, k.loai_khach) is distinct from (g.ket, g.ly_do, coalesce(g.loai_khach, k.loai_khach));
  return n;
end $$;
revoke execute on function public.qc_gop_tiem_nang_trung(date) from public, anon, authenticated;

-- Dòng cũ của page không phải Shidai: điền 'le' luôn
update public.qc_khach_tiem_nang k set loai_khach = 'le'
from sale_response_review s where s.id = k.review_id and k.loai_khach is null and not qc_page_si(s.page_name);

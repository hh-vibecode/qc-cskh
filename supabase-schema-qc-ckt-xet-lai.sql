-- XÉT LẠI "CHƯA KHAI THÁC HẾT" ĐANG MỞ + VIEW BÁO SAI ĐÃ XỬ LÝ CHO APP MKT (25/11/2026, anh Hải qua phiên MKT/SALE APP)
-- Ca gốc: Phùng Dung (107224335550589_29800699782849790, Sale Đinh Ngọc Diệp, 20/11) — AI ghi "Sale nhắn 'e gửi lại hình ảnh'
-- nhưng không thấy ảnh", trong khi Pancake + full_thread đều có 6 ảnh gửi lúc 09:27:48 NGAY TRƯỚC câu "e gửi lại…" (09:28:10).
-- Kết luận sai nằm 5 ngày trong Daily Task vì thẻ chỉ tự gỡ khi có tin mới — không ai xét lại.
-- (1) qc_ghi_ckt: mốc đang ket=true mà xét lại thành false → gỡ LỖI SALE đã gắn (thieu → dung nếu lỗi chỉ do thẻ này).
-- (2) qc_ckt_dang_mo / qc_lo_ckt_mo: thẻ đang mở, lần xét cuối > 20 giờ → lịch cloud đọc lại theo luật hiện hành (lượt báo sai 3 tiếng).
-- (3) view qc_bao_sai_da_xu_ly: app MKT đọc để biết QC đã sửa hội thoại / khách nào, sửa gì, lúc nào (anh chốt 25/11).
-- Chạy lại supabase-gioi-han-qc.sql sau file này. Monsieur Claude

create or replace function public.qc_ghi_ckt(p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n int; m int; g int := 0; v_go bigint[];
begin
  -- mốc đang ket=true mà lần này ghi false = kết luận cũ sai (xét lại) → nhớ để gỡ lỗi Sale
  select coalesce(array_agg(distinct c.review_id), '{}') into v_go
  from jsonb_array_elements(p_rows) x
  join qc_chua_khai_thac c on c.review_id = (x->>'id')::bigint and c.tin_cuoi_luc = (x->>'tin_cuoi_luc')::timestamp and c.ket
  where x->>'ket' = 'false' and coalesce(trim(x->>'ly_do'), '') <> '';

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

-- Thẻ "chưa khai thác hết" ĐANG MỞ (như view: mốc ket=true mới nhất, sau mốc chưa có tin không-Bot), lần xét cuối > 20 giờ
create or replace function public.qc_ckt_dang_mo(p_so int default 40) returns table (
  id bigint, page_name text, customer_name text, sale_name text, verdict text, tin_cuoi_luc timestamp,
  ly_do_cu text, danh_gia_luc timestamptz, doan_cuoi text)
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
                    where m.m[1]::timestamp > c.tin_cuoi_luc)
  order by c.danh_gia_luc limit least(greatest(p_so, 1), 200)
$$;
revoke execute on function public.qc_ckt_dang_mo(int) from public, anon, authenticated;

create or replace function public.qc_lo_ckt_mo(p_ma text, p_so int default 40) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(u)) from qc_ckt_dang_mo(p_so) u), '[]'::jsonb);
end $$;
revoke execute on function public.qc_lo_ckt_mo(text, int) from public;
grant execute on function public.qc_lo_ckt_mo(text, int) to anon, authenticated;

-- App MKT/Sale đọc: báo sai QC đã xử lý (sửa / giữ / chờ anh). Đổi cột: chỉ THÊM.
create or replace view public.qc_bao_sai_da_xu_ly with (security_invoker = true) as
select r.id as bao_id,
       r.status as trang_thai,                       -- fixed = đã xử lý (sửa hoặc giữ — xem ghi_chu_xu_ly), open = đang mở / chờ anh
       r.created_at as bao_luc, r.resolved_at as xu_ly_luc, r.resolved_by as xu_ly_boi, r.reporter as nguoi_bao, r.note as noi_dung_bao,
       s.id as review_id, s.conv_id as pancake_conversation_id, s.page_id, coalesce(s.page_name, r.page_name) as kenh,
       coalesce(s.khach_id, nullif(regexp_replace(s.conv_id, '^pzl_u_\d+_', ''), s.conv_id)) as khach_id,
       coalesce(s.customer_name, r.customer_name) as ten_khach, t.ten_nhan_su as sale, s.sale_name as sale_qc,
       r.verdict_old as verdict_cu, s.verdict as verdict_hien_tai, s.issue as nhan_xet_hien_tai,
       r.resolve_note as ghi_chu_xu_ly, r.luat_de_xuat as luat_rut_ra, s.pancake_url
from sale_review_report r
left join sale_response_review s on s.id = r.review_id
left join qc_sale_ten t on t.ten_pancake = s.sale_name;
grant select on public.qc_bao_sai_da_xu_ly to authenticated;

-- CHẤM TRÊN CLOUD (anh Hải 29/9/2026: "chấm định kỳ mà không cần mở máy" → thử Claude Code routines).
-- Phiên cloud không có file khoá của máy anh → chỉ cầm khoá công khai (anon) + MÃ CHẤM riêng (khác mã xem trang,
-- lưu băm trong qc_cau_hinh khoa='ma_cham', đổi / thu hồi độc lập). Mã chấm CHỈ gọi được 4 hàm dưới đây:
-- lấy lô chờ chấm, lấy lô miss chưa soát, ghi kết quả chấm, ghi kết quả soát miss — cùng luật an toàn với tools/ghi-cham.js
-- (chỉ ghi dòng đang chờ, không ghi đè dòng đã chấm, giữ nhãn "Trả lời muộn" / "Bình luận → tư vấn qua tin nhắn").
-- FAQ: bảng product_faq vốn cho anon đọc — phiên cloud tra thẳng qua REST.
-- Monsieur Claude

create or replace function public.qc_chan_cham(p_ma text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select gia_tri into h from qc_cau_hinh where khoa = 'ma_cham';
  if h is null or coalesce(p_ma, '') = '' or crypt(p_ma, h) <> h then
    perform pg_sleep(0.8);
    raise exception 'Sai mã chấm' using errcode = '28P01';
  end if;
end $$;
revoke execute on function public.qc_chan_cham(text) from public, anon, authenticated;

-- Lô dòng chờ chấm (cũ trước; p_nguoc=true: mới trước — để 2 phiên chạy song song gặp nhau ở giữa)
create or replace function public.qc_lo_cham(p_ma text, p_so int default 40, p_nguoc boolean default false) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select id, conv_date, page_name, conv_id, customer_name, sale_name, customer_ask, sale_reply, issue,
           left(full_thread, 3000) thread
    from sale_response_review
    where verdict = 'chua_cham' and conv_id not like 'pzl\_g\_%'
    order by case when p_nguoc then conv_date end desc, case when p_nguoc then id end desc,
             case when not p_nguoc then conv_date end, case when not p_nguoc then id end
    limit least(greatest(p_so, 1), 60)) x), '[]'::jsonb);
end $$;

create or replace function public.qc_lo_soat_miss(p_ma text, p_so int default 40) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select id, conv_date, page_name, customer_name, verdict, customer_ask, left(full_thread, 1500) thread
    from sale_response_review
    where verdict in ('khong_tra_loi', 'chi_bot') and cham_boi is null and conv_id not like 'pzl\_g\_%'
    order by conv_date, id limit least(greatest(p_so, 1), 60)) x), '[]'::jsonb);
end $$;

-- Ghi kết quả chấm: p_rows = [{id, verdict, severity?, issue?, suggestion?, source_faq?}]
create or replace function public.qc_ghi_cham(p_ma text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r jsonb; loi text[] := '{}'; n int;
begin
  perform qc_chan_cham(p_ma);
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows phải là mảng'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(r->>'verdict','') not in ('dung','thieu','sai','khong_lien_quan','khong_tra_loi','chi_bot','tra_loi_inbox') then
      loi := loi || format('#%s: verdict "%s" không hợp lệ', r->>'id', r->>'verdict');
    elsif r->>'verdict' in ('thieu','sai') and (coalesce(r->>'severity','') not in ('cao','trung','thap')
          or coalesce(r->>'issue','') = '' or coalesce(r->>'suggestion','') = '') then
      loi := loi || format('#%s: %s phải có severity cao|trung|thap + issue + suggestion', r->>'id', r->>'verdict');
    end if;
  end loop;
  if array_length(loi, 1) > 0 then return jsonb_build_object('ghi', 0, 'loi', to_jsonb(loi)); end if;
  with v as (select * from jsonb_to_recordset(p_rows) as x(id bigint, verdict text, severity text, issue text, suggestion text, source_faq text))
  update sale_response_review s set verdict = v.verdict,
    severity = case when v.verdict in ('thieu','sai') then v.severity end,
    issue = case when s.issue ~ '^(Trả lời muộn|Bình luận → tư vấn qua tin nhắn)'
                  and coalesce(v.issue,'') !~ '^(Trả lời muộn|Bình luận → tư vấn qua tin nhắn)'
                 then substring(s.issue from '^(Trả lời muộn [0-9,]+ (?:giờ|phút)(?: \([^)]*\))?\.?|Bình luận → tư vấn qua tin nhắn[^.]*\.)') || coalesce(' ' || v.issue, '')
                 else v.issue end,
    suggestion = v.suggestion, source_faq = v.source_faq, cham_boi = 'sonnet', reviewed_at = now()
  from v where s.id = v.id and s.verdict = 'chua_cham';
  get diagnostics n = row_count;
  return jsonb_build_object('ghi', n, 'gui', jsonb_array_length(p_rows));
end $$;

-- Ghi soát miss: p_rows = [{id, verdict: 'khong_lien_quan'|'giu'|'cham', issue?}]
-- 'cham' (thêm 30/9, báo sai #35): Sale ĐÃ tiếp khách, tin cuối chưa đáp không phải câu hỏi mới → không phải miss,
-- chuyển về chua_cham để chấm nội dung (Sale có hỏi lại / bỏ lửng không).
create or replace function public.qc_ghi_soat_miss(p_ma text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  perform qc_chan_cham(p_ma);
  if exists (select 1 from jsonb_array_elements(p_rows) e where coalesce(e->>'verdict','') not in ('khong_lien_quan','giu','cham')) then
    return jsonb_build_object('ghi', 0, 'loi', 'verdict chỉ nhận khong_lien_quan | giu | cham');
  end if;
  with v as (select * from jsonb_to_recordset(p_rows) as x(id bigint, verdict text, issue text))
  update sale_response_review s set
    verdict = case v.verdict when 'khong_lien_quan' then 'khong_lien_quan' when 'cham' then 'chua_cham' else s.verdict end,
    severity = case when v.verdict in ('khong_lien_quan','cham') then null else s.severity end,
    issue = case v.verdict when 'khong_lien_quan' then coalesce(v.issue, 'Tin tương tác, không phải khách hỏi mua') when 'cham' then null else s.issue end,
    suggestion = case when v.verdict in ('khong_lien_quan','cham') then null else s.suggestion end,
    cham_boi = case when v.verdict = 'cham' then null else 'sonnet' end, reviewed_at = now()
  from v where s.id = v.id and s.verdict in ('khong_tra_loi','chi_bot') and s.cham_boi is null;
  get diagnostics n = row_count;
  return jsonb_build_object('ghi', n, 'gui', jsonb_array_length(p_rows));
end $$;

revoke execute on function public.qc_lo_cham(text, int, boolean), public.qc_lo_soat_miss(text, int),
  public.qc_ghi_cham(text, jsonb), public.qc_ghi_soat_miss(text, jsonb) from public;
grant execute on function public.qc_lo_cham(text, int, boolean), public.qc_lo_soat_miss(text, int),
  public.qc_ghi_cham(text, jsonb), public.qc_ghi_soat_miss(text, jsonb) to anon, authenticated;

-- Mã chấm đặt bằng script riêng (không ghi mã rõ vào file):
--   insert into qc_cau_hinh (khoa, gia_tri) values ('ma_cham', crypt('<mã>', gen_salt('bf'))) on conflict (khoa) do update ...

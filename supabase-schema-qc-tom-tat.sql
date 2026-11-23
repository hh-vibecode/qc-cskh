-- TÓM TẮT TRAO ĐỔI TỪNG HỘI THOẠI (anh Hải 23/11/2026, app MKT/Sale nhờ): cột "Trao đổi gần nhất" ở danh sách khách / CRM
-- của app MKT hiện tóm tắt trao đổi Pancake. QC đọc nội dung (full_thread), MKT chỉ ĐỌC kết quả.
-- Phạm vi (anh chốt): hội thoại Social (Facebook + TikTok, không Zalo) ĐÃ QUA BỘ LỌC (verdict <> 'khong_lien_quan', không nội bộ),
-- có tin từ 1/11/2026 — không tóm tắt bù tháng 8–10.
-- AI tóm tắt trong lịch chấm cloud mỗi giờ (routine/cham-cloud.md, mục TÓM TẮT HỘI THOẠI): qc_lo_tom_tat → tóm tắt → qc_ghi_tom_tat.
-- Lô chỉ trả hội thoại chưa có tóm tắt hoặc có tin mới (không tính Bot) sau lần tóm tắt trước.
-- tin_cuoi_luc / tin_cuoi_cua trong view tính trực tiếp từ thread mới nhất (không chờ AI) — giờ trong thread là giờ VN.
-- App MKT đọc view qc_tom_tat_hoi_thoai: conversation_id, page_id, tom_tat, tin_cuoi_luc, tin_cuoi_cua, cap_nhat_luc. Đổi cột: chỉ THÊM.
-- Monsieur Claude
create table if not exists public.qc_tom_tat (
  page_id          text not null,
  conversation_id  text not null,               -- = sale_response_review.conv_id = datahub_orders.conversation_id
  review_id        bigint not null,             -- dòng sale_response_review lúc tóm tắt
  tom_tat          text not null,               -- 1–2 câu ≤ ~200 ký tự: khách cần gì, Sale báo gì, đang dừng ở đâu / ai chờ ai
  den_tin_luc      timestamp not null,          -- tóm tắt đã đọc tới tin này (giờ VN, bỏ Bot)
  cap_nhat_luc     timestamptz not null default now(),
  primary key (page_id, conversation_id)
);
alter table public.qc_tom_tat enable row level security;
drop policy if exists "doc qc_tom_tat" on public.qc_tom_tat;
create policy "doc qc_tom_tat" on public.qc_tom_tat for select to authenticated using (true);
revoke all on public.qc_tom_tat from anon;
grant select on public.qc_tom_tat to authenticated;

-- Tin cuối (bỏ Bot) của một thread: [giờ VN, 'khach' | 'sale']
create or replace function public.qc_tin_cuoi(p_thread text) returns text[]
language sql immutable set search_path = public as $$
  select array[m[1], case m[2] when 'Khách' then 'khach' else 'sale' end]
  from (select regexp_match(right(coalesce(p_thread, ''), 4000), '.*\[(\d{4}-\d\d-\d\d \d\d:\d\d)\] (Khách|Sale)', 's') m) x
  where m is not null
$$;

-- Hội thoại trong phạm vi: dòng mới nhất mỗi (page_id, conv_id), đã qua lọc, Social, có tin từ 1/11
create or replace view public.qc_tom_tat_hoi_thoai with (security_invoker = true) as
with s as (
  select distinct on (s.page_id, s.conv_id) s.id, s.page_id, s.conv_id, s.full_thread
  from sale_response_review s
  where s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false)
    and s.conv_id not like 'pzl\_%' and s.conv_date >= '2026-10-01'
  order by s.page_id, s.conv_id, s.id desc
)
select s.conv_id conversation_id,
       s.page_id,
       t.tom_tat,
       (qc_tin_cuoi(s.full_thread))[1]::timestamp tin_cuoi_luc,
       (qc_tin_cuoi(s.full_thread))[2] tin_cuoi_cua,
       t.cap_nhat_luc,
       t.den_tin_luc tom_tat_den_tin,
       s.id review_id
from s
left join qc_tom_tat t on t.page_id = s.page_id and t.conversation_id = s.conv_id
where (qc_tin_cuoi(s.full_thread))[1] >= '2026-11-01';
revoke all on public.qc_tom_tat_hoi_thoai from anon;
grant select on public.qc_tom_tat_hoi_thoai to authenticated;

-- Lô cần tóm tắt: chưa có tóm tắt, hoặc tin cuối mới hơn lần tóm tắt trước
create or replace function public.qc_lo_tom_tat(p_ma text, p_so int default 40) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan_cham(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(x)) from (
    select v.review_id id, v.page_id, v.conversation_id, s.page_name, s.customer_name, s.sale_name,
           v.tin_cuoi_luc, v.tom_tat tom_tat_cu, right(s.full_thread, 4000) thread
    from qc_tom_tat_hoi_thoai v join sale_response_review s on s.id = v.review_id
    where v.tom_tat is null or v.tin_cuoi_luc > v.tom_tat_den_tin
    order by v.tin_cuoi_luc desc
    limit least(greatest(p_so, 1), 60)) x), '[]'::jsonb);
end $$;

-- Ghi: p_rows = [{"id": review_id, "tom_tat": "...", "tin_cuoi_luc": "<giữ nguyên từ lô>"}]
create or replace function public.qc_ghi_tom_tat(p_ma text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r jsonb; loi text[] := '{}'; n int;
begin
  perform qc_chan_cham(p_ma);
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows phải là mảng'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(trim(r->>'tom_tat'), '') = '' then loi := loi || format('#%s: thiếu tom_tat', r->>'id');
    elsif length(trim(r->>'tom_tat')) > 300 then loi := loi || format('#%s: tom_tat dài %s ký tự (tối đa 300)', r->>'id', length(trim(r->>'tom_tat')));
    elsif coalesce(r->>'tin_cuoi_luc', '') = '' then loi := loi || format('#%s: thiếu tin_cuoi_luc', r->>'id');
    end if;
  end loop;
  if array_length(loi, 1) > 0 then return jsonb_build_object('ghi', 0, 'loi', to_jsonb(loi)); end if;
  insert into qc_tom_tat (page_id, conversation_id, review_id, tom_tat, den_tin_luc, cap_nhat_luc)
  select s.page_id, s.conv_id, s.id, trim(x->>'tom_tat'), (x->>'tin_cuoi_luc')::timestamp, now()
  from jsonb_array_elements(p_rows) x join sale_response_review s on s.id = (x->>'id')::bigint
  on conflict (page_id, conversation_id) do update
    set review_id = excluded.review_id, tom_tat = excluded.tom_tat, den_tin_luc = excluded.den_tin_luc, cap_nhat_luc = now();
  get diagnostics n = row_count;
  return jsonb_build_object('ghi', n, 'gui', jsonb_array_length(p_rows));
end $$;
revoke execute on function public.qc_lo_tom_tat(text, int), public.qc_ghi_tom_tat(text, jsonb) from public;
grant execute on function public.qc_lo_tom_tat(text, int), public.qc_ghi_tom_tat(text, jsonb) to anon, authenticated;

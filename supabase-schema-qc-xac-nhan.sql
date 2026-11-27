-- TIN XÁC NHẬN CỦA SALE → TIỀM NĂNG CHUYỂN ĐẠT (anh Hải chốt 27/11/2026):
-- "các khách tiềm năng mà sale nhắn xác nhận lại xem họ có mua hay không (t sẽ thêm quy trình cho sale sau khi đợi khách quá lâu)
--  thì sau 2 ngày mà họ k phản hồi lại tin xác nhận ấy hoặc phản hồi từ chối, thì m sẽ chuyển tiềm năng thành đạt và cũng báo
--  để mkt đổi lại thẻ và trạng thái cho tương ứng từ app tới pancake."
-- (1) qc_lo_xac_nhan: khách đang ở nhóm tiềm năng (view qc_khach_tiem_nang_ngay, không tính chưa khai thác hết), tin cuối (bỏ Bot)
--     là của Sale, chưa xét → lịch chấm cloud (AI) đọc 12 tin cuối: tin Sale đó có phải HỎI LẠI khách còn mua / đã quyết chưa.
-- (2) qc_ghi_xac_nhan ghi qc_xac_nhan. (3) view qc_khach_tiem_nang_ngay (file supabase-schema-qc-xac-nhan-view.sql): có tin xác nhận,
--     khách chưa nhắn gì sau đó và đã đủ 48 giờ → nhom = dat, ly_do_nhom "Sale xác nhận lại, khách không phản hồi sau 2 ngày".
--     Khách trả lời từ chối → lượt đánh giá tiềm năng (khách nhắn trong ngày) ra tu_choi → đạt như luật 23/11.
-- Chạy lại supabase-gioi-han-qc.sql sau file này. Monsieur Claude

create table if not exists public.qc_xac_nhan (
  review_id   bigint not null,
  tin_luc     timestamp not null,               -- giờ VN (như thread) của tin Sale được xét
  la_xac_nhan boolean not null,
  ly_do       text,
  danh_gia_luc timestamptz not null default now(),
  primary key (review_id, tin_luc)
);
alter table public.qc_xac_nhan enable row level security;
drop policy if exists qc_xac_nhan_doc on public.qc_xac_nhan;
create policy qc_xac_nhan_doc on public.qc_xac_nhan for select to authenticated using (true);
revoke all on public.qc_xac_nhan from anon;
grant select on public.qc_xac_nhan to authenticated;

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
          where s.conv_date >= date '2026-10-01')
    select s.id, s.page_name, s.customer_name, s.sale_name, substr(ls[cardinality(ls)], 2, 16)::timestamp as tin_luc,
           array_to_string(ls[greatest(1, cardinality(ls) - 11):cardinality(ls)], E'\n') as doan_cuoi
    from s
    where cardinality(ls) > 0 and ls[cardinality(ls)] ~ '^\[[^]]+\] Sale'
      and not exists (select 1 from qc_xac_nhan q where q.review_id = s.id and q.tin_luc = substr(ls[cardinality(ls)], 2, 16)::timestamp)
    order by s.id limit least(greatest(p_so, 1), 60)) u), '[]'::jsonb);
end $$;

create or replace function public.qc_ghi_xac_nhan(p_ma text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare n int;
begin
  perform qc_chan_cham(p_ma);
  insert into qc_xac_nhan (review_id, tin_luc, la_xac_nhan, ly_do)
  select (x->>'id')::bigint, (x->>'tin_luc')::timestamp, (x->>'la_xac_nhan')::boolean, trim(x->>'ly_do')
  from jsonb_array_elements(p_rows) x
  where x->>'la_xac_nhan' in ('true', 'false') and coalesce(trim(x->>'ly_do'), '') <> '' and x->>'tin_luc' is not null
  on conflict (review_id, tin_luc) do update set la_xac_nhan = excluded.la_xac_nhan, ly_do = excluded.ly_do, danh_gia_luc = now();
  get diagnostics n = row_count;
  return jsonb_build_object('ghi', n);
end $$;
revoke all on function public.qc_lo_xac_nhan(text, int) from public;
revoke all on function public.qc_ghi_xac_nhan(text, jsonb) from public;
grant execute on function public.qc_lo_xac_nhan(text, int) to anon, authenticated;
grant execute on function public.qc_ghi_xac_nhan(text, jsonb) to anon, authenticated;

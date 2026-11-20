-- KHÁCH TIỀM NĂNG CHỈ ĐÁNH GIÁ SOCIAL (anh Hải 20/11/2026: "vào zalo thì đánh giá làm gì, đánh giá trên social thôi").
-- (1) Lô tiềm năng + ứng viên "chưa khai thác hết" bỏ Zalo (conv_id pzl_). (2) Dọn kết quả Zalo đã ghi (sao lưu trước),
-- trả #3479 (Zalo, bị gắn "chưa khai thác hết" → Thiếu ý) về đúng trạng thái trong bản sao lưu #53 (Đúng, không nhận xét).
-- View qc_khach_tiem_nang_ngay của app MKT KHÔNG đổi — đọc bảng nên tự hết dòng Zalo.
-- Chạy lại supabase-gioi-han-qc.sql sau file này (create or replace xoá statement_timeout). Monsieur Claude

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

create or replace function public.qc_ckt_ung_vien(p_so int default 60) returns table (
  id bigint, page_name text, customer_name text, sale_name text, verdict text, tin_cuoi_luc timestamp, phut_cho int, doan_cuoi text)
language sql stable security definer set search_path = public, extensions as $$
  with tn as (select distinct on (review_id) review_id, ket from qc_khach_tiem_nang order by review_id, ngay desc, danh_gia_luc desc),
  s as (select s.id, s.page_name, s.customer_name, s.sale_name, s.verdict,
               array(select l from regexp_split_to_table(s.full_thread, E'\n') with ordinality x(l, n)
                     where l ~ '^\[\d{4}-\d\d-\d\d \d\d:\d\d\] ' and l !~ '^\[[^]]+\] Bot:' order by n) ls
        from sale_response_review s join tn on tn.review_id = s.id
        where tn.ket in ('tiem_nang', 'chua_du') and s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false)
          and s.conv_id not like 'pzl\_%'),   -- chỉ Social (20/11)
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

-- Dọn dữ liệu Zalo (đã chạy 20/11/2026 — giữ để tra lại, KHÔNG chạy lại)
-- select qc_chup_sao_luu('20/11 bỏ đánh giá tiềm năng Zalo — trước khi trả #3479 về Đúng');
-- insert into qc_sao_luu (ly_do, bang, so_dong, du_lieu)
--   select '20/11 bỏ đánh giá tiềm năng Zalo', 'qc_khach_tiem_nang', count(*), coalesce(jsonb_agg(to_jsonb(k)), '[]')
--   from qc_khach_tiem_nang k join sale_response_review s on s.id = k.review_id where s.conv_id like 'pzl\_%';
-- insert into qc_sao_luu (ly_do, bang, so_dong, du_lieu)
--   select '20/11 bỏ đánh giá tiềm năng Zalo', 'qc_chua_khai_thac', count(*), coalesce(jsonb_agg(to_jsonb(c)), '[]')
--   from qc_chua_khai_thac c join sale_response_review s on s.id = c.review_id where s.conv_id like 'pzl\_%';
-- update sale_response_review set verdict = 'dung', severity = null, issue = null, suggestion = null, reviewed_at = now()
--   where id = 3479 and issue like 'Chưa khai thác hết:%';
-- delete from qc_chua_khai_thac c using sale_response_review s where s.id = c.review_id and s.conv_id like 'pzl\_%';
-- delete from qc_khach_tiem_nang k using sale_response_review s where s.id = k.review_id and s.conv_id like 'pzl\_%';

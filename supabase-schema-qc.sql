-- APP QC CSKH — cổng MÃ TRUY CẬP (không tài khoản) cho trang xem kết quả chấm.
-- Vì sao (28/9/2026): app chỉ anh Hải + giám đốc xem, không cấp tài khoản cho nhân sự. Trang nằm trên
-- github.io công khai còn bảng chấm có SĐT + nội dung chat của khách, nên KHÔNG mở khoá anon cho bảng.
-- Trang gọi các hàm dưới đây kèm mã; hàm kiểm mã (lưu dạng băm) rồi mới đọc/ghi bằng quyền chủ hàm.
-- Bảng sale_response_review / sale_review_report giữ nguyên luật cũ (chỉ authenticated đọc).
-- Monsieur Claude

create extension if not exists pgcrypto with schema extensions;

-- Ai chấm dòng này: 'luat' (tools/cham-luat.js) | 'sonnet' (agent cham-qc) | null = chấm tay / job cũ.
-- Thêm 28/9/2026 để soát riêng từng tầng. Job cũ bên mkt-sale-app không ghi cột này (không ảnh hưởng).
alter table public.sale_response_review add column if not exists cham_boi text;

-- page_id (29/9/2026): tên page viết nhiều kiểu (Thuỷ/Thủy, "-"/"|") nên lọc theo tên bị lệch. Job mới của QC ghi thẳng;
-- dòng cũ lấy từ pancake_url (https://pancake.vn/{page_id}?c_id=...).
alter table public.sale_response_review add column if not exists page_id text;
update public.sale_response_review set page_id = substring(pancake_url from 'pancake\.vn/([^?]+)\?')
 where page_id is null and pancake_url is not null;

create table if not exists public.qc_cau_hinh (
  khoa      text primary key,
  gia_tri   text not null,
  cap_nhat  timestamptz not null default now()
);
alter table public.qc_cau_hinh enable row level security;   -- không policy nào: chỉ hàm chủ + service role
revoke all on public.qc_cau_hinh from anon, authenticated;

-- Chặn nếu sai mã (chậm lại 0,8s để chống dò). 28P01 -> PostgREST trả 403.
create or replace function public.qc_chan(p_ma text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare h text;
begin
  select gia_tri into h from qc_cau_hinh where khoa = 'ma_truy_cap';
  if h is null or coalesce(p_ma, '') = '' or crypt(p_ma, h) <> h then
    perform pg_sleep(0.8);
    raise exception 'Sai mã truy cập' using errcode = '28P01';
  end if;
end $$;

-- Danh sách lượt chấm (KHÔNG kèm full_thread cho nhẹ — mở từng dòng mới tải). Bỏ nhóm Zalo pzl_g_.
-- 29/9/2026: nhận khoảng ngày (trang mặc định 30 ngày; null = tất cả) và bỏ luôn dòng khong_lien_quan (trang vốn ẩn)
-- → mỗi lần mở trang không còn tải cả bảng ~1,5 MB (quota egress chung với app MKT/Sale).
drop function if exists public.qc_ds_cham(text);
create or replace function public.qc_ds_cham(p_ma text, p_tu date default null, p_den date default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.conv_date desc, x.id)
    from (select id, conv_date, conv_at, page_name, conv_id, customer_name, phone, sale_name,
                 customer_ask, sale_reply, verdict, issue, suggestion, severity, source_faq,
                 reviewed_at, pancake_url, cham_boi
          from sale_response_review
          where conv_id not like 'pzl\_g\_%' and verdict <> 'khong_lien_quan'
            and (p_tu is null or conv_date >= p_tu) and (p_den is null or conv_date <= p_den)) x), '[]'::jsonb);
end $$;

create or replace function public.qc_hoi_thoai(p_ma text, p_id bigint) returns text
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  return (select full_thread from sale_response_review where id = p_id);
end $$;

create or replace function public.qc_ds_bao_sai(p_ma text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  -- kèm verdict HIỆN TẠI của lượt chấm (verdict_moi) để trang Lịch sử xử lý thấy "trước → sau"
  return coalesce((select jsonb_agg(to_jsonb(r) || jsonb_build_object('verdict_moi', s.verdict, 'customer_ask', coalesce(r.customer_ask, s.customer_ask))
                                    order by r.created_at desc)
                   from sale_review_report r left join sale_response_review s on s.id = r.review_id), '[]'::jsonb);
end $$;

-- Báo 1 lượt chấm sai. Ảnh: tối đa 3 data URL đã nén (<= ~250KB mỗi ảnh). Không tự xoá báo cáo cũ.
create or replace function public.qc_bao_sai(p_ma text, p_review_id bigint, p_note text,
                                             p_images text[] default '{}', p_nguoi text default null)
returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare r sale_response_review; v_id bigint;
begin
  perform qc_chan(p_ma);
  if coalesce(trim(p_note), '') = '' then raise exception 'Chưa ghi sai ở chỗ nào'; end if;
  select * into r from sale_response_review where id = p_review_id;
  if not found then raise exception 'Không thấy lượt chấm #%', p_review_id; end if;
  if coalesce(array_length(p_images, 1), 0) > 3 then raise exception 'Tối đa 3 ảnh'; end if;
  if exists (select 1 from unnest(coalesce(p_images, '{}')) u
             where u !~ '^data:image/(png|jpe?g|webp);base64,' or length(u) > 350000) then
    raise exception 'Ảnh không hợp lệ hoặc quá nặng';
  end if;
  insert into sale_review_report (review_id, conv_date, page_name, customer_name, customer_ask,
                                  verdict_old, note, images, reporter)
  values (r.id, r.conv_date, r.page_name, r.customer_name, left(r.customer_ask, 1000),
          r.verdict, left(trim(p_note), 2000), coalesce(p_images, '{}'), left(nullif(trim(p_nguoi), ''), 100))
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.qc_xu_ly_bao_sai(p_ma text, p_id bigint, p_ghi_chu text default null,
                                                   p_nguoi text default null)
returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  update sale_review_report
     set status = 'fixed', resolved_at = now(),
         resolved_by = left(nullif(trim(p_nguoi), ''), 100),
         resolve_note = left(nullif(trim(p_ghi_chu), ''), 1000)
   where id = p_id;
end $$;

create or replace function public.qc_doi_ma(p_ma text, p_ma_moi text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  if length(coalesce(p_ma_moi, '')) < 8 then raise exception 'Mã mới phải từ 8 ký tự'; end if;
  update qc_cau_hinh set gia_tri = crypt(p_ma_moi, gen_salt('bf')), cap_nhat = now()
   where khoa = 'ma_truy_cap';
end $$;

-- Quyền: chỉ các hàm có kiểm mã được gọi từ trang (anon); qc_chan là hàm nội bộ.
revoke execute on function public.qc_chan(text) from public, anon, authenticated;
revoke execute on function public.qc_ds_cham(text, date, date), public.qc_hoi_thoai(text, bigint),
  public.qc_ds_bao_sai(text), public.qc_bao_sai(text, bigint, text, text[], text),
  public.qc_xu_ly_bao_sai(text, bigint, text, text), public.qc_doi_ma(text, text) from public;
grant execute on function public.qc_ds_cham(text, date, date), public.qc_hoi_thoai(text, bigint),
  public.qc_ds_bao_sai(text), public.qc_bao_sai(text, bigint, text, text[], text),
  public.qc_xu_ly_bao_sai(text, bigint, text, text), public.qc_doi_ma(text, text) to anon, authenticated;

-- Mã ban đầu đặt bằng script riêng (không ghi mã rõ vào file này):
--   insert into qc_cau_hinh (khoa, gia_tri) values ('ma_truy_cap', crypt('<mã>', gen_salt('bf')))
--   on conflict (khoa) do nothing;

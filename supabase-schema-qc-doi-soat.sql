-- ĐỐI CHIẾU KÉO VỀ / LỌC RA (anh Hải 7/10/2026: "số kéo về vs số lọc ra liệt kê vào phần nào cho t, để t còn check k sót;
-- số còn lại cho vào chấm thì bên chất lượng phản hồi"). Trang: Cài đặt › Nhật ký chạy. Monsieur Claude

-- Mỗi lượt kéo ghi thêm số lượt tự lọc ngay lúc kéo
alter table public.qc_nhat_ky_chay add column if not exists luot_loc int;

-- Theo ngày: kéo về (mọi lượt khách, trừ nhóm Zalo) → lọc ra (lúc kéo / khi chấm) → vào chấm (đã chấm / chờ / miss / lỗi nền tảng)
create or replace function public.qc_doi_soat_ngay(p_ma text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.ngay desc) from (
    select conv_date ngay,
      count(*) keo_ve,
      count(*) filter (where verdict = 'khong_lien_quan') loc_ra,
      count(*) filter (where verdict = 'khong_lien_quan' and cham_boi = 'luat' and issue like 'Tự lọc lúc kéo%') loc_luc_keo,
      count(*) filter (where verdict = 'khong_lien_quan' and not (cham_boi = 'luat' and coalesce(issue, '') like 'Tự lọc lúc kéo%')) loc_khi_cham,
      count(*) filter (where verdict <> 'khong_lien_quan') vao_cham,
      count(*) filter (where verdict in ('dung', 'thieu', 'sai')) da_cham,
      count(*) filter (where verdict in ('chua_cham', 'tra_loi_inbox')) cho_cham,
      count(*) filter (where verdict in ('khong_tra_loi', 'chi_bot')) miss,
      count(*) filter (where verdict = 'loi_nen_tang') loi_nen_tang
    from sale_response_review
    where conv_id not like 'pzl\_g\_%' and conv_date between p_tu and p_den
    group by conv_date) x), '[]'::jsonb);
end $$;

-- Danh sách lượt bị lọc ra (để soát) — 1 ngày hoặc khoảng ngày
create or replace function public.qc_ds_loc(p_ma text, p_tu date, p_den date) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(x) order by x.conv_at desc nulls last, x.id desc) from (
    select id, conv_date, conv_at, page_id, page_name, conv_id, customer_name, customer_ask, sale_name, issue, cham_boi, pancake_url,
           left(full_thread, 1500) full_thread
    from sale_response_review
    where verdict = 'khong_lien_quan' and conv_id not like 'pzl\_g\_%' and conv_date between p_tu and p_den
    limit 2000) x), '[]'::jsonb);
end $$;

revoke execute on function public.qc_doi_soat_ngay(text, date, date), public.qc_ds_loc(text, date, date) from public;
grant execute on function public.qc_doi_soat_ngay(text, date, date), public.qc_ds_loc(text, date, date) to anon, authenticated;

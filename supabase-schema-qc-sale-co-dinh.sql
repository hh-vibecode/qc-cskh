-- SALE CỐ ĐỊNH THEO PAGE (anh Hải 7/10/2026: "từ tháng 10/2026 tất cả tin nhắn tới từ Hiền Thủy, Shidai và Nến Tự Tại Viên
-- đều là của Vân Ngọc"). Tên admin Pancake không đáng tin (tài khoản dùng chung, trống tên, người khác trả lời hộ) → gán cứng.
-- Cấu hình ở qc_cau_hinh khoa 'sale_co_dinh' = {"<page_id>": {"sale": "...", "tu": "YYYY-MM-DD"}, ...}.
-- Trigger chạy cho MỌI lần ghi (job kéo tin, soát miss, chấm) nên không phải sửa từng công cụ. Monsieur Claude
create or replace function public.qc_gan_sale_co_dinh() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare c jsonb;
begin
  select gia_tri::jsonb into c from qc_cau_hinh where khoa = 'sale_co_dinh';
  if c is not null and new.page_id is not null and c ? new.page_id
     and new.conv_date >= coalesce((c -> new.page_id ->> 'tu')::date, '1900-01-01') then
    new.sale_name := c -> new.page_id ->> 'sale';
  end if;
  return new;
end $$;
revoke execute on function public.qc_gan_sale_co_dinh() from public, anon, authenticated;

drop trigger if exists qc_sale_co_dinh on public.sale_response_review;
create trigger qc_sale_co_dinh before insert or update on public.sale_response_review
  for each row execute function public.qc_gan_sale_co_dinh();

insert into qc_cau_hinh (khoa, gia_tri) values ('sale_co_dinh', '{
  "105133802417722": {"sale": "Vân Ngọc", "tu": "2026-10-01", "ghi_chu": "Siêu Thị Phật Giáo Hiền Thuỷ (FB)"},
  "107792638827892": {"sale": "Vân Ngọc", "tu": "2026-10-01", "ghi_chu": "Hiền Thủy - Siêu Thị Đồ Thờ & Đồ Mã (FB)"},
  "ttm_-000uG5lXadOZHV4VWlMRAHc5FZGkQtuyxY3": {"sale": "Vân Ngọc", "tu": "2026-10-01", "ghi_chu": "Hiền Thuỷ (TikTok)"},
  "pzl_1927214341338004925": {"sale": "Vân Ngọc", "tu": "2026-10-01", "ghi_chu": "Siêu Thị Phật Giáo Hiền Thủy (Zalo)"},
  "pzl_716330578937743406": {"sale": "Vân Ngọc", "tu": "2026-10-01", "ghi_chu": "Siêu Thị Đồ Thờ Cao Cấp (Zalo, Hiền Thủy)"},
  "100667699549693": {"sale": "Vân Ngọc", "tu": "2026-10-01", "ghi_chu": "Nến Bơ - Tự Tại Viên (FB)"},
  "506247572578559": {"sale": "Vân Ngọc", "tu": "2026-10-01", "ghi_chu": "Thời Đại - Tổng Kho Sỉ (FB, Shidai)"}
}') on conflict (khoa) do update set gia_tri = excluded.gia_tri;

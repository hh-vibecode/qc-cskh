-- HỘI THOẠI NỘI BỘ / NHÀ CUNG CẤP (anh Hải 16/10/2026 "làm đi"): Zalo Hiền Thủy / Shidai… có nhiều cuộc chat với nhà cung cấp,
-- kế toán, đồng nghiệp (Sale là bên mua / thanh toán). Trước đây mỗi lần bên kia nhắn thêm, job kéo đưa cả hội thoại về chờ chấm
-- LẠI → tốn lượt chấm. Nay: dòng đã chấm khong_lien_quan với issue bắt đầu "Nội bộ / NCC:" → noi_bo = true (trigger), job kéo chỉ
-- nối thread, KHÔNG chấm lại. Sửa verdict khác khong_lien_quan (báo sai) → tự bỏ đánh dấu. Monsieur Claude
alter table public.sale_response_review add column if not exists noi_bo boolean not null default false;

create or replace function public.qc_danh_dau_noi_bo() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.verdict = 'khong_lien_quan' and coalesce(new.issue, '') ~* '^nội bộ / ncc' then new.noi_bo := true;
  elsif new.verdict is distinct from 'khong_lien_quan' then new.noi_bo := false;
  end if;
  return new;
end $$;
drop trigger if exists qc_danh_dau_noi_bo on public.sale_response_review;
create trigger qc_danh_dau_noi_bo before insert or update of verdict, issue on public.sale_response_review
  for each row execute function public.qc_danh_dau_noi_bo();

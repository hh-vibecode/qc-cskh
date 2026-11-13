-- DỮ LIỆU ZALO ĐÃ LỌC CHO BÁO CÁO CÔNG VIỆC CỦA APP MKT/SALE (yêu cầu 13/11/2026, anh Hải duyệt).
-- App MKT CHỈ ĐỌC view qc_zalo_phan_hoi_ngay. Đổi cột về sau: CHỈ THÊM, không đổi tên / xoá (app MKT đang đọc).
-- 1 dòng = 1 khách Zalo × 1 Sale × 1 ngày (giờ VN), từ 01/10/2026. LỌC TRƯỚC: bỏ hội thoại không qua bộ lọc QC
-- (verdict khong_lien_quan: khấn, rác, nội bộ / NCC, tin hệ thống…), bỏ nhóm pzl_g_, bỏ tin Bot và tin "Sale:" không tên
-- (chào / ảnh tự động). Không có cột nội dung tin.
--   sale       : tên ở sale_nhan_su.ten. Lấy từ tên người trả lời trên Pancake qua bảng qc_sale_ten; ngày khách nhắn mà chưa
--                Sale nào trả lời → Sale mặc định theo thương hiệu (quy tắc QC 28/10: HT+TTV Vân Ngọc · Shidai Nguyên · CT Lệ).
--                Không khớp được tên nhân sự → null.
--   da_tra_loi : luôn true từ 13/11 (2) — view chỉ còn ngày Sale có trả lời khách.
--   khach_nhan : khách có nhắn trong ngày; false = Sale nhắn chủ động.
--   ma_kh      : CHƯA CÓ — QC chưa đọc ghi chú khách Pancake (để null, bổ sung sau).
-- View chạy theo quyền người đọc (security_invoker) — authenticated đọc được như sale_response_review. Monsieur Claude

-- Đối chiếu tên Pancake → tên nhân sự (sale_nhan_su là bảng app MKT, QC chỉ đọc)
create table if not exists public.qc_sale_ten (
  ten_pancake text primary key,
  ten_nhan_su text,            -- đúng sale_nhan_su.ten; null = không phải nhân sự / chưa xác định
  ghi_chu     text
);
alter table public.qc_sale_ten enable row level security;
drop policy if exists "doc qc_sale_ten" on public.qc_sale_ten;
create policy "doc qc_sale_ten" on public.qc_sale_ten for select to authenticated using (true);
grant select on public.qc_sale_ten to authenticated;
insert into public.qc_sale_ten (ten_pancake, ten_nhan_su, ghi_chu) values
  ('Vân Ngọc', 'Trịnh Lê Vân Ngọc', null),
  ('Nguyên Khánh', 'Nguyễn Khánh Nguyên', 'Zalo Tổng Kho Sỉ Đồ Thờ Shidai là của Nguyên (anh Hải 13/11)'),
  ('Oanhh Bùi', 'Bùi Thị Kim Oanh', 'Zalo Oanh Bùi Tổng Kho Sỉ là của Oanh (anh Hải xác nhận 13/11)'),
  ('Lệ', 'Phạm Thị Lệ', 'mặc định Chánh Tâm'),
  ('Chánh Tâm Ngọc Diệp', 'Đinh Ngọc Diệp', null),
  ('Đức Tuấn Chánh Tâm', 'Nguyễn Đức Anh Tuấn', 'anh Hải xác nhận 13/11'),
  ('Nguyễn Thảo Ngọc', 'Nguyễn Thảo Ngọc', null),
  ('PANCAKE THT HOLDING', null, 'tài khoản dùng chung'),
  ('Sales Admin', null, 'tài khoản dùng chung')
on conflict (ten_pancake) do update set ten_nhan_su = excluded.ten_nhan_su, ghi_chu = excluded.ghi_chu;

-- 13/11 (2) anh Hải: báo cáo cho app chỉ cần "trong ngày Sale TRẢ LỜI khách nào" — không quan tâm tin trước đã trả lời hay chưa.
-- → CHỈ giữ ngày Sale có nhắn cho khách; ngày khách nhắn mà không Sale nào nhắn thì KHÔNG đưa vào. Cột giữ nguyên (app MKT đang đọc):
-- da_tra_loi luôn true (= Sale đã trả lời khách trong ngày), khach_nhan = khách có nhắn trong ngày đó không (false = Sale nhắn chủ động).
-- Trên ZALO tin Sale gửi từ điện thoại KHÔNG mang tên ("Sale: …") = CHỦ Zalo trả lời → gán chủ Zalo (qc_sale_mac_dinh).
create or replace view public.qc_zalo_phan_hoi_ngay with (security_invoker = true) as
with hoi as (
  select s.id, s.page_id, s.page_name, s.conv_id, s.customer_name, s.phone,
         coalesce(s.khach_id, nullif(regexp_replace(s.conv_id, '^pzl_u_\d+_', ''), s.conv_id)) as khach_id, s.full_thread
  from public.sale_response_review s
  where s.page_id like 'pzl\_%' and s.conv_id not like 'pzl\_g\_%' and s.conv_date >= '2026-10-01'
    and s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false)
),
dong as (
  select h.id, m[1]::date as ngay, m[2] as ai, lower(trim(m[3])) as nd
  from hoi h, regexp_split_to_table(h.full_thread, E'\n') l,
       regexp_match(l, '^\[(\d{4}-\d\d-\d\d) \d\d:\d\d\] ([^:]+): ?(.*)$') m
  where m is not null and m[1] >= '2026-10-01'
),
sale_ngay as (   -- ai nhắn cho khách trong ngày; khoá '' = chủ Zalo (tin không tên / tài khoản dùng chung)
  select distinct id, ngay,
         coalesce(case when ai ~ '^Sale \(.+\)$' and substring(ai from '^Sale \((.+)\)$') !~* '^(pancake tht holding|sales? admin)$'
                       then substring(ai from '^Sale \((.+)\)$') end, '') as sk
  from dong where ai ~ '^Sale( \(.+\))?$'
),
khach_ngay as (
  select distinct id, ngay from dong
  where ai = 'Khách' and nd !~ '(sinh nhật của .* hãy gửi lời chúc|đã đồng ý kết bạn|lời mời kết bạn|vừa kết bạn với)'
)
select sn.ngay,
       case when sn.sk = '' then t2.ten_nhan_su else t1.ten_nhan_su end as sale,
       h.conv_id, h.khach_id, h.customer_name as ten_khach, h.phone as sdt, null::text as ma_kh,
       true as da_tra_loi,
       (kn.id is not null) as khach_nhan,
       h.page_name as kenh,
       nullif(sn.sk, '') as sale_pancake
from sale_ngay sn
join hoi h on h.id = sn.id
left join khach_ngay kn on kn.id = sn.id and kn.ngay = sn.ngay
left join public.qc_sale_ten t1 on t1.ten_pancake = sn.sk
left join public.qc_sale_ten t2 on t2.ten_pancake = public.qc_sale_mac_dinh(h.page_id, h.page_name);

grant select on public.qc_zalo_phan_hoi_ngay to authenticated;
revoke all on public.qc_zalo_phan_hoi_ngay from anon;

-- GÁN SALE KHI LƯỢT NÀY KHÔNG CÓ TÊN NGƯỜI TRẢ LỜI (23/11/2026, app MKT báo ca Phan Dung #22316 — Thời Đại):
-- ngày 23/11 khách nhắn, Sale chưa trả lời → sale_name trống → trigger gán theo thương hiệu (Thời Đại / Shidai = Nguyên Khánh)
-- dù cả hội thoại do Vân Ngọc nhắn. Luật anh chốt 28/10: "tên người trả lời trên Pancake; không phân biệt được người → theo
-- thương hiệu". Nay: trống / tên chung → lấy tên ở TIN SALE CUỐI trong full_thread nếu tin đó có tên người ("Sale (Tên):");
-- tin Sale cuối KHÔNG có tên (Zalo cá nhân = chủ Zalo, tin tự động) → vẫn theo thương hiệu như cũ. Monsieur Claude
create or replace function public.qc_sale_theo_thuong_hieu() returns trigger
language plpgsql set search_path = public as $$
declare moi text; cuoi text;
begin
  -- anh Hải 28/10: LỌC TRƯỚC, chỉ xử lý tin đã qua bộ lọc — dòng "không liên quan" (khấn, nội bộ, spam…) không gán Sale
  if new.verdict = 'khong_lien_quan' then return new; end if;
  if coalesce(trim(new.sale_name), '') = '' or new.sale_name ~* '^(pancake tht holding|sales? admin|botcake)$' then
    -- Zalo cá nhân (pzl_): tin Sale CUỐI không tên = chủ Zalo → theo thương hiệu. Facebook / TikTok: tin không tên là lời chào
    -- tự động → bỏ qua, lấy người CÓ TÊN nhắn gần nhất (ca Phi Hoàng #22179: tin cuối "Sale: Tổng kho Thời Đại xin chào").
    select nullif(m[2], '') into cuoi
    from regexp_matches(coalesce(new.full_thread, ''), '\] Sale( \(([^)]+)\))?:', 'g') with ordinality t(m, n)
    where new.page_id like 'pzl\_%' or m[2] is not null
    order by n desc limit 1;
    if cuoi ~* '^(pancake tht holding|sales? admin|botcake)$' then cuoi := null; end if;
    new.sale_name := coalesce(cuoi, qc_sale_mac_dinh(new.page_id, new.page_name), nullif(trim(new.sale_name), ''));
  end if;
  -- người đã nghỉ: từ mốc ngày tính cho người nhận (qc_sale_chuyen)
  select c.ten_moi into moi from qc_sale_chuyen c
   where c.ten_cu = new.sale_name and (coalesce(new.conv_at, now()) at time zone 'Asia/Ho_Chi_Minh')::date >= c.tu_ngay
   order by c.tu_ngay desc limit 1;
  if moi is not null then new.sale_name := moi; end if;
  return new;
end $$;
alter function public.qc_sale_theo_thuong_hieu() set statement_timeout = '20s';

-- Sửa dòng cũ (từ 1/10, đã qua lọc): đang mang tên mặc định theo thương hiệu mà tin Sale cuối có tên người khác.
-- CHẠY SAU khi đã select qc_chup_sao_luu('…').
with x as (
  select s.id, s.sale_name,
         (select nullif(m[2], '') from regexp_matches(s.full_thread, '\] Sale( \(([^)]+)\))?:', 'g') with ordinality t(m, n)
           where s.page_id like 'pzl\_%' or m[2] is not null order by n desc limit 1) sale_cuoi
  from sale_response_review s
  where s.verdict <> 'khong_lien_quan' and s.conv_date >= '2026-10-01'
    and s.sale_name = qc_sale_mac_dinh(s.page_id, s.page_name))
update sale_response_review s set sale_name = x.sale_cuoi
from x
where s.id = x.id and x.sale_cuoi is not null and x.sale_cuoi !~* '^(pancake tht holding|sales? admin|botcake)$'
  and coalesce((select ten_nhan_su from qc_sale_ten where ten_pancake = x.sale_cuoi), x.sale_cuoi)
      <> coalesce((select ten_nhan_su from qc_sale_ten where ten_pancake = x.sale_name), x.sale_name);

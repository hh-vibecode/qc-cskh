-- GÁN SALE (anh Hải 28/10/2026 — THAY quy tắc gán cứng 7 page = Vân Ngọc từ 1/10, trigger qc_sale_co_dinh ĐÃ GỠ):
--   1. Sale = TÊN NGƯỜI trả lời trên Pancake ("Sale (Tên): …", người nhắn cuối trong hội thoại) — job kéo / soát miss ghi.
--   2. Không phân biệt được người (chưa ai trả lời, hoặc tài khoản dùng chung "PANCAKE THT HOLDING", "Sales Admin")
--      → theo THƯƠNG HIỆU: Hiền Thủy + Tự Tại Viên = Vân Ngọc · Shidai (gồm Thời Đại) = Nguyên Khánh · Chánh Tâm = Lệ.
-- Trigger qc_sale_theo_thuong_hieu chỉ điền khi sale_name trống / tài khoản chung — không bao giờ đè tên người thật.
-- Cấu hình cũ giữ trong qc_cau_hinh 'sale_co_dinh' (ngung 28/10) để tra lịch sử. Monsieur Claude
drop trigger if exists qc_sale_co_dinh on public.sale_response_review;

create or replace function public.qc_sale_mac_dinh(p_page_id text, p_page_name text) returns text
language sql immutable set search_path = public as $$
  select case
    when p_page_id in ('105133802417722','107792638827892','ttm_-000uG5lXadOZHV4VWlMRAHc5FZGkQtuyxY3','pzl_1927214341338004925','pzl_716330578937743406','100667699549693')
      then 'Vân Ngọc'
    when p_page_id in ('506247572578559','pzl_421283811192749346','pzl_636053762312360623') then 'Nguyên Khánh'
    when p_page_id in ('107224335550589','1212423508625663','ttm_-000fnwmEFDETu8kL8prpYMAbgrdue0Cc0hG','pzl_355233102341719971','pzl_357024678860117283','ttm_-000wff5HiYIrt76uNDUJiL1kfVVtVkiURi-')
      then 'Lệ'
    -- page mới chưa có trong danh sách: đoán theo tên page (CSDL chung không có unaccent — không tự cài)
    when lower(coalesce(p_page_name,'')) ~ 'hiền th|hien th|tự tại|tu tai|nến bơ|cao cấp' then 'Vân Ngọc'
    when lower(coalesce(p_page_name,'')) ~ 'shidai|thời đại|thoi dai' then 'Nguyên Khánh'
    when lower(coalesce(p_page_name,'')) ~ 'chánh tâm|chanh tam|hoàng dương|ming ying' then 'Lệ'
  end $$;

create or replace function public.qc_sale_theo_thuong_hieu() returns trigger
language plpgsql set search_path = public as $$
begin
  -- anh Hải 28/10: LỌC TRƯỚC, chỉ xử lý tin đã qua bộ lọc — dòng "không liên quan" (khấn, nội bộ, spam…) không gán Sale
  if new.verdict = 'khong_lien_quan' then return new; end if;
  if coalesce(trim(new.sale_name), '') = '' or new.sale_name ~* '^(pancake tht holding|sales? admin|botcake)$' then
    new.sale_name := coalesce(qc_sale_mac_dinh(new.page_id, new.page_name), nullif(trim(new.sale_name), ''));
  end if;
  return new;
end $$;
drop trigger if exists qc_sale_theo_thuong_hieu on public.sale_response_review;
create trigger qc_sale_theo_thuong_hieu before insert or update of sale_name, page_id, verdict on public.sale_response_review
  for each row execute function public.qc_sale_theo_thuong_hieu();

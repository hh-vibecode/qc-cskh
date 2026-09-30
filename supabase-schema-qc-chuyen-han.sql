-- CHUYỂN HẲN kéo tin sang job QC (30/9/2026, anh Hải: "báo con app đóng luồng… để m tự chạy").
-- Đưa các lượt job mới đã kéo vào bảng thử qc_review_thu (chưa có ở bảng chính) sang sale_response_review,
-- rồi nối mốc kéo tin để job ghi bảng chính chạy tiếp từ đúng chỗ. Chạy lại được nhiều lần (không đẻ trùng).
-- Chống trùng giống job: (conv_id, 160 ký tự đầu câu hỏi) hoặc (conv_id, giờ khách bắt đầu hỏi, làm tròn giây).
-- Monsieur Claude
insert into public.sale_response_review
  (conv_date, conv_at, page_name, page_id, conv_id, customer_name, phone, sale_name, customer_ask, sale_reply,
   verdict, issue, suggestion, severity, source_faq, full_thread, pancake_url)
select t.conv_date, t.conv_at, t.page_name, t.page_id, t.conv_id, t.customer_name, t.phone, t.sale_name, t.customer_ask,
       t.sale_reply, t.verdict, t.issue, t.suggestion, t.severity, t.source_faq, t.full_thread, t.pancake_url
from public.qc_review_thu t
where not exists (
  select 1 from public.sale_response_review s
  where s.conv_id = t.conv_id
    and (left(s.customer_ask, 160) = left(t.customer_ask, 160)
         or date_trunc('second', s.conv_at) = date_trunc('second', t.conv_at)));

insert into public.qc_cau_hinh (khoa, gia_tri)
select 'moc_keo:sale_response_review', gia_tri from public.qc_cau_hinh where khoa = 'moc_keo:qc_review_thu'
on conflict (khoa) do update set gia_tri = excluded.gia_tri, cap_nhat = now();

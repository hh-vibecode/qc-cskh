-- MÃ KHÁCH PANCAKE (13/10/2026, báo sai #52/#56): bình luận và tin nhắn riêng của CÙNG một khách là 2 hội thoại khác conv_id
-- nhưng chung customer id trên Pancake. Lưu lại để job kéo nối tin Sale nhắn riêng (private reply, khách chưa nhắn lại) vào
-- dòng BÌNH LUẬN của chính khách đó — trước đây phần này bị bỏ vì hội thoại inbox không có lượt khách. Monsieur Claude
alter table public.sale_response_review add column if not exists khach_id text;
create index if not exists sale_response_review_page_khach_idx on public.sale_response_review (page_id, khach_id) where khach_id is not null;

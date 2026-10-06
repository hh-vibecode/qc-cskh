-- SAI QUY TRÌNH (anh Hải 6/10/2026): thẻ "Hội thoại sai quy trình" thay thẻ "Tư vấn qua tin nhắn".
-- Ngoài đúng/thiếu/sai nội dung, mỗi hội thoại chấm thêm có đúng quy trình không (vd: trả lời / báo giá công khai
-- dưới bình luận là SAI — phải dẫn về tin nhắn riêng). Cột NULL = đúng quy trình / chưa xét; có chữ = lý do sai.
-- Bộ quy tắc chi tiết anh gửi sau → ghi vào .claude/agents/cham-qc.md + routine/cham-cloud.md. Monsieur Claude
alter table public.sale_response_review add column if not exists sai_quy_trinh text;

create or replace function public.qc_ds_cham(p_ma text, p_tu date default null, p_den date default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.conv_date desc, x.id)
    from (select id, conv_date, conv_at, page_name, conv_id, customer_name, phone, sale_name,
                 customer_ask, sale_reply, verdict, issue, suggestion, severity, source_faq,
                 reviewed_at, pancake_url, cham_boi, page_id, sai_quy_trinh
          from sale_response_review
          where conv_id not like 'pzl\_g\_%' and verdict <> 'khong_lien_quan'
            and (p_tu is null or conv_date >= p_tu) and (p_den is null or conv_date <= p_den)) x), '[]'::jsonb);
end $$;

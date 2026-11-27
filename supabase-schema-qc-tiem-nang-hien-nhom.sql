-- MÀN QC HIỆN THẺ TIỀM NĂNG THEO NHÓM CUỐI (anh Hải 27/11 qua app MKT: "bảo nó gắn thẻ cho chuẩn đi").
-- Ca anh phản ánh: Anh Thu Nguyen (Thời Đại, 506247572578559_29481050874866580) — màn QC hiện "Khách tiềm năng" (theo ket)
-- nhưng view qc_khach_tiem_nang_ngay xếp nhom = dat ("Báo giá xong khách chưa phản hồi", luật 23/11) → Pancake gắn LEAD ĐẠT.
-- GIỮ luật 23/11, chỉ sửa cách hiện: RPC của màn QC trả thêm nhom / ly_do_nhom LẤY TỪ CHÍNH VIEW app MKT đọc, gắn đúng lần
-- đánh giá (cùng hội thoại + ngày + giờ đánh giá) — lần đánh giá cũ hơn (không còn trong view) giữ hiện theo ket.
-- Không đổi view (app MKT đang đọc nhom, ket). Chạy lại supabase-gioi-han-qc.sql sau file này. Monsieur Claude

create or replace function public.qc_ds_tiem_nang(p_ma text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  return coalesce((select jsonb_agg(jsonb_build_object('review_id', k.review_id, 'ngay', k.ngay, 'ket', k.ket, 'ly_do', k.ly_do,
      'danh_gia_luc', k.danh_gia_luc,
      -- kèm thông tin hội thoại: ngày đánh giá có thể sớm hơn conv_date (= ngày nhắn cuối) nên trang không dựa vào danh sách chấm đang tải
      'conv_date', s.conv_date, 'conv_at', s.conv_at, 'page_id', s.page_id, 'page_name', s.page_name, 'conv_id', s.conv_id,
      'customer_name', s.customer_name, 'phone', s.phone, 'sale_name', s.sale_name, 'verdict', s.verdict, 'pancake_url', s.pancake_url,
      -- 20/11: thẻ "chưa khai thác hết" (Sale hứa quay lại rồi bỏ lửng — qc_chua_khai_thac)
      'ckt', (select c.ly_do from qc_chua_khai_thac c where c.review_id = k.review_id and c.ket order by c.tin_cuoi_luc desc limit 1),
      -- 27/11: nhóm cuối cùng như app MKT thấy (tiem_nang / dat) + lý do nhóm
      'nhom', v.nhom, 'ly_do_nhom', v.ly_do_nhom)
      order by k.ngay, k.review_id)
    from qc_khach_tiem_nang k join sale_response_review s on s.id = k.review_id
    left join qc_khach_tiem_nang_ngay v on v.pancake_conversation_id = s.conv_id and v.ngay = k.ngay and v.danh_gia_luc = k.danh_gia_luc
    where k.ngay >= date '2026-11-01' and s.verdict <> 'khong_lien_quan'), '[]'::jsonb);
end $$;

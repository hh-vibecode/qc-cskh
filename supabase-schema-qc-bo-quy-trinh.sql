-- BỎ CHẤM QUY TRÌNH (anh Hải chốt 20/11/2026: "bỏ sai quy trình đi, clear luôn, đổi thành dash tiềm năng tự đánh giá").
-- Xoá dữ liệu cũ (165 dòng, đã chụp sao lưu trước) + trigger giữ sai_quy_trinh luôn null dù bên chấm nào lỡ ghi.
-- Cột giữ nguyên (không đổi cấu trúc bảng; hàm cũ vẫn đọc được). Monsieur Claude
select qc_chup_sao_luu('20/11 bỏ chấm quy trình — xoá sai_quy_trinh');
update sale_response_review set sai_quy_trinh = null where sai_quy_trinh is not null;

create or replace function qc_bo_quy_trinh() returns trigger language plpgsql as $$
begin
  new.sai_quy_trinh := null;
  return new;
end $$;
drop trigger if exists qc_bo_quy_trinh on sale_response_review;
create trigger qc_bo_quy_trinh before insert or update of sai_quy_trinh on sale_response_review
  for each row when (new.sai_quy_trinh is not null) execute function qc_bo_quy_trinh();

-- GIỚI HẠN THỜI GIAN cho mọi hàm của QC (29/9/2026, anh Hải: "tách dữ liệu xử lý riêng để lỗi không ảnh hưởng tới nhau").
-- QC và app MKT/Sale chung 1 máy chủ Postgres (không tách project — tiết kiệm ~10 USD/tháng). Để một lỗi / truy vấn nặng
-- của QC không chiếm máy chủ làm chậm app kia: hàm qc_* chạy quá hạn là tự dừng.
-- Chạy lại được nhiều lần (tự áp cho cả hàm qc_* thêm sau này).
-- Monsieur Claude
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname
           from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'qc\_%' loop
    -- qc_keo_tin chỉ gửi 1 lời gọi GitHub (pg_net, bất đồng bộ) → 5s là dư; hàm đọc/ghi dữ liệu → 20s
    execute format('alter function %s set statement_timeout = %L', f.sig,
                   case when f.proname = 'qc_keo_tin' then '5s' else '20s' end);
  end loop;
end $$;

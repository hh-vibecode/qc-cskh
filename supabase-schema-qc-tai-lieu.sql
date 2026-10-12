-- TÀI LIỆU QUY TRÌNH (anh Hải 12/10/2026: "lưu mấy file quy trình t gửi, thỉnh thoảng vào check để cập nhật quy trình cho chuẩn").
-- Lưu nội dung các Google Sheet anh gửi (SOP tư vấn Sales Onl, Bảng khoảng giá) — KHÔNG để trong repo (repo công khai).
-- tools/kiem-tai-lieu.js tải lại mỗi sáng (lượt quét 6h20), so dấu vân tay: đổi → lưu bản mới + bản cũ để so, ghi Nhật ký chạy
-- (đỏ) để phiên Claude cập nhật luật chấm; bảng giá đổi thì nạp lại qc_bang_gia. Monsieur Claude
create table if not exists public.qc_tai_lieu (
  khoa          text primary key,      -- 'sop' | 'bang_gia'
  ten           text,
  url           text not null,
  noi_dung      text,                  -- toàn bộ các tab, dạng "### <tab>\n<csv>"
  noi_dung_cu   text,                  -- bản trước lần đổi gần nhất (để so)
  dau_van_tay   text,
  kiem_luc      timestamptz,
  thay_doi_luc  timestamptz,
  tom_tat_doi   text                   -- tab nào đổi, thêm / bớt bao nhiêu dòng
);
alter table public.qc_tai_lieu enable row level security;   -- không policy: chỉ khoá qc_cskh (job / máy)

insert into qc_tai_lieu (khoa, ten, url) values
  ('sop', 'QUY TRÌNH TƯ VẤN SALES ONL', 'https://docs.google.com/spreadsheets/d/e/2PACX-1vTxsN-xE-d-oyrAeMvO-H8ZKgeNTBwi9VljMEJxzYWqSGINO_cnwa7Q7A87eDqdb5GV-eDsp7yD2ezX/pubhtml'),
  ('bang_gia', 'BẢNG KHOẢNG GIÁ BÁO KHÁCH - SALES', 'https://docs.google.com/spreadsheets/d/e/2PACX-1vRTWC2wiYFlXNaCWl_t85vnqpydUhlh40Yh14P1iIsw7rM3gpmPk8tUNw4yjgFenEAkng6Fl1RNIJyu/pubhtml')
on conflict (khoa) do update set url = excluded.url, ten = excluded.ten;

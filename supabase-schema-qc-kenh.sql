-- KÊNH KẾT NỐI (anh Hải 1/10/2026: "cho vào nhật ký chạy, tất cả các page và zalo, trạng thái kết nối xanh đỏ, đỏ là
-- không đọc được, để sau còn biết kết nối lại với Pancake").
-- Mỗi lượt job kéo tin (scripts/keo-tin.js) ghi lại mọi page Pancake trả về (kích hoạt + không kích hoạt) và thử đọc hội thoại:
--   ok  = đọc được;  loi = không đọc được (Pancake trả lỗi, Zalo mất kết nối, cần sửa webhook, page chưa kích hoạt, token hết hạn).
-- Job ghi bằng khoá qc_cskh (REST); trang đọc qua qc_ds_kenh (mã truy cập). Monsieur Claude
create table if not exists public.qc_kenh (
  page_id       text primary key,
  ten           text,
  kenh          text,                    -- facebook | tiktok | zalo | khác (theo platform của Pancake)
  kich_hoat     boolean,                 -- nằm trong danh sách "activated" của Pancake
  trang_thai    text not null default 'ok' check (trang_thai in ('ok','loi')),
  ly_do         text,                    -- vì sao đỏ
  lan_kiem      timestamptz,             -- lượt kéo gần nhất có kiểm kênh này
  lan_ok        timestamptz,             -- lần gần nhất đọc được
  tin_moi_nhat  timestamptz,             -- hội thoại cập nhật mới nhất Pancake trả về
  so_hoi_thoai  int                      -- số hội thoại khách nhắn lấy được ở lượt gần nhất
);
alter table public.qc_kenh enable row level security;   -- không policy: chỉ khoá qc_cskh (job) và hàm security definer đọc/ghi

create or replace function public.qc_ds_kenh(p_ma text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  return coalesce((select jsonb_agg(to_jsonb(k) order by k.kich_hoat desc, k.trang_thai desc, k.kenh, k.ten) from qc_kenh k), '[]'::jsonb);
end $$;

revoke execute on function public.qc_ds_kenh(text) from public;
grant execute on function public.qc_ds_kenh(text) to anon, authenticated;

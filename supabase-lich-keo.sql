-- LỊCH KÉO TIN NHẮN CHO QC (anh Hải 29/9/2026: "lịch kéo tin nhắn loanh quanh 6-7h và 18-19h hàng ngày").
-- Vì sao không dùng lịch của GitHub: lịch GitHub trễ 5–8 tiếng (hẹn 7h05 chạy lúc ~12h, hẹn 15h05 chạy lúc ~23h35).
-- pg_cron của Supabase chạy đúng giờ → gọi GitHub API chạy workflow kéo tin (workflow_dispatch) kèm khoảng ngày.
-- Token GitHub để trong Supabase Vault (tên 'qc_gh_token'), đặt bằng script riêng — KHÔNG ghi trong file này.
--
-- Giờ chạy 6h20 / 18h35 (không phải 6h/18h): theo lưu ý phiên app MKT/Sale — Pancake dùng chung token, bên đó
-- tạo đơn 6h & 18h, phân loại SP 7h & 18h, ngày nhắn cuối phút 0–10 mỗi giờ.
-- Workflow: job MỚI của QC (repo qc-cskh, keo-tin.yml). Đang chạy song song → job mới ghi bảng thử qc_review_thu;
-- job cũ (mkt-sale-app sync-sale-review.yml) vẫn tự chạy theo lịch GitHub của nó và cấp dữ liệu cho trang.
-- Monsieur Claude

create extension if not exists pg_net;
create extension if not exists pg_cron;

create or replace function public.qc_keo_tin(p_tu date, p_den date) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_token text;
  v_id bigint;
  c_repo constant text := 'hh-vibecode/qc-cskh';
  c_wf   constant text := 'keo-tin.yml';
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'qc_gh_token';
  if v_token is null then raise exception 'Thiếu secret qc_gh_token trong Vault'; end if;
  select net.http_post(
    url := format('https://api.github.com/repos/%s/actions/workflows/%s/dispatches', c_repo, c_wf),
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_token, 'Accept', 'application/vnd.github+json',
                                  'User-Agent', 'qc-cskh', 'Content-Type', 'application/json'),
    body := jsonb_build_object('ref', 'main', 'inputs', jsonb_build_object('from', coalesce(p_tu::text, ''), 'to', coalesce(p_den::text, '')))
  ) into v_id;
  return v_id;
end $$;
revoke execute on function public.qc_keo_tin(date, date) from public, anon, authenticated;

-- 6h20 VN (23:20 UTC hôm trước): quét lại TRỌN ngày hôm qua (lưới an toàn).
-- Mỗi giờ phút :25 (anh Hải 29/9: "kéo tin và chấm cùng lúc, mỗi giờ 1 lần"): p_tu/p_den = null → job chạy chế độ MỐC,
-- chỉ kéo hội thoại khách nhắn từ lượt trước. Phiên chấm trên cloud chạy phút :50 cùng giờ.
-- 2 lượt QUÉT LỚN mỗi ngày (anh Hải 30/9: "làm 2 luồng 6h-7h và 18h-19h"), mỗi lượt còn soát lại miss 60 ngày:
--   6h20 VN (23:20 UTC hôm trước): kéo trọn HÔM QUA · 18h35 VN (11:35 UTC): kéo trọn HÔM NAY tới lúc đó.
select cron.unschedule(jobid) from cron.job where jobname in ('qc-keo-6h', 'qc-keo-18h', 'qc-keo-gio');
select cron.schedule('qc-keo-6h',  '20 23 * * *',
  $$select public.qc_keo_tin((now() at time zone 'Asia/Ho_Chi_Minh')::date - 1, (now() at time zone 'Asia/Ho_Chi_Minh')::date - 1)$$);
select cron.schedule('qc-keo-18h', '35 11 * * *',
  $$select public.qc_keo_tin((now() at time zone 'Asia/Ho_Chi_Minh')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date)$$);
select cron.schedule('qc-keo-gio', '25 * * * *', $$select public.qc_keo_tin(null, null)$$);

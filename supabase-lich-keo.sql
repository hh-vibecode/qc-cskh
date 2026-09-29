-- LỊCH KÉO TIN NHẮN CHO QC (anh Hải 29/9/2026: "lịch kéo tin nhắn loanh quanh 6-7h và 18-19h hàng ngày").
-- Vì sao không dùng lịch của GitHub: lịch GitHub trễ 5–8 tiếng (hẹn 7h05 chạy lúc ~12h, hẹn 15h05 chạy lúc ~23h35).
-- pg_cron của Supabase chạy đúng giờ → gọi GitHub API chạy workflow kéo tin (workflow_dispatch) kèm khoảng ngày.
-- Token GitHub để trong Supabase Vault (tên 'qc_gh_token'), đặt bằng script riêng — KHÔNG ghi trong file này.
-- Workflow hiện vẫn là job cũ bên mkt-sale-app; khi chép job sang repo qc-cskh thì đổi 2 hằng số bên dưới.
-- Monsieur Claude

create extension if not exists pg_net;
create extension if not exists pg_cron;

create or replace function public.qc_keo_tin(p_tu date, p_den date) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_token text;
  v_id bigint;
  c_repo constant text := 'hh-vibecode/mkt-sale-app';
  c_wf   constant text := 'sync-sale-review.yml';
begin
  select decrypted_secret into v_token from vault.decrypted_secrets where name = 'qc_gh_token';
  if v_token is null then raise exception 'Thiếu secret qc_gh_token trong Vault'; end if;
  select net.http_post(
    url := format('https://api.github.com/repos/%s/actions/workflows/%s/dispatches', c_repo, c_wf),
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_token, 'Accept', 'application/vnd.github+json',
                                  'User-Agent', 'qc-cskh', 'Content-Type', 'application/json'),
    body := jsonb_build_object('ref', 'main', 'inputs', jsonb_build_object('from', p_tu::text, 'to', p_den::text))
  ) into v_id;
  return v_id;
end $$;
revoke execute on function public.qc_keo_tin(date, date) from public, anon, authenticated;

-- 6h00 VN (23:00 UTC hôm trước): kéo trọn ngày hôm qua.  18h00 VN (11:00 UTC): kéo tin hôm nay tới lúc đó.
select cron.unschedule(jobid) from cron.job where jobname in ('qc-keo-6h', 'qc-keo-18h');
select cron.schedule('qc-keo-6h',  '0 23 * * *',
  $$select public.qc_keo_tin((now() at time zone 'Asia/Ho_Chi_Minh')::date - 1, (now() at time zone 'Asia/Ho_Chi_Minh')::date - 1)$$);
select cron.schedule('qc-keo-18h', '0 11 * * *',
  $$select public.qc_keo_tin((now() at time zone 'Asia/Ho_Chi_Minh')::date, (now() at time zone 'Asia/Ho_Chi_Minh')::date)$$);

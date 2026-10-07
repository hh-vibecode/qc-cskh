-- THỜI GIAN PHẢN HỒI (anh Hải 7/10/2026: "bổ sung 1 hàng tỉ lệ đúng giờ của thương hiệu / Sale, có cả thời gian phản hồi trung bình").
-- Tính từ full_thread: mỗi lượt khách (dòng "Khách:" đầu tiên sau tin Sale / Bot) → tin "Sale" đầu tiên sau đó (Bot không tính).
-- tg_phan_hoi_tb = trung bình (phút) các lượt CÓ Sale trả lời; tg_phan_hoi_max = lượt chậm nhất. Lượt chưa ai trả lời không tính
-- (đã là miss). Trigger chạy mỗi lần full_thread đổi → job kéo tin / soát miss / chấm không phải sửa. Monsieur Claude
alter table public.sale_response_review add column if not exists tg_phan_hoi_tb int, add column if not exists tg_phan_hoi_max int,
  add column if not exists tg_ngoai_gio int;   -- 7/10: số lượt khách nhắn ngoài giờ làm (8h–17h30) bị trả lời sau > 60 phút → thẻ Ngoài giờ làm

-- Phút LÀM VIỆC giữa 2 mốc giờ (giờ VIỆT NAM như trong thread — từ 7/10; trước đó thread ghi UTC, đã chuyển hết). Giờ làm việc 8h–17h30 giờ VN (anh Hải chốt 7/10). Đổi khung giờ: sửa 2 hằng số dưới.
create or replace function public.qc_phut_lam_viec(p_tu timestamp, p_den timestamp) returns int
language plpgsql immutable set search_path = public as $$
declare a timestamp := p_tu; b timestamp := p_den; d date; tong numeric := 0;   -- thread ghi GIỜ VIỆT NAM từ 7/10
  mo time := '08:00'; dong time := '17:30';   -- anh Hải chốt 7/10: giờ làm việc 8h–17h30
begin
  if b <= a then return 0; end if;
  d := a::date;
  while d <= b::date loop
    tong := tong + greatest(0, extract(epoch from least(b, d + dong) - greatest(a, d + mo)) / 60);
    d := d + 1;
  end loop;
  return round(tong)::int;
end $$;

-- Hàm tính dùng chung (trigger + tính lại hàng loạt). Không tính là Sale trả lời: dòng 'Bot', và 'Sale: (gửi ảnh/tệp)' KHÔNG tên người gửi
-- (ảnh page tự gửi khi khách bấm quảng cáo — 7/10 thấy ca Hưng Trung bị tính 0 phút).
create or replace function public.qc_tinh_tg(p_thread text) returns int[]
language plpgsql immutable set search_path = public as $$
declare l text; ts timestamp; ai text; cho timestamp := null; tong int := 0; n int := 0; mx int := null; d int; ng int := 0;
begin
  for l in select unnest(string_to_array(coalesce(p_thread, ''), E'\n')) loop
    ts := to_timestamp(substring(l from '^\[(\d{4}-\d\d-\d\d \d\d:\d\d)\]'), 'YYYY-MM-DD HH24:MI');
    if ts is null then continue; end if;
    ai := case when l ~ '^\[[^]]*\] Khách:' then 'khach'
               when l ~ '^\[[^]]*\] Sale: \(gửi ảnh/tệp\)\s*$' then 'bot'
               when l ~ '^\[[^]]*\] Sale' then 'sale' else 'bot' end;
    if ai = 'khach' then
      -- chỉ đo lượt khách từ 01/10/2026 (anh chốt làm chuẩn từ T10): tin khách 15/9 + Sale chủ động chào 7/10 không phải "trả lời chậm 3 tuần"
      if cho is null and ts >= timestamp '2026-10-01 00:00' then cho := ts; end if;
    elsif ai = 'sale' and cho is not null then
      -- anh Hải 7/10: khách nhắn NGOÀI giờ làm (trước 8h / từ 17h30) mà trả lời chậm → thẻ "Ngoài giờ làm", KHÔNG tính muộn,
      -- không vào trung bình / đúng giờ. Chỉ lượt khách nhắn TRONG giờ làm mới đo phút làm việc.
      -- Sửa lại 7/10 theo anh: khách nhắn ngoài giờ thì tính chờ TỪ 8h (lúc vào làm) — 20h tối, trả lời 9h sáng = chậm 1 giờ;
      -- 7h55, trả lời 11h07 = chậm 3 giờ 7 phút. Mọi lượt đều đo phút làm việc; thẻ ngoài giờ chỉ để biết khách nhắn ngoài giờ.
      if (cho::time < time '08:00' or cho::time >= time '17:30') and extract(epoch from ts - cho) / 60 > 60 then ng := ng + 1; end if;
      d := qc_phut_lam_viec(cho, ts);
      tong := tong + d; n := n + 1; mx := greatest(coalesce(mx, 0), d);
      cho := null;
    end if;
  end loop;
  return array[case when n > 0 then round(tong::numeric / n)::int end, mx, ng];
end $$;

create or replace function public.qc_tinh_phan_hoi() returns trigger
language plpgsql security definer set search_path = public, extensions as $$
declare a int[];
begin
  if tg_op = 'UPDATE' and new.full_thread is not distinct from old.full_thread then return new; end if;
  a := qc_tinh_tg(new.full_thread);
  new.tg_phan_hoi_tb := a[1]; new.tg_phan_hoi_max := a[2]; new.tg_ngoai_gio := a[3];
  return new;
end $$;
revoke execute on function public.qc_tinh_phan_hoi() from public, anon, authenticated;

drop trigger if exists qc_phan_hoi on public.sale_response_review;
create trigger qc_phan_hoi before insert or update on public.sale_response_review
  for each row execute function public.qc_tinh_phan_hoi();

-- Trang đọc thêm 2 cột
create or replace function public.qc_ds_cham(p_ma text, p_tu date default null, p_den date default null) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan(p_ma);
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.conv_date desc, x.id)
    from (select id, conv_date, conv_at, page_name, conv_id, customer_name, phone, sale_name,
                 customer_ask, sale_reply, verdict, issue, suggestion, severity, source_faq,
                 reviewed_at, pancake_url, cham_boi, page_id, sai_quy_trinh, tg_phan_hoi_tb, tg_phan_hoi_max, tg_ngoai_gio
          from sale_response_review
          where conv_id not like 'pzl\_g\_%' and verdict <> 'khong_lien_quan'
            and (p_tu is null or conv_date >= p_tu) and (p_den is null or conv_date <= p_den)) x), '[]'::jsonb);
end $$;

-- Chuyển thread cũ (ghi UTC) sang GIỜ VIỆT NAM — chạy 1 lần 7/10 (dòng đã chuyển đánh dấu bằng việc giờ khớp conv_at giờ VN).
create or replace function public.qc_thread_sang_vn(p text) returns text
language plpgsql immutable set search_path = public as $$
declare l text; ts timestamp; ra text[] := '{}';
begin
  for l in select unnest(string_to_array(coalesce(p, ''), E'\n')) loop
    ts := to_timestamp(substring(l from '^\[(\d{4}-\d\d-\d\d \d\d:\d\d)\]'), 'YYYY-MM-DD HH24:MI');
    ra := ra || case when ts is null then l else '[' || to_char(ts + interval '7 hours', 'YYYY-MM-DD HH24:MI') || ']' || substring(l from 19) end;
  end loop;
  return array_to_string(ra, E'\n');
end $$;
revoke execute on function public.qc_thread_sang_vn(text) from public, anon, authenticated;

-- GẮN QUẢNG CÁO (Ad ID Meta) CHO TỪNG HỘI THOẠI PANCAKE — app MKT nhờ, anh Hải duyệt 27/11/2026.
-- Luật anh chốt: mỗi hội thoại lấy Ad ID của QUẢNG CÁO GẦN NHẤT khách nhắn đến từ đó (hoặc quảng cáo xuất hiện trong đoạn chat);
-- nhiều quảng cáo thì lấy cái gần nhất nhưng vẫn ghi lại danh sách tất cả. Không có dấu vết ads vẫn để 1 dòng (ad_id rỗng).
--
-- Nguồn (đọc từ /pages/{page}/conversations/{conv}/messages của Pancake — cùng lời gọi job kéo tin đang dùng, không tốn thêm):
--   ad_clicks      : lịch sử mọi lần khách bấm quảng cáo vào hội thoại (ad_id, post_id, giờ) — Pancake giữ lùi tới 3/2026
--   referral       : activities nguồn ADS (OPEN_THREAD — khách mở hội thoại từ quảng cáo, có ad_title)
--   the_quang_cao  : thẻ quảng cáo trong đoạn chat (tin id "ad-…", attachments[].ad_id)
--   Cùng 1 lần bấm thường hiện ở cả 3 nguồn (lệch vài giây) → gộp 1 mục khi cùng ad_id và cách nhau < 5 phút.
-- TikTok: Pancake trả ad_clicks = null → không có dấu vết. Bình luận: chỉ có post_id bài viết (app MKT tự tra post → ad,
-- hoặc dùng view qc_ads_bai_viet: các ad_id đã thấy dùng post đó trong ad_clicks của hội thoại khác).
--
-- Bảng thô qc_ads_hoi_thoai (QC ghi qua RPC qc_ghi_ads, GỘP với lịch sử đã lưu — không đè mất quảng cáo cũ) →
-- view qc_hoi_thoai_ads (app MKT chỉ ĐỌC). Đổi cột view: chỉ THÊM.
-- Chạy lại supabase-gioi-han-qc.sql sau file này. Monsieur Claude

create table if not exists public.qc_ads_hoi_thoai (
  conv_id       text primary key,              -- id hội thoại Pancake
  page_id       text not null,
  page_name     text,
  kenh          text,                          -- facebook / tiktok / zalo
  loai          text,                          -- inbox / comment
  khach_id      text,                          -- customers[0].id của Pancake (cùng khach_id trong sale_response_review)
  ten_khach     text,
  sdt           text,                          -- recent_phone_numbers[0]
  post_id       text,                          -- bài viết của hội thoại BÌNH LUẬN
  ads           jsonb not null default '[]',   -- [{ad_id, luc, post_id, nguon:[…], tieu_de, custom_tag}] mới nhất trước
  ad_id         text,                          -- quảng cáo GẦN NHẤT (trigger tự tính từ ads)
  ad_luc        timestamptz,
  nguon_ad      text,
  ad_post_id    text,
  ad_tieu_de    text,
  tin_dau_luc   timestamptz,                   -- lúc hội thoại tạo trên Pancake
  tin_cuoi_luc  timestamptz,                   -- tin mới nhất đã đọc
  khach_cuoi_luc timestamptz,                  -- last_customer_interactive_at
  tao_luc       timestamptz not null default now(),
  cap_nhat_luc  timestamptz not null default now()
);
alter table public.qc_ads_hoi_thoai enable row level security;
drop policy if exists qc_ads_hoi_thoai_doc on public.qc_ads_hoi_thoai;
create policy qc_ads_hoi_thoai_doc on public.qc_ads_hoi_thoai for select to authenticated using (true);
revoke all on public.qc_ads_hoi_thoai from anon;
grant select on public.qc_ads_hoi_thoai to authenticated;
create index if not exists qc_ads_hoi_thoai_ad_idx on public.qc_ads_hoi_thoai (ad_id) where ad_id is not null;
create index if not exists qc_ads_hoi_thoai_khach_idx on public.qc_ads_hoi_thoai (page_id, khach_id);
create index if not exists qc_ads_hoi_thoai_tin_idx on public.qc_ads_hoi_thoai (tin_cuoi_luc desc);
create index if not exists qc_ads_hoi_thoai_post_idx on public.qc_ads_hoi_thoai (post_id) where post_id is not null;
create index if not exists qc_ads_hoi_thoai_ads_gin on public.qc_ads_hoi_thoai using gin (ads jsonb_path_ops);   -- tra bài viết → quảng cáo
-- view nối verdict theo conv_id (bảng QC, chưa có chỉ mục conv_id)
create index if not exists qc_srr_conv_idx on public.sale_response_review (conv_id);

-- Gộp 2 danh sách quảng cáo: cùng ad_id cách nhau < 5 phút = 1 lần bấm (gộp nguồn); xếp mới nhất trước.
create or replace function public.qc_gop_ads(a jsonb, b jsonb) returns jsonb
language plpgsql immutable set search_path = public as $$
declare kq jsonb := coalesce(a, '[]'::jsonb); x jsonb; y jsonb; i int; trung boolean;
begin
  for x in select e from jsonb_array_elements(coalesce(b, '[]'::jsonb)) e where e->>'ad_id' is not null and e->>'luc' is not null loop
    trung := false;
    for i in 0 .. jsonb_array_length(kq) - 1 loop
      y := kq->i;
      if y->>'ad_id' = x->>'ad_id'
         and abs(extract(epoch from ((y->>'luc')::timestamptz - (x->>'luc')::timestamptz))) < 300 then
        kq := jsonb_set(kq, array[i::text], y || jsonb_strip_nulls(jsonb_build_object(
          'nguon', (select jsonb_agg(distinct v order by v) from jsonb_array_elements_text(coalesce(y->'nguon', '[]') || coalesce(x->'nguon', '[]')) v),
          'post_id', coalesce(y->'post_id', x->'post_id'), 'tieu_de', coalesce(y->'tieu_de', x->'tieu_de'),
          'custom_tag', coalesce(y->'custom_tag', x->'custom_tag'))));
        trung := true; exit;
      end if;
    end loop;
    if not trung then kq := kq || jsonb_build_array(x); end if;
  end loop;
  return (select coalesce(jsonb_agg(e order by (e->>'luc')::timestamptz desc), '[]'::jsonb) from jsonb_array_elements(kq) e);
end $$;

create or replace function public.qc_ads_gan_nhat() returns trigger
language plpgsql set search_path = public as $$
begin
  new.ad_id      := new.ads->0->>'ad_id';
  new.ad_luc     := (new.ads->0->>'luc')::timestamptz;
  new.nguon_ad   := (select string_agg(v, '+' order by v) from jsonb_array_elements_text(coalesce(new.ads->0->'nguon', '[]')) v);
  new.ad_post_id := new.ads->0->>'post_id';
  new.ad_tieu_de := new.ads->0->>'tieu_de';
  return new;
end $$;
drop trigger if exists qc_ads_gan_nhat on public.qc_ads_hoi_thoai;
create trigger qc_ads_gan_nhat before insert or update of ads on public.qc_ads_hoi_thoai
  for each row execute function public.qc_ads_gan_nhat();

-- Ghi 1 lô (job kéo tin mỗi giờ + tools/keo-ads.js lấy bù). Có rồi thì GỘP ads, giữ thông tin cũ khi lô mới để trống.
create or replace function public.qc_ghi_ads(p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into qc_ads_hoi_thoai as t (conv_id, page_id, page_name, kenh, loai, khach_id, ten_khach, sdt, post_id, ads,
                                     tin_dau_luc, tin_cuoi_luc, khach_cuoi_luc)
  select distinct on (x.conv_id)   -- chốt chặn: lô trùng conv_id (Pancake trả 1 hội thoại 2 lần khi lật trang) thì giữ dòng tin mới nhất
         x.conv_id, x.page_id, x.page_name, x.kenh, x.loai, x.khach_id, x.ten_khach, x.sdt, x.post_id,
         public.qc_gop_ads('[]'::jsonb, coalesce(x.ads, '[]'::jsonb)), x.tin_dau_luc, x.tin_cuoi_luc, x.khach_cuoi_luc
  from jsonb_to_recordset(p_rows) as x(conv_id text, page_id text, page_name text, kenh text, loai text, khach_id text,
       ten_khach text, sdt text, post_id text, ads jsonb, tin_dau_luc timestamptz, tin_cuoi_luc timestamptz, khach_cuoi_luc timestamptz)
  where x.conv_id is not null and x.page_id is not null
  order by x.conv_id, x.tin_cuoi_luc desc nulls last
  on conflict (conv_id) do update set
    page_name = coalesce(excluded.page_name, t.page_name), kenh = coalesce(excluded.kenh, t.kenh), loai = coalesce(excluded.loai, t.loai),
    khach_id = coalesce(excluded.khach_id, t.khach_id), ten_khach = coalesce(nullif(excluded.ten_khach, ''), t.ten_khach),
    sdt = coalesce(excluded.sdt, t.sdt), post_id = coalesce(excluded.post_id, t.post_id),
    ads = public.qc_gop_ads(t.ads, excluded.ads),
    tin_dau_luc = least(t.tin_dau_luc, excluded.tin_dau_luc), tin_cuoi_luc = greatest(t.tin_cuoi_luc, excluded.tin_cuoi_luc),
    khach_cuoi_luc = greatest(t.khach_cuoi_luc, excluded.khach_cuoi_luc), cap_nhat_luc = now();
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function public.qc_ghi_ads(jsonb) from public, anon, authenticated;

-- App MKT đọc: 1 dòng = 1 hội thoại. qua_loc = hội thoại đã qua bộ lọc QC (có lượt khách không phải khấn / spam / nội bộ…);
-- theo luật anh (28/10) số liệu "data" nên đếm qua_loc = true. verdict null = hội thoại chưa có dòng chấm QC.
create or replace view public.qc_hoi_thoai_ads with (security_invoker = true) as
select a.page_id, a.page_name, a.kenh, a.conv_id as pancake_conversation_id, a.loai, a.khach_id, a.ten_khach, a.sdt,
       a.ad_id, a.ad_luc, a.nguon_ad, a.ad_post_id, a.ad_tieu_de,
       a.ads as ad_ids_tat_ca, jsonb_array_length(a.ads) as so_lan_ads,
       a.post_id,                                       -- bài viết của hội thoại bình luận
       a.tin_dau_luc, a.tin_cuoi_luc, a.khach_cuoi_luc, a.cap_nhat_luc,
       s.verdict,
       exists (select 1 from sale_response_review r where r.conv_id = a.conv_id and r.verdict <> 'khong_lien_quan') as qua_loc,
       -- BÌNH LUẬN (không có ad_id gốc): quảng cáo SUY TỪ BÀI VIẾT — ad_id đã thấy dùng post đó trong ad_clicks của hội thoại khác
       -- (mới nhất). so_ad_theo_bai > 1 = 1 bài chạy nhiều quảng cáo, chỉ là ước đoán. Đối chiếu 27/11: ca bình luận có đơn mang ad_id khớp.
       b.ad_id as ad_id_theo_bai, b.so_ad as so_ad_theo_bai
from qc_ads_hoi_thoai a
left join lateral (select r.verdict from sale_response_review r where r.conv_id = a.conv_id order by r.conv_at desc nulls last limit 1) s on true
left join lateral (
  select (array_agg(e->>'ad_id' order by (e->>'luc')::timestamptz desc))[1] as ad_id, count(distinct e->>'ad_id') as so_ad
  from qc_ads_hoi_thoai x, jsonb_array_elements(x.ads) e
  where a.ad_id is null and a.post_id is not null
    and x.ads @> jsonb_build_array(jsonb_build_object('post_id', a.post_id)) and e->>'post_id' = a.post_id
) b on true;
grant select on public.qc_hoi_thoai_ads to authenticated;

-- Bài viết ↔ quảng cáo đã thấy trong ad_clicks (để tra bình luận chỉ có post_id). 1 bài có thể chạy nhiều quảng cáo.
create or replace view public.qc_ads_bai_viet with (security_invoker = true) as
select e->>'post_id' as post_id, e->>'ad_id' as ad_id, count(distinct a.conv_id) as so_hoi_thoai,
       min((e->>'luc')::timestamptz) as lan_dau, max((e->>'luc')::timestamptz) as lan_cuoi
from qc_ads_hoi_thoai a, jsonb_array_elements(a.ads) e
where e->>'post_id' is not null
group by 1, 2;
grant select on public.qc_ads_bai_viet to authenticated;

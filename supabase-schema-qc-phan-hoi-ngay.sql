-- PHẢN HỒI KHÁCH THEO NGÀY — MỌI KÊNH (Facebook + Zalo + TikTok) CHO APP MKT/SALE (anh Hải 13/11/2026: "bổ cả tin nhắn FB vào
-- cho bên app MKT, thêm 1 cột phản hồi FB, quy tắc như Zalo; đưa số liệu QC đã xử lý sang: bao nhiêu tin phản hồi, bao nhiêu
-- tin trả lời muộn"). App MKT CHỈ ĐỌC. Đổi cột về sau: CHỈ THÊM, không đổi tên / xoá. View Zalo cũ qc_zalo_phan_hoi_ngay giữ nguyên.
-- 1 dòng = 1 khách × 1 Sale × 1 ngày (giờ VN) mà Sale CÓ trả lời khách (gộp đúng từ 20/11 — xem CHỐNG TRÙNG cuối view), từ 01/10/2026. LỌC TRƯỚC: chỉ hội thoại đã qua bộ lọc
-- QC (bỏ khấn, rác, nội bộ / NCC, tin hệ thống), bỏ nhóm Zalo pzl_g_, bỏ tin Bot.
--   nen_tang      : facebook | zalo | tiktok — app MKT lấy cột "phản hồi FB" = nen_tang 'facebook'.
--   sale          : sale_nhan_su.ten (qua qc_sale_chuyen → qc_sale_ten). Facebook / TikTok: chỉ tin "Sale (Tên)"; tin "Sale:" không
--                   tên là tự động → bỏ. Zalo: tin không tên = chủ Zalo trả lời. Tài khoản chung (PANCAKE THT HOLDING) → mặc định kênh.
--   khach_nhan    : khách có nhắn trong ngày (false = Sale nhắn chủ động).
--   phut_cho      : phút LÀM VIỆC (8h–17h30, qc_phut_lam_viec) từ tin khách ĐẦU lượt cần trả lời trong ngày tới tin đầu tiên của
--                   Sale này sau đó. Khách nhắn ngoài giờ tính từ 8h. null khi khách không nhắn trong ngày.
--   tra_loi_muon  : phut_cho > 60 (chuẩn "đúng giờ" của trang QC, DUNG_GIO = 60).
--   la_binh_luan  : dòng là bình luận Facebook (phần nhắn riêng nếu có đã nối vào).
--   la_miss       : (thêm 13/11) true = dòng MISS (khách hỏi, chưa Sale nào trả lời) — xem quy tắc ở phần union bên dưới.
-- Monsieur Claude
create or replace view public.qc_phan_hoi_ngay with (security_invoker = true) as
with goc as (
with hoi as (
  select s.id, s.page_id, s.page_name, s.conv_id, s.customer_name, s.phone,
         coalesce(s.khach_id, nullif(regexp_replace(s.conv_id, '^pzl_u_\d+_', ''), s.conv_id)) as khach_id, s.full_thread,
         case when s.page_id like 'pzl\_%' then 'zalo' when s.page_id like 'ttm\_%' then 'tiktok' else 'facebook' end as nen_tang,
         (s.page_id not like 'pzl\_%' and s.page_id not like 'ttm\_%' and s.conv_id not like s.page_id || '\_%') as la_binh_luan
  from public.sale_response_review s
  where s.conv_date >= '2026-10-01' and s.conv_id not like 'pzl\_g\_%'
    and s.verdict <> 'khong_lien_quan' and not coalesce(s.noi_bo, false)
),
dong as (   -- [YYYY-MM-DD HH:MM] Ai: nội dung (giờ VN)
  select h.id, h.nen_tang, m[1]::date as ngay, (m[1] || ' ' || m[2])::timestamp as luc, m[3] as ai, lower(trim(m[4])) as nd
  from hoi h, regexp_split_to_table(h.full_thread, E'\n') l,
       regexp_match(l, '^\[(\d{4}-\d\d-\d\d) (\d\d:\d\d)\] ([^:]+): ?(.*)$') m
  where m is not null and m[1] >= '2026-10-01'
),
tin as (
  select id, ngay, luc, ai = 'Khách' as la_khach,
         case when ai = 'Khách' then null
              when ai ~ '^Sale \(.+\)$' and substring(ai from '^Sale \((.+)\)$') !~* '^(pancake tht holding|sales? admin)$'
                then substring(ai from '^Sale \((.+)\)$')
              else '' end as sk,                       -- '' = chủ kênh (Zalo tin không tên / tài khoản chung)
         -- tin "Khách" cần trả lời: bỏ tin máy (sinh nhật, kết bạn) + xã giao / ảnh / sticker (không cần trả lời)
         ai = 'Khách' and nd !~ '(sinh nhật của .* hãy gửi lời chúc|đã đồng ý kết bạn|lời mời kết bạn|vừa kết bạn với)'
           and not (nd ~ '^(ok\w*|oke\w*|vâng\w*|vg|dạ\w*|ừ\w*|uh\w*|cảm ơn|cám ơn|camon|thanks?|thank you|tks|\(gửi ảnh/tệp\)|\(sticker\))([^a-z0-9à-ỹ]|$)' and length(nd) <= 40) as can_tl,
         ai = 'Khách' and nd !~ '(sinh nhật của .* hãy gửi lời chúc|đã đồng ý kết bạn|lời mời kết bạn|vừa kết bạn với)' as khach_that
  from dong
  where ai = 'Khách'
     or ai ~ '^Sale \(.+\)$'
     or (ai = 'Sale' and nen_tang = 'zalo')             -- FB / TikTok: "Sale:" không tên là tin tự động → bỏ
),
sale_ngay as (   -- Sale nhắn khách trong ngày + tin đầu tiên của Sale đó trong ngày
  select t.id, t.ngay, t.sk, min(t.luc) as sale_dau
  from tin t where not t.la_khach group by t.id, t.ngay, t.sk
),
khach_ngay as (   -- khách có nhắn trong ngày; tin cần trả lời ĐẦU TIÊN của ngày
  select id, ngay, bool_or(khach_that) as khach_nhan, min(luc) filter (where can_tl) as kh_dau
  from tin where la_khach group by id, ngay
)
select sn.ngay, h.nen_tang, h.page_name as kenh,
       case when sn.sk = '' then t2.ten_nhan_su else t1.ten_nhan_su end as sale,
       nullif(sn.sk_goc, '') as sale_pancake,
       h.conv_id, h.khach_id, h.customer_name as ten_khach, h.phone as sdt,
       coalesce(kn.khach_nhan, false) as khach_nhan,
       pc.phut as phut_cho,
       pc.phut > 60 as tra_loi_muon,
       h.la_binh_luan,
       false as la_miss
from (   -- người đã nghỉ → từ mốc ngày tính cho người nhận (qc_sale_chuyen); sale_pancake giữ tên gốc
  select s0.id, s0.ngay, s0.sale_dau, s0.sk as sk_goc,
         coalesce((select c.ten_moi from public.qc_sale_chuyen c where c.ten_cu = s0.sk and s0.ngay >= c.tu_ngay order by c.tu_ngay desc limit 1), s0.sk) as sk
  from sale_ngay s0
) sn
join hoi h on h.id = sn.id
left join khach_ngay kn on kn.id = sn.id and kn.ngay = sn.ngay
left join lateral (   -- phút làm việc từ tin khách đầu lượt cần trả lời tới tin đầu tiên của Sale này sau đó
  select public.qc_phut_lam_viec(kn.kh_dau, (select min(x.luc) from tin x where x.id = sn.id and not x.la_khach and x.sk = sn.sk_goc and x.luc >= kn.kh_dau)) as phut
  where kn.kh_dau is not null
) pc on true
left join public.qc_sale_ten t1 on t1.ten_pancake = sn.sk
left join public.qc_sale_ten t2 on t2.ten_pancake = public.qc_sale_mac_dinh(h.page_id, h.page_name)

union all

-- TIN MISS (anh Hải 13/11: "cuối ngày Sale phải chụp báo cáo, nên tin miss để hết hôm nay mới update vào báo cáo hôm trước cho chuẩn,
-- đỡ cãi"). Miss ngày D (ngày khách hỏi) chỉ hiện từ ngày D+1 (giờ VN) VÀ khi khách đã chờ > 60 phút LÀM VIỆC mà chưa Sale nào
-- trả lời (tin tối hôm trước → tính từ 8h, khoảng 9h mới hiện). Sale trả lời sau đó → dòng miss tự mất, thay bằng dòng
-- tra_loi_muon ở ngày Sale trả lời. Miss theo quy tắc QC: verdict khong_tra_loi / chi_bot SAU soát miss mỗi giờ với Pancake
-- (đã loại: trả lời muộn, chỉ cảm ơn / ảnh sau khi Sale đáp, lỗi nền tảng #551, nhắn riêng bình luận, gọi điện có thời lượng).
-- Sale = chủ kênh mặc định (qc_sale_mac_dinh → qc_sale_ten); phut_cho = phút làm việc khách đã chờ tới lúc đọc view.
select (s.conv_at at time zone 'Asia/Ho_Chi_Minh')::date as ngay,
       case when s.page_id like 'pzl\_%' then 'zalo' when s.page_id like 'ttm\_%' then 'tiktok' else 'facebook' end as nen_tang,
       s.page_name as kenh,
       tm.ten_nhan_su as sale,
       null::text as sale_pancake,
       s.conv_id,
       coalesce(s.khach_id, nullif(regexp_replace(s.conv_id, '^pzl_u_\d+_', ''), s.conv_id)) as khach_id,
       s.customer_name as ten_khach, s.phone as sdt,
       true as khach_nhan,
       public.qc_phut_lam_viec((s.conv_at at time zone 'Asia/Ho_Chi_Minh'), (now() at time zone 'Asia/Ho_Chi_Minh')) as phut_cho,
       null::boolean as tra_loi_muon,
       (s.page_id not like 'pzl\_%' and s.page_id not like 'ttm\_%' and s.conv_id not like s.page_id || '\_%') as la_binh_luan,
       true as la_miss
from public.sale_response_review s
left join public.qc_sale_ten tm on tm.ten_pancake = coalesce(
       (select c.ten_moi from public.qc_sale_chuyen c where c.ten_cu = public.qc_sale_mac_dinh(s.page_id, s.page_name)
          and (s.conv_at at time zone 'Asia/Ho_Chi_Minh')::date >= c.tu_ngay order by c.tu_ngay desc limit 1),
       public.qc_sale_mac_dinh(s.page_id, s.page_name))
where s.verdict in ('khong_tra_loi', 'chi_bot') and s.conv_date >= '2026-10-01' and s.conv_id not like 'pzl\_g\_%'
  and not coalesce(s.noi_bo, false) and s.conv_at is not null
  and (s.conv_at at time zone 'Asia/Ho_Chi_Minh')::date < (now() at time zone 'Asia/Ho_Chi_Minh')::date
  and public.qc_phut_lam_viec((s.conv_at at time zone 'Asia/Ho_Chi_Minh'), (now() at time zone 'Asia/Ho_Chi_Minh')) > 60
),
-- ── CHỐNG TRÙNG (20/11, anh Hải "để ý k bị dup data"): trước đây 1 dòng = 1 hội thoại × 1 TÊN PANCAKE × 1 ngày → cùng 1 khách nhiều dòng
-- (Zalo tin có tên + tin không tên của cùng 1 Sale; bình luận + tin nhắn riêng; nhiều bình luận): 708 khách-ngày thừa 818 dòng.
-- Nay 1 dòng = 1 KHÁCH (kênh + khach_id) × 1 SALE (tên nhân sự; chưa map thì tên Pancake) × 1 ngày. conv_id ưu tiên tin nhắn riêng;
-- phut_cho = lượt trả lời nhanh nhất của Sale đó với khách trong ngày. Dòng MISS bỏ nếu cùng ngày khách đã được Sale trả lời ở luồng khác.
-- goc chỉ tham chiếu 1 lần (bản đầu tham chiếu 2 lần → 30 giây, vượt giới hạn 8 giây của app MKT — đã trả lại bản cũ 20/11).
a as (
  select ngay, nen_tang, kenh, coalesce(khach_id, conv_id) as khach_key, coalesce(sale, 'pk:' || sale_pancake, '') as sale_key, la_miss,
         (array_agg(sale) filter (where sale is not null))[1] as sale,
         (array_agg(sale_pancake order by sale_pancake nulls last))[1] as sale_pancake,
         (array_agg(conv_id order by la_binh_luan, conv_id))[1] as conv_id,
         (array_agg(khach_id) filter (where khach_id is not null))[1] as khach_id,
         (array_agg(ten_khach order by la_binh_luan))[1] as ten_khach,
         (array_agg(sdt) filter (where sdt is not null))[1] as sdt,
         bool_or(khach_nhan) as khach_nhan,
         min(phut_cho) as phut_min, max(phut_cho) as phut_max,
         bool_and(la_binh_luan) as la_binh_luan
  from goc
  group by ngay, nen_tang, kenh, coalesce(khach_id, conv_id), coalesce(sale, 'pk:' || sale_pancake, ''), la_miss
),
b as (
  select a.*, bool_or(not a.la_miss) over (partition by a.ngay, a.nen_tang, a.kenh, a.khach_key) as co_tra_loi
  from a
)
select ngay, nen_tang, kenh, sale, case when la_miss then null::text else sale_pancake end as sale_pancake,
       conv_id, khach_id, ten_khach, sdt, khach_nhan,
       case when la_miss then phut_max else phut_min end as phut_cho,
       case when la_miss then null::boolean else phut_min > 60 end as tra_loi_muon,
       la_binh_luan, la_miss
from b
where not (la_miss and co_tra_loi);

grant select on public.qc_phan_hoi_ngay to authenticated;
revoke all on public.qc_phan_hoi_ngay from anon;

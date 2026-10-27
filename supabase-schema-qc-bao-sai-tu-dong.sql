-- TỰ XỬ LÝ BÁO SAI CUỐI NGÀY (anh Hải 15/10/2026: "làm tool cuối ngày rà lỗi báo sai và clear luôn, t đỡ phải báo m").
-- Lịch chấm cloud (routine/cham-cloud.md) từ 17h giờ VN: đọc báo sai đang mở (kèm ảnh Sale / anh gửi + cả hội thoại),
-- xét theo luật chấm, rồi: sửa kết quả dòng chấm + đóng báo · giữ nguyên + đóng (ghi vì sao) · để mở "CHỜ ANH:" khi cần
-- anh quyết nghiệp vụ. Bài học rút ra ghi vào luat_de_xuat → phiên Claude sau chép vào 2 file luật (routine KHÔNG sửa repo),
-- trong lúc chờ thì lượt chấm đọc luat_cho_ghi để áp ngay. Monsieur Claude
-- Tên hàm KHÁC qc_ds_bao_sai / qc_xu_ly_bao_sai của trang (15/10 lỡ ghi đè qc_ds_bao_sai của trang vài phút, đã khôi phục).
alter table public.sale_review_report add column if not exists luat_de_xuat text;
alter table public.sale_review_report add column if not exists luat_da_ghi boolean not null default false;

create or replace function public.qc_lo_bao_sai(p_ma text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform qc_chan_cham(p_ma);
  return jsonb_build_object(
    'bao', coalesce((select jsonb_agg(jsonb_build_object(
        'bao_id', b.id, 'nguoi_bao', b.reporter, 'ghi_chu_bao', b.note, 'luc_bao', b.created_at, 'verdict_luc_bao', b.verdict_old,
        'anh', coalesce(to_jsonb(b.images), '[]'::jsonb),
        'dong', jsonb_build_object('id', s.id, 'page', s.page_name, 'khach', s.customer_name, 'sale', s.sale_name, 'conv_at', s.conv_at,
          'verdict', s.verdict, 'severity', s.severity, 'issue', s.issue, 'suggestion', s.suggestion, 'sai_quy_trinh', s.sai_quy_trinh,
          'cham_boi', s.cham_boi, 'la_binh_luan', s.page_id is not null and s.conv_id not like s.page_id || '\_%' and s.conv_id not like 'pzl\_%',
          'thread', right(s.full_thread, 8000)),
        'dong_cung_khach', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'verdict', o.verdict, 'conv_at', o.conv_at, 'issue', o.issue)), '[]'::jsonb)
          from sale_response_review o where s.khach_id is not null and o.khach_id = s.khach_id and o.page_id = s.page_id and o.id <> s.id
            and o.conv_date >= current_date - 14))
        order by b.id)
      from sale_review_report b left join sale_response_review s on s.id = b.review_id
      where b.status = 'open' and coalesce(b.resolve_note, '') not like 'CHỜ ANH:%'), '[]'::jsonb),
    'luat_cho_ghi', coalesce((select jsonb_agg(jsonb_build_object('bao_id', id, 'luat', luat_de_xuat) order by id)
      from sale_review_report where coalesce(luat_de_xuat, '') <> '' and not luat_da_ghi), '[]'::jsonb));
end $$;

-- p_rows = [{bao_id, ket:'sua'|'giu'|'cho_anh', ghi_chu, luat_de_xuat?, verdict?, severity?, issue?, suggestion?, sai_quy_trinh?}]
--  sua     : ghi lại dòng chấm (verdict… như qc_ghi_cham, cham_boi='claude' để job kéo không đè) + đóng báo
--  giu     : kết quả cũ đúng → đóng báo, ghi_chu nói rõ vì sao giữ
--  cho_anh : cần anh quyết nghiệp vụ → báo vẫn MỞ, resolve_note = 'CHỜ ANH: …' (lượt sau không xét lại)
create or replace function public.qc_tu_xu_ly_bao_sai(p_ma text, p_rows jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare r jsonb; loi text[] := '{}'; n int := 0; rid bigint;
begin
  perform qc_chan_cham(p_ma);
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'p_rows phải là mảng'; end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    if coalesce(r->>'ket','') not in ('sua','giu','cho_anh') then loi := loi || format('báo #%s: ket "%s" không hợp lệ', r->>'bao_id', r->>'ket');
    elsif coalesce(trim(r->>'ghi_chu'),'') = '' then loi := loi || format('báo #%s: thiếu ghi_chu', r->>'bao_id');
    elsif not exists (select 1 from sale_review_report where id = (r->>'bao_id')::bigint and status = 'open') then loi := loi || format('báo #%s: không còn mở', r->>'bao_id');
    -- 27/10 anh Hải: "mấy cái chấm sai mà ngta feedback phải nhớ vào, không phải để ấy" → báo ĐÚNG (sửa) BẮT BUỘC kèm luật rút ra
    elsif r->>'ket' = 'sua' and length(coalesce(trim(r->>'luat_de_xuat'),'')) < 15 then
      loi := loi || format('báo #%s: sửa kết quả thì BẮT BUỘC có luat_de_xuat (1 câu luật chung để không chấm sai lại)', r->>'bao_id');
    elsif r->>'ket' = 'sua' and coalesce(r->>'verdict','') not in ('dung','thieu','sai','khong_lien_quan','khong_tra_loi','loi_nen_tang') then
      loi := loi || format('báo #%s: verdict "%s" không hợp lệ', r->>'bao_id', r->>'verdict');
    elsif r->>'ket' = 'sua' and r->>'verdict' in ('thieu','sai') and (coalesce(r->>'severity','') not in ('cao','trung','thap')
          or coalesce(r->>'issue','') = '' or coalesce(r->>'suggestion','') = '') then
      loi := loi || format('báo #%s: %s phải có severity cao|trung|thap + issue + suggestion', r->>'bao_id', r->>'verdict');
    end if;
  end loop;
  if array_length(loi, 1) > 0 then return jsonb_build_object('ghi', 0, 'loi', to_jsonb(loi)); end if;
  for r in select * from jsonb_array_elements(p_rows) loop
    select review_id into rid from sale_review_report where id = (r->>'bao_id')::bigint;
    if r->>'ket' = 'sua' then
      update sale_response_review set verdict = r->>'verdict',
        severity = case when r->>'verdict' in ('thieu','sai') then r->>'severity' end,
        issue = nullif(trim(r->>'issue'), ''), suggestion = case when r->>'verdict' in ('thieu','sai') then r->>'suggestion' end,
        sai_quy_trinh = nullif(trim(r->>'sai_quy_trinh'), ''), cham_boi = 'claude', reviewed_at = now()
      where id = rid;
    end if;
    update sale_review_report set
      status = case when r->>'ket' = 'cho_anh' then 'open' else 'fixed' end,
      resolved_at = case when r->>'ket' = 'cho_anh' then null else now() end,
      resolved_by = case when r->>'ket' = 'cho_anh' then null else 'Tự xử lý cuối ngày (Monsieur Claude)' end,
      resolve_note = case when r->>'ket' = 'cho_anh' then 'CHỜ ANH: ' else '' end
        || case when r->>'ket' = 'giu' then 'Giữ nguyên: ' else '' end || trim(r->>'ghi_chu'),
      luat_de_xuat = coalesce(nullif(trim(r->>'luat_de_xuat'), ''), luat_de_xuat)
    where id = (r->>'bao_id')::bigint;
    n := n + 1;
  end loop;
  return jsonb_build_object('ghi', n, 'gui', jsonb_array_length(p_rows));
end $$;

revoke execute on function public.qc_lo_bao_sai(text), public.qc_tu_xu_ly_bao_sai(text, jsonb) from public;
grant execute on function public.qc_lo_bao_sai(text), public.qc_tu_xu_ly_bao_sai(text, jsonb) to anon, authenticated;

// Khoá của app QC — KHÔNG in giá trị, KHÔNG chép khoá vào repo.
// Thứ tự: biến môi trường (job GitHub Actions) → file riêng qc-keys.local.txt (máy anh Hải).
// Từ 29/9/2026 QC có secret key Supabase RIÊNG ('qc_cskh', thu hồi độc lập với app MKT/Sale); không còn đọc file khoá của mkt-sale-app.
// Monsieur Claude
const fs = require('fs');
const path = require('path');
const FILE = process.env.QC_KEY_FILE || path.join(__dirname, '..', 'qc-keys.local.txt');
const t = fs.existsSync(FILE) ? fs.readFileSync(FILE, 'utf8') : '';
const m = re => { const x = t.match(re); return x ? x[1] : null; };
const E = process.env;
module.exports = {
  qc: E.QC_SUPABASE_KEY || m(/QC_SUPABASE_KEY:\s*(\S+)/),                 // khoá ghi/đọc dữ liệu riêng của QC (PostgREST)
  pancake: E.PANCAKE_SESSION_TOKEN || m(/PANCAKE_SESSION_TOKEN:[^\n]*\n\s*(\S+)/),
  sbp: E.SUPABASE_MGMT_TOKEN || m(/SUPABASE_MGMT_TOKEN:\s*(\S+)/),        // chỉ dùng cho việc quản trị (SQL, schema, cron)
  gh: E.GH_TOKEN || m(/GITHUB_TOKEN:\s*(\S+)/),
  anon: E.SUPABASE_ANON_KEY || m(/ANON_KEY:\s*(\S+)/),
  url: 'https://bcrpxfvvjsjpvbksqzls.supabase.co',
  ref: 'bcrpxfvvjsjpvbksqzls',
};
if (require.main === module) {
  for (const [k, v] of Object.entries(module.exports)) console.log(k, v ? `ok (${v.length} ký tự)` : 'THIẾU');
}

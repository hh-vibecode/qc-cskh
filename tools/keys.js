// Đọc khoá từ file khoá dùng chung của mkt-sale-app — KHÔNG in giá trị, KHÔNG chép khoá vào repo.
// Monsieur Claude
const fs = require('fs');
const FILE = process.env.QC_KEY_FILE || 'C:/Users/HP/Desktop/mkt-sale-app/supabase-keys.local.txt';
const t = fs.readFileSync(FILE, 'utf8');
const m = re => { const x = t.match(re); return x ? x[1] : null; };
module.exports = {
  gh: m(/(ghp_[A-Za-z0-9]+)/),
  sbp: m(/(sbp_[A-Za-z0-9]+)/),
  service: m(/SERVICE_ROLE_KEY\s*[:=]\s*(\S+)/),
  anon: m(/ANON_KEY\s*[:=]\s*(\S+)/),
  pancake: m(/PANCAKE_SESSION_TOKEN[^\n]*\n\s*(eyJ\S+)/),
  url: 'https://bcrpxfvvjsjpvbksqzls.supabase.co',
  ref: 'bcrpxfvvjsjpvbksqzls',
};
if (require.main === module) {
  for (const [k, v] of Object.entries(module.exports)) console.log(k, v ? `ok (${v.length} ký tự)` : 'THIẾU');
}

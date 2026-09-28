// Chạy SQL trên Supabase dùng chung qua Management API.
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" tools/sql.js <file.sql | "câu SQL"> [--json]
// --json: in JSON thô (để script khác đọc); mặc định in bảng.
// Monsieur Claude
const fs = require('fs');
const K = require('./keys.js');
const arg = process.argv[2];
const asJson = process.argv.includes('--json');
if (!arg) { console.error('Thiếu câu SQL hoặc file .sql'); process.exit(1); }
const q = fs.existsSync(arg) ? fs.readFileSync(arg, 'utf8') : arg;
(async () => {
  const r = await fetch(`https://api.supabase.com/v1/projects/${K.ref}/database/query`, {
    method: 'POST', headers: { Authorization: 'Bearer ' + K.sbp, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: q }),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) { console.error('HTTP', r.status, JSON.stringify(j)); process.exit(1); }
  if (asJson) console.log(JSON.stringify(j));
  else if (Array.isArray(j) && j.length && typeof j[0] === 'object') console.table(j);
  else console.log(JSON.stringify(j, null, 1));
})();

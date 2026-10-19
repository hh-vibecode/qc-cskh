// Đóng dấu phiên bản app QC trước khi commit (anh Hải 19/10/2026: "set version ngày giờ update như 2 app khác" —
// giống app Kế toán: scripts/dong-dau.js). APP_SO = 1.<số lần index.html đã commit + 1> · APP_VERSION = giờ VIỆT NAM lúc chạy
// (phiên cloud chạy giờ UTC nên luôn cộng 7 tiếng, không dùng giờ máy). Hiện ở cuối menu trái: "Phiên bản v1.N · dd/mm hh:mm".
// Dùng: chạy 1 lần ngay trước `git add index.html` mỗi khi sửa index.html —
//   máy anh: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" C:/Users/HP/Desktop/qc-cskh/tools/dong-dau.js
//   cloud:   node tools/dong-dau.js
// Monsieur Claude
const fs = require('fs'), path = require('path'), { execSync } = require('child_process');
const goc = path.join(__dirname, '..'), f = path.join(goc, 'index.html');
const n = Number(execSync('git rev-list --count HEAD -- index.html', { cwd: goc }).toString().trim()) + 1;
const vn = new Date(Date.now() + 7 * 36e5).toISOString();   // giờ Việt Nam
const gio = `${vn.slice(8, 10)}/${vn.slice(5, 7)}/${vn.slice(0, 4)} ${vn.slice(11, 16)}`;
let s = fs.readFileSync(f, 'utf8');
if (!/^const APP_VERSION='[^']*';/m.test(s) || !/^const APP_SO='[^']*';/m.test(s)) throw new Error('Không thấy APP_VERSION / APP_SO trong index.html');
s = s.replace(/^const APP_VERSION='[^']*';/m, `const APP_VERSION='${gio}';`).replace(/^const APP_SO='[^']*';/m, `const APP_SO='1.${n}';`);
fs.writeFileSync(f, s);
console.log(`v1.${n} · ${gio}`);

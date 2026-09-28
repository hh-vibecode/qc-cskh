// Đẩy nhánh hiện tại của repo qc-cskh lên GitHub. Token lấy từ file khoá, chỉ đưa vào git qua header tạm
// (không lưu vào .git/config, không in ra). Pull --rebase trước để không đè commit ở nơi khác.
// Dùng: ELECTRON_RUN_AS_NODE=1 "D:/Microsoft VS Code/Code.exe" C:/Users/HP/Desktop/qc-cskh/tools/push.js
// Monsieur Claude
const { execFileSync } = require('child_process');
const K = require('./keys.js');
const REPO = require('path').resolve(__dirname, '..');
const auth = 'http.extraheader=Authorization: Basic ' + Buffer.from('x-access-token:' + K.gh).toString('base64');
const git = (...a) => execFileSync('git', ['-c', auth, ...a], { cwd: REPO, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
try {
  git('pull', '--rebase', '--quiet', 'origin', 'main');
  git('push', 'origin', 'HEAD:main');
  console.log('push: ok', git('log', '--oneline', '-1'));
} catch (e) {
  console.error('LỖI', (e.stderr || e.message || '').toString().replace(/Basic \S+/g, 'Basic ***'));
  process.exit(1);
}

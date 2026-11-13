// THAY TOKEN PANCAKE TRÊN GITHUB (13/11/2026, anh Hải: "m không tự thay hộ được à"). Đặt GitHub Actions secret bằng sealed box (libsodium
// crypto_box_seal) viết tay — X25519 (Node) + XSalsa20-Poly1305 + BLAKE2b; tự kiểm 6 bộ số chuẩn (RFC 7693/8439/7748, NaCl) trước khi gửi.
// Giá trị = token Pancake trong qc-keys.local.txt (KHÔNG in). Quyền: GITHUB_TOKEN trong qc-keys.local.txt (scope repo).
// Dùng: …/Code.exe tools/dat-secret-gh.js --thu   (chỉ kiểm bộ số)
//       …/Code.exe tools/dat-secret-gh.js hh-vibecode/qc-cskh PANCAKE_SESSION_TOKEN   (rồi làm tương tự hh-vibecode/mkt-sale-app)
// Đã dùng 13/11: job GitHub chạy lại đọc đủ 14 kênh. Monsieur Claude
const crypto = require('crypto');
const hex = s => Buffer.from(s.replace(/[^0-9a-f]/gi, ''), 'hex');
// ── BLAKE2b (BigInt) ──
const M64 = (1n << 64n) - 1n;
const IV = ['6a09e667f3bcc908', 'bb67ae8584caa73b', '3c6ef372fe94f82b', 'a54ff53a5f1d36f1', '510e527fade682d1', '9b05688c2b3e6c1f', '1f83d9abfb41bd6b', '5be0cd19137e2179'].map(x => BigInt('0x' + x));
const SIG = [[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],[14,10,4,8,9,15,13,6,1,12,0,2,11,7,5,3],[11,8,12,0,5,2,15,13,10,14,3,6,7,1,9,4],[7,9,3,1,13,12,11,14,2,6,5,10,4,0,15,8],[9,0,5,7,2,4,10,15,14,1,11,12,6,8,3,13],[2,12,6,10,0,11,8,3,4,13,7,5,15,14,1,9],[12,5,1,15,14,13,4,10,0,7,6,3,9,2,8,11],[13,11,7,14,12,1,3,9,5,0,15,4,8,6,2,10],[6,15,14,9,11,3,0,8,12,2,13,7,1,4,10,5],[10,2,8,4,7,6,1,5,15,11,9,14,3,12,13,0]];
const rotr = (x, n) => ((x >> BigInt(n)) | (x << BigInt(64 - n))) & M64;
function blake2b(data, outlen) {
  const h = IV.slice(); h[0] ^= 0x01010000n ^ BigInt(outlen);
  const blocks = Math.max(1, Math.ceil(data.length / 128));
  for (let b = 0; b < blocks; b++) {
    const blk = Buffer.alloc(128); data.copy(blk, 0, b * 128, Math.min(data.length, (b + 1) * 128));
    const m = []; for (let i = 0; i < 16; i++) m.push(blk.readBigUInt64LE(i * 8));
    const last = b === blocks - 1, t = BigInt(last ? data.length : (b + 1) * 128);
    const v = [...h, ...IV]; v[12] ^= t & M64; v[13] ^= t >> 64n; if (last) v[14] ^= M64;
    const G = (a, bb, c, d, x, y) => {
      v[a] = (v[a] + v[bb] + x) & M64; v[d] = rotr(v[d] ^ v[a], 32); v[c] = (v[c] + v[d]) & M64; v[bb] = rotr(v[bb] ^ v[c], 24);
      v[a] = (v[a] + v[bb] + y) & M64; v[d] = rotr(v[d] ^ v[a], 16); v[c] = (v[c] + v[d]) & M64; v[bb] = rotr(v[bb] ^ v[c], 63);
    };
    for (let r = 0; r < 12; r++) { const s = SIG[r % 10];
      G(0,4,8,12,m[s[0]],m[s[1]]); G(1,5,9,13,m[s[2]],m[s[3]]); G(2,6,10,14,m[s[4]],m[s[5]]); G(3,7,11,15,m[s[6]],m[s[7]]);
      G(0,5,10,15,m[s[8]],m[s[9]]); G(1,6,11,12,m[s[10]],m[s[11]]); G(2,7,8,13,m[s[12]],m[s[13]]); G(3,4,9,14,m[s[14]],m[s[15]]); }
    for (let i = 0; i < 8; i++) h[i] ^= v[i] ^ v[i + 8];
  }
  const out = Buffer.alloc(64); h.forEach((x, i) => out.writeBigUInt64LE(x, i * 8)); return out.subarray(0, outlen);
}
// ── Salsa20 / HSalsa20 / XSalsa20 ──
const R = (a, b) => ((a << b) | (a >>> (32 - b))) >>> 0;
function core(inp, hs) {
  const x = Uint32Array.from(inp);
  for (let i = 0; i < 10; i++) {
    x[4]^=R((x[0]+x[12])>>>0,7); x[8]^=R((x[4]+x[0])>>>0,9); x[12]^=R((x[8]+x[4])>>>0,13); x[0]^=R((x[12]+x[8])>>>0,18);
    x[9]^=R((x[5]+x[1])>>>0,7); x[13]^=R((x[9]+x[5])>>>0,9); x[1]^=R((x[13]+x[9])>>>0,13); x[5]^=R((x[1]+x[13])>>>0,18);
    x[14]^=R((x[10]+x[6])>>>0,7); x[2]^=R((x[14]+x[10])>>>0,9); x[6]^=R((x[2]+x[14])>>>0,13); x[10]^=R((x[6]+x[2])>>>0,18);
    x[3]^=R((x[15]+x[11])>>>0,7); x[7]^=R((x[3]+x[15])>>>0,9); x[11]^=R((x[7]+x[3])>>>0,13); x[15]^=R((x[11]+x[7])>>>0,18);
    x[1]^=R((x[0]+x[3])>>>0,7); x[2]^=R((x[1]+x[0])>>>0,9); x[3]^=R((x[2]+x[1])>>>0,13); x[0]^=R((x[3]+x[2])>>>0,18);
    x[6]^=R((x[5]+x[4])>>>0,7); x[7]^=R((x[6]+x[5])>>>0,9); x[4]^=R((x[7]+x[6])>>>0,13); x[5]^=R((x[4]+x[7])>>>0,18);
    x[11]^=R((x[10]+x[9])>>>0,7); x[8]^=R((x[11]+x[10])>>>0,9); x[9]^=R((x[8]+x[11])>>>0,13); x[10]^=R((x[9]+x[8])>>>0,18);
    x[12]^=R((x[15]+x[14])>>>0,7); x[13]^=R((x[12]+x[15])>>>0,9); x[14]^=R((x[13]+x[12])>>>0,13); x[15]^=R((x[14]+x[13])>>>0,18);
  }
  if (hs) return [x[0], x[5], x[10], x[15], x[6], x[7], x[8], x[9]];
  return x.map((w, i) => (w + inp[i]) >>> 0);
}
const C = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574];
const words = b => { const w = []; for (let i = 0; i < b.length; i += 4) w.push(b.readUInt32LE(i)); return w; };
const toBuf = w => { const b = Buffer.alloc(w.length * 4); w.forEach((x, i) => b.writeUInt32LE(x >>> 0, i * 4)); return b; };
function state(k, n16) { const kw = words(k), nw = words(n16); return [C[0], kw[0], kw[1], kw[2], kw[3], C[1], nw[0], nw[1], nw[2], nw[3], C[2], kw[4], kw[5], kw[6], kw[7], C[3]]; }
const hsalsa = (k, n16) => toBuf(core(state(k, n16), true));
function xsalsaStream(k, n24, len) {
  const sub = hsalsa(k, n24.subarray(0, 16)), out = Buffer.alloc(Math.ceil(len / 64) * 64);
  for (let c = 0; c * 64 < len; c++) { const ctr = Buffer.alloc(8); ctr.writeBigUInt64LE(BigInt(c)); toBuf(core(state(sub, Buffer.concat([n24.subarray(16, 24), ctr])), false)).copy(out, c * 64); }
  return out.subarray(0, len);
}
// ── Poly1305 ──
const le = b => { let n = 0n; for (let i = b.length - 1; i >= 0; i--) n = (n << 8n) | BigInt(b[i]); return n; };
function poly1305(msg, key) {
  const r = le(key.subarray(0, 16)) & 0x0ffffffc0ffffffc0ffffffc0fffffffn, s = le(key.subarray(16, 32)), p = (1n << 130n) - 5n;
  let a = 0n;
  for (let i = 0; i < msg.length; i += 16) { const blk = msg.subarray(i, i + 16); a = ((a + le(blk) + (1n << BigInt(8 * blk.length))) * r) % p; }
  a = (a + s) & ((1n << 128n) - 1n);
  const out = Buffer.alloc(16); for (let i = 0; i < 16; i++) { out[i] = Number(a & 0xffn); a >>= 8n; } return out;
}
// ── secretbox / box / sealed box (định dạng libsodium: mac || c) ──
function secretbox(m, n24, k) {
  const ks = xsalsaStream(k, n24, 32 + m.length), c = Buffer.alloc(m.length);
  for (let i = 0; i < m.length; i++) c[i] = m[i] ^ ks[32 + i];
  return Buffer.concat([poly1305(c, ks.subarray(0, 32)), c]);
}
const rawPub = ko => Buffer.from(ko.export({ format: 'jwk' }).x, 'base64url');
const pubFromRaw = b => crypto.createPublicKey({ key: { kty: 'OKP', crv: 'X25519', x: b.toString('base64url') }, format: 'jwk' });
function seal(m, pkRaw) {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('x25519');
  const epk = rawPub(publicKey);
  const shared = crypto.diffieHellman({ privateKey, publicKey: pubFromRaw(pkRaw) });
  const k = hsalsa(shared, Buffer.alloc(16));
  const n = blake2b(Buffer.concat([epk, pkRaw]), 24);
  return Buffer.concat([epk, secretbox(m, n, k)]);
}
// ── KIỂM BỘ SỐ CHUẨN ──
function kiem() {
  const ok = (ten, d) => { if (!d) throw new Error('SAI bộ số: ' + ten); console.log('  đạt:', ten); };
  ok('BLAKE2b-512("abc") RFC 7693 phụ lục A', blake2b(Buffer.from('abc'), 64).equals(hex('ba80a53f981c4d0d6a2797b69f12f6e94c212f14685ac4b74b12bb6fdbffa2d17d87c5392aab792dc252d5de4533cc9518d38aa8dbf1925ab92386edd4009923')));
  ok('BLAKE2b-512("") chuẩn', blake2b(Buffer.alloc(0), 64).equals(hex('786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce')));
  ok('Poly1305 RFC 8439 §2.5.2', poly1305(Buffer.from('Cryptographic Forum Research Group'), hex('85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b')).equals(hex('a8061dc1305136c6c22b8baf0c0127a9')));
  const aSk = crypto.createPrivateKey({ key: { kty: 'OKP', crv: 'X25519', d: hex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a').toString('base64url'),
    x: hex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a').toString('base64url') }, format: 'jwk' });
  const sh = crypto.diffieHellman({ privateKey: aSk, publicKey: pubFromRaw(hex('de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f')) });
  ok('X25519 RFC 7748 §6.1', sh.equals(hex('4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742')));
  const k = hsalsa(sh, Buffer.alloc(16));
  ok('HSalsa20 NaCl firstkey', k.equals(hex('1b27556473e985d462cd51197a9a46c76009549eac6474f206c4ee0844f68389')));
  const c = secretbox(hex('be075fc53c81f2d5cf141316ebeb0c7b'), hex('69696ee955b62b73cd62bda875fc73d68219e0036b7a0b37'), k);
  ok('XSalsa20 NaCl box (16 byte đầu)', c.subarray(16).equals(hex('8e993b9f48681273c29650ba32fc76ce')));
}
module.exports = { seal, kiem };
if (require.main === module) (async () => {
  console.log('Kiểm bộ số chuẩn:'); kiem();
  if (process.argv.includes('--thu')) return;
  const [repo, ten] = process.argv.slice(2);
  const K = require('./keys.js');
  const H = { Authorization: 'Bearer ' + K.gh, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json' };
  const pk = await (await fetch(`https://api.github.com/repos/${repo}/actions/secrets/public-key`, { headers: H })).json();
  const enc = seal(Buffer.from(K.pancake), Buffer.from(pk.key, 'base64')).toString('base64');
  const r = await fetch(`https://api.github.com/repos/${repo}/actions/secrets/${ten}`, { method: 'PUT', headers: H, body: JSON.stringify({ encrypted_value: enc, key_id: pk.key_id }) });
  console.log(`${repo} ${ten}: HTTP ${r.status}`, r.status === 204 ? '(đã cập nhật)' : await r.text());
})();

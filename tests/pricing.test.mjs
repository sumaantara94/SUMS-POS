import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const pricing = await readFile(new URL('../pricing.html', import.meta.url), 'utf8');
const build = await readFile(new URL('../scripts/build.mjs', import.meta.url), 'utf8');

test('pricing page presents the launch and regular package prices', () => {
  for (const value of [
    'STARTER', 'GROW', 'SCALE', 'ENTERPRISE',
    'Rp69.000', 'Rp149.000', 'Rp249.000',
    'Rp48.300', 'Rp111.750', 'Rp174.300',
    'Rp509.472', 'Rp1.180.080', 'Rp1.840.608',
    '12%', '14 hari', '31 Desember 2026',
    'One POS platform. Multiple business types. Built to grow.'
  ]) assert.ok(pricing.includes(value), `Missing pricing content: ${value}`);
});

test('pricing page is Indonesian and does not imply trial or checkout is already active', () => {
  assert.ok(pricing.includes('<html lang="id">'));
  assert.ok(pricing.includes('href="/?app=office"'));
  assert.ok(pricing.includes('belum dikonfirmasi aktif'));
  assert.ok(pricing.includes('tidak menjamin masa trial otomatis dimulai'));
});

test('static build copies the pricing page into dist', () => {
  assert.ok(build.includes("copyFile('pricing.html','dist/pricing.html')"));
});

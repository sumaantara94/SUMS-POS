import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const pricing = await readFile(new URL('../pricing.html', import.meta.url), 'utf8');
const build = await readFile(new URL('../scripts/build.mjs', import.meta.url), 'utf8');

test('pricing page presents the approved monthly and annual package prices', () => {
  for (const value of [
    'ESSENTIAL', 'GROWTH', 'INTELLIGENCE',
    'Rp120.000', 'Rp210.000', 'Rp340.000',
    'Rp1.267.200', 'Rp2.217.600', 'Rp3.590.400',
    '12%', 'Run Smarter. Grow Better.'
  ]) assert.ok(pricing.includes(value), `Missing pricing content: ${value}`);
});

test('pricing page is Indonesian and calls to action return to Back Office without implying checkout is live', () => {
  assert.ok(pricing.includes('<html lang="id">'));
  assert.ok(pricing.includes('href="/?app=office"'));
  assert.ok(pricing.includes('belum diaktifkan'));
});

test('static build copies the pricing page into dist', () => {
  assert.ok(build.includes("copyFile('pricing.html','dist/pricing.html')"));
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const migration = await readFile(new URL('../database/032_admin_catalog_role.sql', import.meta.url), 'utf8');
const app = await readFile(new URL('../src/app.mjs', import.meta.url), 'utf8');
const domain = await readFile(new URL('../src/domain.mjs', import.meta.url), 'utf8');
const staff = await readFile(new URL('../functions/staff-access/index.js', import.meta.url), 'utf8');

test('Admin is a supported membership role with catalog-only default permissions', () => {
  assert.match(migration, /role in \('owner','admin','cashier','waiter','custom'\)/);
  assert.match(migration, /else array\['products'\]/);
  assert.doesNotMatch(migration, /else array\[[^\]]*'reports'[^\]]*\]/);
  assert.match(domain, /admin:\['products'\]/);
});

test('Owner staff form exposes Admin with a clear limited scope', () => {
  assert.match(app, /value="admin">Admin Back Office · kelola katalog produk/);
  assert.match(staff, /!\['cashier','waiter','admin'\]\.includes\(input\.role\)/);
});

test('Admin accounts are routed to Back Office and not the cashier portal', () => {
  assert.match(app, /if\(role==='admin'\)\{surface='office'/);
  assert.match(app, /u\.searchParams\.set\('app','office'\)/);
});

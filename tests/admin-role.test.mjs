import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

const migration = await readFile(new URL('../database/032_admin_catalog_role.sql', import.meta.url), 'utf8');
const app = await readFile(new URL('../src/app.mjs', import.meta.url), 'utf8');
const domain = await readFile(new URL('../src/domain.mjs', import.meta.url), 'utf8');
const staff = await readFile(new URL('../functions/staff-access/index.js', import.meta.url), 'utf8');

test('Admin is a supported membership role with catalog-only default permissions', () => {
  assert.ok(migration.includes("check(role in ('owner','admin','cashier','waiter','custom'))"));
  assert.ok(migration.includes("else array['products']"));
  assert.ok(!migration.includes("else array['products','reports']"));
  assert.ok(domain.includes("admin:['products']"));
});

test('Owner staff form exposes Admin with a clear limited scope', () => {
  assert.ok(app.includes('value="admin">Admin Back Office · kelola katalog produk'));
  assert.ok(staff.includes("!['cashier','waiter','admin'].includes(input.role)"));
});

test('Admin accounts are routed to Back Office while preserving username login on reload', () => {
  assert.ok(app.includes("if(role==='admin'){surface='office'}else if(['cashier','waiter'].includes(role))"));
  assert.ok(app.includes("if(role==='admin'&&next==='pos')return toast"));
});

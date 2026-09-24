// Run with:  node tests/ownership.test.js      (no database or npm packages needed)
// Verifies the ownership middleware against an in-memory stand-in for Postgres.
const assert = require('assert');
const path = require('path');

const exams = [
  { id: 'e-alice', user_id: 1 },
  { id: 'e-bob', user_id: 2 },
];
const results = [{ id: 'r-alice', exam_id: 'e-alice' }, { id: 'r-bob', exam_id: 'e-bob' }];
const scans = [{ id: 's-alice', exam_id: 'e-alice' }, { id: 's-bob', exam_id: 'e-bob' }];

const fakePool = {
  async query(sql, params) {
    const q = sql.replace(/\s+/g, ' ');
    if (params.some((p) => p === 'not-a-uuid')) {
      const e = new Error('invalid input syntax for type uuid'); e.code = '22P02'; throw e;
    }
    if (q.includes('FROM exam_results r JOIN exams e')) {
      const [rid, uid] = params;
      const r = results.find((x) => x.id === rid);
      const e = r && exams.find((x) => x.id === r.exam_id);
      return { rows: e && e.user_id === uid ? [{ '?column?': 1 }] : [] };
    }
    if (q.includes('FROM omr_scans s JOIN exams e')) {
      const [sid, eid, uid] = params;
      const s = scans.find((x) => x.id === sid && x.exam_id === eid);
      const e = s && exams.find((x) => x.id === s.exam_id);
      return { rows: e && e.user_id === uid ? [{ '?column?': 1 }] : [] };
    }
    if (q.includes('FROM exams WHERE id = $1 AND user_id = $2')) {
      const [eid, uid] = params;
      return { rows: exams.some((x) => x.id === eid && x.user_id === uid) ? [{ '?column?': 1 }] : [] };
    }
    throw new Error('unexpected query: ' + q);
  },
};
const dbPath = path.resolve(__dirname, '../config/db.js');
require.cache[dbPath] = { id: dbPath, filename: dbPath, loaded: true, exports: fakePool };
const own = require('../middleware/ownership');

function run(mw, { user, params, body, value }) {
  return new Promise((resolve) => {
    const res = {
      statusCode: 200,
      status(c) { this.statusCode = c; return this; },
      json(b) { resolve({ status: this.statusCode, body: b, passed: false }); },
    };
    const next = (err) => resolve({ passed: true, error: err });
    const req = { user, params: params || {}, body: body || {} };
    if (value !== undefined) mw(req, res, next, value); else mw(req, res, next);
  });
}
const alice = { id: 1 }, bob = { id: 2 };
let n = 0;
async function check(name, promise, expect) {
  const r = await promise;
  if (expect === 'pass') assert.ok(r.passed && !r.error, `${name}: expected pass, got ${JSON.stringify(r)}`);
  else assert.ok(!r.passed && r.status === expect, `${name}: expected ${expect}, got ${JSON.stringify(r)}`);
  n++; console.log('  ok  ' + name);
}

(async () => {
  console.log('exam id in URL (router.param)');
  await check('owner can open own exam', run(own.examParam, { user: alice, value: 'e-alice' }), 'pass');
  await check("other user cannot open Alice's exam -> 404", run(own.examParam, { user: bob, value: 'e-alice' }), 404);
  await check('unknown exam -> 404', run(own.examParam, { user: alice, value: 'e-nope' }), 404);
  await check('malformed id -> 404 (not a 500)', run(own.examParam, { user: alice, value: 'not-a-uuid' }), 404);

  console.log('result id in URL');
  await check('owner can open own result', run(own.resultParam, { user: alice, value: 'r-alice' }), 'pass');
  await check("other user cannot open Alice's result -> 404", run(own.resultParam, { user: bob, value: 'r-alice' }), 404);

  console.log('exam id in request body');
  await check('owner passes', run(own.requireExamInBody, { user: alice, body: { exam_id: 'e-alice' } }), 'pass');
  await check('other user blocked -> 404', run(own.requireExamInBody, { user: bob, body: { exam_id: 'e-alice' } }), 404);
  await check('missing exam_id falls through to route 400', run(own.requireExamInBody, { user: alice, body: {} }), 'pass');

  console.log('scoring: exam + scan');
  await check('owner scores own scan', run(own.requireExamAndScanInBody, { user: alice, body: { exam_id: 'e-alice', scan_id: 's-alice' } }), 'pass');
  await check("cannot score against someone else's exam", run(own.requireExamAndScanInBody, { user: bob, body: { exam_id: 'e-alice', scan_id: 's-alice' } }), 404);
  await check("cannot score another user's scan against own exam", run(own.requireExamAndScanInBody, { user: bob, body: { exam_id: 'e-bob', scan_id: 's-alice' } }), 404);

  console.log(`\nall ${n} ownership checks passed`);
})().catch((e) => { console.error('FAILED:', e.message); process.exit(1); });

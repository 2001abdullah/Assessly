const assert = require('assert');
const { resolvePythonPath } = require('../services/scoring');

assert.strictEqual(
  resolvePythonPath({
    env: { OMR_PYTHON: '/opt/assessly-venv/bin/python' },
    platform: 'linux',
  }),
  '/opt/assessly-venv/bin/python',
);

assert.strictEqual(
  resolvePythonPath({ env: {}, platform: 'linux' }),
  'python3',
);

assert.strictEqual(
  resolvePythonPath({
    env: {},
    platform: 'win32',
    existsSync: () => false,
  }),
  'python',
);

assert.ok(
  resolvePythonPath({
    env: {},
    platform: 'win32',
    existsSync: () => true,
  }).endsWith('python.exe'),
);

console.log('Python path resolution checks passed');

const assert = require('assert');
const {
  formatDetectedIdentifier,
  resolvePythonPath,
} = require('../services/scoring');

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

assert.strictEqual(
  formatDetectedIdentifier({ digits: [2, 6, 0, null, null, null, null] }),
  '260????',
);

assert.strictEqual(
  formatDetectedIdentifier({ digits: [2, 2, 2, 0, 1, 2, 6, 0, null, null] }),
  '22201260??',
);

assert.strictEqual(
  formatDetectedIdentifier({ value: '0012345', digits: [] }),
  '0012345',
);

assert.strictEqual(
  formatDetectedIdentifier({ digits: [null, null] }),
  null,
);

console.log('Python path resolution checks passed');

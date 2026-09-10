require('dotenv').config();

const { scoreScan } = require('./services/scoring');

const EXAM_ID = '81e898c9-209f-4cad-b308-8ef7fd5fde9a';
const SCAN_ID = '96d8fc88-84fd-476d-8d82-5f83ed7658f8';

async function main() {
  try {
    console.log('Starting scoring test...\n');

    const result = await scoreScan({
      examId: EXAM_ID,
      scanId: SCAN_ID,
      name: '',
    });

    console.log('Scoring successful!\n');

    console.log(
      JSON.stringify(result, null, 2)
    );
  } catch (error) {
    console.error('\nScoring failed:');
    console.error(error.message);
    console.error(error.stack);
    process.exitCode = 1;
  }
}

main();
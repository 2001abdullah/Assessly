require('dotenv').config();

const express = require('express');
const pool = require('./config/db');
const authRoutes = require('./routes/auth');
const loginRoutes = require('./routes/login');
const omrRoutes = require('./routes/omr');
const examRoutes= require('./routes/exam');
const answerKeyRoutes = require('./routes/answerKeys');
const scoringRoutes = require('./routes/scoring');
const resultRoutes = require('./routes/results');
const scoringRulesRoutes = require('./routes/scoringRules');
const authMiddleware = require('./middleware/authMiddleware');

const app = express();

app.use(express.json());
app.use('/api/auth', authRoutes);
app.use('/api/auth', loginRoutes);

// Everything below requires a signed-in user; each router then limits access
// to that user's own exams (see middleware/ownership.js).
app.use('/api/omr', authMiddleware, omrRoutes);
app.use('/api/exam', authMiddleware, examRoutes);
app.use('/api/answer-key', authMiddleware, answerKeyRoutes);
app.use('/api/scoring', authMiddleware, scoringRoutes);
app.use('/api/results', authMiddleware, resultRoutes);
app.use('/api/scoring-rules', authMiddleware, scoringRulesRoutes);

app.get('/', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'Assessly backend',
    omr_scan_endpoint: 'POST /api/omr/scan',
  });
});

app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    return res.status(200).json({
      status: 'ok',
      database: 'connected',
    });
  } catch (error) {
    console.error('Health check database error:', error);
    return res.status(503).json({
      status: 'degraded',
      database: 'disconnected',
    });
  }
});

const port = Number(process.env.PORT || 5000);

pool.query(`
  ALTER TABLE exams
  ADD COLUMN IF NOT EXISTS owner_id UUID REFERENCES users(id)
`).catch((error) => {
  console.error('Could not ensure exam ownership column:', error.message);
});

pool.on('error', (error) => {
  console.error('Unexpected PostgreSQL pool error:', error);
});

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`Assessly server running on port ${port}`);
});

server.on('error', (error) => {
  console.error(`Backend server error on port ${port}:`, error);
});

app.use((error, _req, res, _next) => {
  console.error('Unhandled request error:', error);

  if (res.headersSent) {
    return;
  }

  res.status(500).json({
    message: 'Internal server error',
  });
});

pool.query('SELECT NOW()')
  .then((result) => {
    console.log('Database connected successfully:', result.rows[0]);
  })
  .catch((error) => {
    console.error(
      'Database is unavailable at startup. The server will remain online and retry on requests:',
      error.message,
    );
  });

let isShuttingDown = false;

const shutdown = (signal) => {
  if (isShuttingDown) {
    return;
  }

  isShuttingDown = true;
  console.log(`${signal} received. Closing backend server...`);

  server.close((serverError) => {
    if (serverError) {
      console.error('Error while closing backend server:', serverError);
      process.exitCode = 1;
      return;
    }

    pool.end()
      .then(() => {
        console.log('Backend server and database pool closed');
      })
      .catch((poolError) => {
        console.error('Error while closing database pool:', poolError);
        process.exitCode = 1;
      });
  });
};

process.once('SIGINT', () => shutdown('SIGINT'));
process.once('SIGTERM', () => shutdown('SIGTERM'));
process.once('uncaughtException', (error) => {
  console.error('Uncaught exception; shutting down safely:', error);
  shutdown('uncaughtException');
});
process.once('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection; shutting down safely:', reason);
  shutdown('unhandledRejection');
});
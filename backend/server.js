// Assessly API entry point.
//
// Request flow:
//   JSON body parser (1 MB) -> request logger (pino, x-request-id) -> metrics
//   -> security headers -> router -> error handler
//
// Routers:
//   /api/auth           public, rate-limited      routes/auth.js
//   /api/omr            JWT + upload rate limit   routes/omr.js
//   /api/exam           JWT                       routes/exam.js
//   /api/answer-key     JWT                       routes/answerKeys.js
//   /api/scoring-rules  JWT                       routes/scoringRules.js
//   /api/scoring        JWT                       routes/scoring.js
//   /api/results        JWT                       routes/results.js
//   /api/classes        JWT                       routes/classes.js
//   /api/student        JWT, student role         routes/student.js
//   /api/profile        JWT, any role             routes/profile.js
//   /api/notifications  JWT, any role             routes/notifications.js
//   /health             public, checks PostgreSQL
//
// Every router except auth/profile/notifications/student is teacher-only.
//   /metrics            Prometheus; requires Bearer METRICS_TOKEN (404 otherwise)
//
// Every JWT router additionally restricts access to the caller's own exams
// (middleware/ownership.js).

require('dotenv').config();

if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
  throw new Error('JWT_SECRET must be configured with at least 32 characters');
}

const express = require('express');
const { rateLimit } = require('express-rate-limit');
const pool = require('./config/db');
const authMiddleware = require('./middleware/authMiddleware');
const { metricsHandler, metricsMiddleware, requestLogger } = require('./middleware/observability');
const authRoutes = require('./routes/auth');
const omrRoutes = require('./routes/omr');
const examRoutes = require('./routes/exam');
const answerKeyRoutes = require('./routes/answerKeys');
const scoringRoutes = require('./routes/scoring');
const resultRoutes = require('./routes/results');
const scoringRulesRoutes = require('./routes/scoringRules');
const classRoutes = require('./routes/classes');
const studentRoutes = require('./routes/student');
const profileRoutes = require('./routes/profile');
const notificationRoutes = require('./routes/notifications');
const { requireRole } = require('./middleware/roles');

const app = express();

app.disable('x-powered-by');
// One proxy hop (Render's load balancer) so req.ip, and therefore rate
// limiting, uses the real client address.
app.set('trust proxy', 1);
app.use(express.json({ limit: '1mb' }));
app.use(requestLogger);
app.use(metricsMiddleware);
app.use((_req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
  next();
});

// Per client IP, per 15 minutes.
const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 20, standardHeaders: 'draft-8', legacyHeaders: false });
const uploadLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 60, standardHeaders: 'draft-8', legacyHeaders: false });

const teacher = [authMiddleware, requireRole('teacher')];

app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/omr', uploadLimiter, ...teacher, omrRoutes);
app.use('/api/exam', ...teacher, examRoutes);
app.use('/api/answer-key', ...teacher, answerKeyRoutes);
app.use('/api/scoring', ...teacher, scoringRoutes);
app.use('/api/results', ...teacher, resultRoutes);
app.use('/api/scoring-rules', ...teacher, scoringRulesRoutes);
app.use('/api/classes', ...teacher, classRoutes);
app.use('/api/student', authMiddleware, requireRole('student'), studentRoutes);
app.use('/api/profile', authMiddleware, profileRoutes);
app.use('/api/notifications', authMiddleware, notificationRoutes);

app.get('/', (_req, res) => {
  res.json({ status: 'ok', service: 'Assessly backend' });
});

// Used by Render's health check and for manual connectivity tests.
app.get('/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    return res.status(200).json({
      status: 'ok',
      database: 'connected',
      version: process.env.RENDER_GIT_COMMIT || 'development',
    });
  } catch (error) {
    console.error('Health check database error:', error);
    return res.status(503).json({ status: 'degraded', database: 'disconnected' });
  }
});

// Answers 404 (not 401) without the token so the endpoint is not advertised.
app.get('/metrics', (req, res, next) => {
  const token = process.env.METRICS_TOKEN;
  if (!token || req.headers.authorization !== `Bearer ${token}`) {
    return res.status(404).end();
  }
  return metricsHandler(req, res, next);
});

// Last resort for errors a route did not handle (Express 5 also routes
// rejected async handlers here). Never leaks internals to the client.
app.use((error, _req, res, _next) => {
  if (error instanceof Error && error.name === 'MulterError') {
    return res.status(400).json({ message: error.message });
  }
  console.error('Unhandled request error:', error);
  if (res.headersSent) return undefined;
  return res.status(500).json({ message: 'Internal server error' });
});

pool.on('error', (error) => {
  console.error('Unexpected PostgreSQL pool error:', error);
});

const port = Number(process.env.PORT || 5000);
const server = app.listen(port, '0.0.0.0', () => {
  console.log(`Assessly server running on port ${port}`);
});

server.on('error', (error) => {
  console.error(`Backend server error on port ${port}:`, error);
});

pool.query('SELECT NOW()')
  .then(() => console.log('Database connected successfully'))
  .catch((error) => {
    console.error(
      'Database is unavailable at startup. The server will remain online and retry on requests:',
      error.message,
    );
  });

// Graceful shutdown: stop accepting connections, let in-flight requests
// finish, then close the database pool.
let isShuttingDown = false;

const shutdown = (signal) => {
  if (isShuttingDown) return;
  isShuttingDown = true;
  console.log(`${signal} received. Closing backend server...`);

  server.close((serverError) => {
    if (serverError) {
      console.error('Error while closing backend server:', serverError);
      process.exitCode = 1;
      return;
    }
    pool.end()
      .then(() => console.log('Backend server and database pool closed'))
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
  process.exitCode = 1;
  shutdown('uncaughtException');
});
process.once('unhandledRejection', (reason) => {
  console.error('Unhandled promise rejection; shutting down safely:', reason);
  process.exitCode = 1;
  shutdown('unhandledRejection');
});

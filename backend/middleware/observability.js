const crypto = require('crypto');
const pinoHttp = require('pino-http');
const client = require('prom-client');

client.collectDefaultMetrics();
const requests = new client.Histogram({
  name: 'assessly_http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30],
});

const requestLogger = pinoHttp({
  genReqId(req, res) {
    const id = req.headers['x-request-id'] || crypto.randomUUID();
    res.setHeader('x-request-id', id);
    return id;
  },
  redact: ['req.headers.authorization', 'req.body.password', 'req.body.token'],
});

function metricsMiddleware(req, res, next) {
  const end = requests.startTimer();
  res.once('finish', () => end({
    method: req.method,
    route: req.route?.path || req.path || 'unknown',
    status_code: String(res.statusCode),
  }));
  next();
}

async function metricsHandler(_req, res) {
  res.setHeader('Content-Type', client.register.contentType);
  res.end(await client.register.metrics());
}

module.exports = { metricsHandler, metricsMiddleware, requestLogger };

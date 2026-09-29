// Requires `Authorization: Bearer <JWT>` (issued by routes/auth.js).
// On success sets req.user = { id, email, name, iat, exp }; otherwise 401.
// The app treats any 401 as "session expired" and signs the user out.

const jwt = require('jsonwebtoken');

function authMiddleware(req, res, next) {
  const [scheme, token] = String(req.headers.authorization || '').split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ message: 'authorization token required' });
  }

  try {
    req.user = jwt.verify(token, process.env.JWT_SECRET);
    return next();
  } catch (_error) {
    return res.status(401).json({ message: 'invalid or expired token' });
  }
}

module.exports = authMiddleware;

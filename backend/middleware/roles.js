// Role gates. Run after authMiddleware.
//
// The role travels in the JWT (routes/auth.js). Tokens issued before roles
// existed carry none; every account from that time is a teacher.

function roleOf(req) {
  return req.user?.role || 'teacher';
}

function requireRole(role) {
  return (req, res, next) => {
    if (roleOf(req) !== role) {
      return res.status(403).json({ message: `This action is only for ${role}s` });
    }
    return next();
  };
}

module.exports = { roleOf, requireRole };

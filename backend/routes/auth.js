const express= require('express');
const pool= require('../config/db');
const bcrypt=require('bcrypt');
const crypto = require('crypto');
const { sendPasswordResetCode } = require('../services/email');


const router= express.Router();

const genericResetMessage = {
  message: 'If that account exists, a reset code has been sent.',
};

router.post('/forgot-password', async (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  if (!email) return res.status(400).json({ message: 'email is required' });

  try {
    const userResult = await pool.query(
      'SELECT id, email FROM users WHERE lower(email) = $1',
      [email],
    );
    if (!userResult.rows.length) return res.status(202).json(genericResetMessage);

    const code = crypto.randomInt(100000, 1000000).toString();
    const tokenHash = crypto.createHash('sha256').update(code).digest('hex');
    await pool.query('DELETE FROM password_reset_tokens WHERE user_id = $1', [userResult.rows[0].id]);
    await pool.query(
      `INSERT INTO password_reset_tokens (id, user_id, token_hash, expires_at)
       VALUES ($1, $2, $3, now() + interval '15 minutes')`,
      [crypto.randomUUID(), userResult.rows[0].id, tokenHash],
    );
    await sendPasswordResetCode({ email: userResult.rows[0].email, code });
    return res.status(202).json(genericResetMessage);
  } catch (error) {
    console.error('password reset request error:', error.message);
    return res.status(202).json(genericResetMessage);
  }
});

router.post('/reset-password', async (req, res) => {
  const email = String(req.body?.email || '').trim().toLowerCase();
  const code = String(req.body?.code || '').trim();
  const password = String(req.body?.password || '');
  if (!email || !/^\d{6}$/.test(code) || password.length < 8) {
    return res.status(400).json({ message: 'Valid email, 6-digit code, and 8-character password are required' });
  }

  const tokenHash = crypto.createHash('sha256').update(code).digest('hex');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const tokenResult = await client.query(
      `SELECT prt.id, prt.user_id
         FROM password_reset_tokens prt
         JOIN users u ON u.id = prt.user_id
        WHERE lower(u.email) = $1 AND prt.token_hash = $2
          AND prt.used_at IS NULL AND prt.expires_at > now()
        FOR UPDATE`,
      [email, tokenHash],
    );
    if (!tokenResult.rows.length) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'Reset code is invalid or expired' });
    }
    const passwordHash = await bcrypt.hash(password, 12);
    await client.query('UPDATE users SET password_hash = $1 WHERE id = $2', [passwordHash, tokenResult.rows[0].user_id]);
    await client.query('UPDATE password_reset_tokens SET used_at = now() WHERE id = $1', [tokenResult.rows[0].id]);
    await client.query('COMMIT');
    return res.status(200).json({ message: 'Password reset successfully' });
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('password reset error:', error.message);
    return res.status(500).json({ message: 'Could not reset password' });
  } finally {
    client.release();
  }
});

router.post('/register', async (req,res)=>
{
try{
const {name, email, password}=req.body;

if(!name || !email || !password)
{
return res.status(400).json(
{
message: "name,email and password are required"
});
}
if(password.length<8){

return res.status(400).json(
{
message: "password must be at least 8 characters"
});
}
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

if (!emailRegex.test(email)) {
  return res.status(400).json({
    message: 'Please enter a valid email address'
  });
}

const result= await pool.query(
'SELECT * FROM users where lower(email)=lower($1)',
[email.trim()]

);

if(result.rows.length>0)
{
return res.status(409).json(
{
message:"email already registered"
});
}

const passwordHash=await bcrypt.hash(password,12);

const insertResult=await pool.query(
`INSERT INTO users (name,email,password_hash)
VALUES ($1,$2,$3)
RETURNING id,name,email,created_at`,
[name.trim(),email.trim().toLowerCase(),passwordHash]

);

res.status(201).json({
message:"user registered successfully",
user:insertResult.rows[0]
}
);


}
catch(error){
console.error('registration error:',error.message);
res.status(500).json(
{
message:"something went wrong while registering the user"
});
}
});

module.exports=router;

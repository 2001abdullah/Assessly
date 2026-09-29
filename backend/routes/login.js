const express= require('express');
const pool=require('../config/db');
const bcrypt=require('bcrypt');
const jwt=require("jsonwebtoken");
const authMiddleware=require("../middleware/authMiddleware");
const { OAuth2Client } = require('google-auth-library');
const router=express.Router();

const googleClient = new OAuth2Client();

function createSession(user) {
    const token = jwt.sign(
        { id: user.id, email: user.email, name: user.name },
        process.env.JWT_SECRET,
        { expiresIn: process.env.JWT_EXPIRES_IN || '7d' },
    );
    return {
        message: 'login successful',
        token,
        user: { id: user.id, name: user.name, email: user.email },
    };
}

router.post('/google', async (req, res) => {
    const idToken = req.body?.id_token;
    const audience = process.env.GOOGLE_CLIENT_ID;
    if (!idToken) return res.status(400).json({ message: 'Google ID token is required' });
    if (!audience) return res.status(503).json({ message: 'Google sign-in is not configured' });

    try {
        const ticket = await googleClient.verifyIdToken({ idToken, audience });
        const payload = ticket.getPayload();
        if (!payload?.sub || !payload.email || payload.email_verified !== true) {
            return res.status(401).json({ message: 'Google account could not be verified' });
        }

        const name = String(payload.name || payload.email.split('@')[0]).slice(0, 100);
        const email = payload.email.toLowerCase();
        const userResult = await pool.query(
            `INSERT INTO users (name, email, google_subject)
             VALUES ($1, $2, $3)
             ON CONFLICT (email) DO UPDATE
               SET google_subject = COALESCE(users.google_subject, EXCLUDED.google_subject),
                   name = CASE WHEN users.name = '' THEN EXCLUDED.name ELSE users.name END
             WHERE users.google_subject IS NULL
                OR users.google_subject = EXCLUDED.google_subject
             RETURNING id, name, email`,
            [name, email, payload.sub],
        );
        if (!userResult.rows[0]) {
            return res.status(409).json({ message: 'Google account does not match the linked account' });
        }
        return res.status(200).json(createSession(userResult.rows[0]));
    } catch (error) {
        console.error('Google login error', error.message);
        return res.status(401).json({ message: 'Google sign-in failed' });
    }
});

router.post('/login', async (req,res)=>{
const {email,password}=req.body;
try{
    if(!email || !password)
{
    return res.status(400).json(
        {
            message: "email and password are required"
        }
    );
}
const result=await pool.query(
    'SELECT * FROM users where email=$1',
    [email]
);
if (result.rows.length==0)
{
    return res.status(404).json(
        {
            message: "user not found"
        }
    );
}
const user=result.rows[0];
if (!user.password_hash) {
    return res.status(400).json({ message: 'Use Google to sign in to this account' });
}
const isMatch=await bcrypt.compare(
    password,
    user.password_hash
);
if(!isMatch)
{
    return res.status(401).json(
        {
            message: "invalid password"
        }
    );
}
return res.json(createSession(user));

}
catch(error){
    console.error('login error',error.message);

    res.status(500).json(
        {
            message: "something went wrong while loggin in"
        }
    )
}
})

router.get('/me',authMiddleware,async (req,res)=>
{
    try{
        const result=await pool.query(
            'SELECT id,name,email,created_at FROM users where id=$1',
            [req.user.id]
        );
        if(result.rows.length===0)
        {
            return res.status(404).json({message:"user not found"});
        }
        res.json(
            {
                message:"authenticated user",
                user: result.rows[0]
            }
        );
    }
    catch(error){
        console.error('profile error',error.message);
        res.status(500).json({message:"could not load profile"});
    }
});

// Permanently remove the signed-in user and all data owned through their
// exams. Exam foreign keys cascade to answer keys, scans, answers and results.
router.delete('/me', authMiddleware, async (req, res) => {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        await client.query('DELETE FROM exams WHERE user_id = $1', [req.user.id]);
        const deleted = await client.query(
            'DELETE FROM users WHERE id = $1 RETURNING id',
            [req.user.id],
        );
        await client.query('COMMIT');

        if (deleted.rows.length === 0) {
            return res.status(404).json({ message: 'user not found' });
        }
        return res.status(200).json({ message: 'account deleted' });
    } catch (error) {
        await client.query('ROLLBACK');
        console.error('account deletion error', error.message);
        return res.status(500).json({ message: 'could not delete account' });
    } finally {
        client.release();
    }
});

module.exports=router;

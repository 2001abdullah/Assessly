const express= require('express');
const pool=require('../config/db');
const bcrypt=require('bcrypt');
const jwt=require("jsonwebtoken");
const authMiddleware=require("../middleware/authMiddleware");
const router=express.Router();

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
const token=jwt.sign(
    {
        id:user.id,
        email:user.email
    },
    process.env.JWT_SECRET,
    {
        expiresIn: '1h'
    }
);
return res.json(
    {
        message: "login successful",
        token:token
    }
);

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

router.get('/me',authMiddleware,(req,res)=>
{
    res.json(
        {
            message:"authenticated user",
            user: req.user
        }
    );

});

module.exports=router;

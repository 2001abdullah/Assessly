const express= require('express');
const pool= require('../config/db');
const bcrypt=require('bcrypt');


const router= express.Router();

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
if(password.length<6){

return res.status(400).json(
{
message: "password must be atleast 6 charecters"
});
}
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

if (!emailRegex.test(email)) {
  return res.status(400).json({
    message: 'Please enter a valid email address'
  });
}

const result= await pool.query(
'SELECT * FROM users where email=$1',
[email]

);

if(result.rows.length>0)
{
return res.status(409).json(
{
message:"email already registered"
});
}

const passwordHash=await bcrypt.hash(password,10);

const insertResult=await pool.query(
`INSERT INTO users (name,email,password_hash)
VALUES ($1,$2,$3)
RETURNING id,name,email,created_at`,
[name,email,passwordHash]

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
import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {


 final TextEditingController emailController=TextEditingController();
 final TextEditingController passwordController=TextEditingController();

 bool obscurePassword=true;
 bool isLoading=false;

 @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Padding(
          padding: EdgeInsetsGeometry.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text("Welcome Back",
              style: AppTextStyles.heading,),
              SizedBox(height: 20,),
              Text("Login to continue using Assessly"),
              SizedBox(height: 30,),

              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: "Email",
                 prefixIcon: Icon(Icons.email_outlined,
                  color: AppColors.primary,)
                ),
              ),
              SizedBox(height: 20,),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                      onPressed: (){
                        setState(() {
                          obscurePassword =! obscurePassword;
                        });
                      },
                      icon: Icon(obscurePassword==true?
                      Icons.visibility
                      :Icons.visibility_off)
                  ),
                  prefixIcon: Icon(Icons.lock_outline,
                  color: AppColors.primary,),
                  labelText: "Password"
                ),
              ),
              TextButton(
                  onPressed: (){
                    Navigator.pushNamed(
                      context,
                      AppRoutes.forgotPassword
                    );


                  },
                  child: Text('Forgot Password')
              ),
              SizedBox(height: 10,),
              ElevatedButton(onPressed: () async{
               final authProvider=context.read<AuthProvider>();
               
               try{
                 await authProvider.login(emailController.text.trim(),
                     passwordController.text);

                 if(!mounted) return;

                 Navigator.pushReplacementNamed(context, AppRoutes.home);
               }
               catch(error)
                {
                  if(!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
                }
              },

                  child: Text("Login"),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(150, 55),
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadiusGeometry.circular(20)
                  )
                ),
              ),
              SizedBox(height: 20,),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Don't have and account?",
                  style: AppTextStyles.body,),
                  TextButton(onPressed: (){
                    Navigator.pushNamed(context,
                    AppRoutes.register);

                  },
                      child: Text(
                        'Register',
                         style: AppTextStyles.body,
                      )
                  )
                ],
              )
            ],
          ),
      )),
    );
  }
}


import 'package:assessly/providers/auth_provider.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {

  final TextEditingController nameController=TextEditingController();
  final TextEditingController emailController=TextEditingController();
  final TextEditingController passwordController=TextEditingController();
  final TextEditingController confirmPasswordController=TextEditingController();

  bool obscurePassword=true;
  bool obscureConfirmPassword=true;
  bool isLoading=false;

  @override
  void dispose() {
   nameController.dispose();
   emailController.dispose();
   passwordController.dispose();
   confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      body: SafeArea(child: Padding(
        padding: const EdgeInsets.all(24,),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Create Account",
            style: AppTextStyles.heading,),
            SizedBox(height: 50,),
            TextField(
              controller: nameController,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                  suffixIcon: Icon(Icons.person_outline),
                labelText: "Name"
              ),
            ),
            SizedBox(height: 30,),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                suffixIcon: Icon(Icons.email_outlined),
                  labelText: "email"
              ),
            ),
            SizedBox(height: 30,),
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
                    color: AppColors.primary),
                  labelText: "Password"
              ),
            ),
            SizedBox(height: 30,),
            TextField(
              controller: confirmPasswordController,
              obscureText: obscureConfirmPassword,
              decoration: InputDecoration(
                  suffixIcon: IconButton(
                      onPressed: (){
                        setState(() {
                          obscureConfirmPassword =! obscureConfirmPassword;
                        });
                      },
                      icon: Icon(obscureConfirmPassword==true?
                      Icons.visibility
                          :Icons.visibility_off)
                  ),
                  prefixIcon: Icon(Icons.lock_outline,
                      color: AppColors.primary),
                  labelText: "Confirm Password"
              ),
            ),
            SizedBox(height: 30,),
            ElevatedButton(onPressed: () async{
              final authProvider=context.read<AuthProvider>();
              if(passwordController.text != confirmPasswordController.text)
              {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("password do not match"))
                );
                return ;
              }
              try{

               await authProvider.register(nameController.text,
                    emailController.text.trim(),
                    passwordController.text);

                if(!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Registration Successful"),
                duration: Duration(seconds: 2),));

                await Future.delayed(const Duration(seconds: 2));

                Navigator.pop(context);
              }
              catch(error)
              {
                if(!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },

              child: Text("Registration"),
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

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Already have an account?",
                  style: AppTextStyles.body,),
                TextButton(onPressed: (){
                  Navigator.pop(context);

                },
                    child: Text(
                      'login',
                      style: AppTextStyles.body,
                    )
                )
              ],
            )

          ],
        ),
      )
      ),
    );
  }
}

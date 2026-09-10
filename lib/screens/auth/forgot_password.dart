import 'package:assessly/themes/app_colors.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:flutter/material.dart';

class ForgotPassword extends StatefulWidget {
  const ForgotPassword({super.key});

  @override
  State<ForgotPassword> createState() => _ForgotPasswordState();
}

class _ForgotPasswordState extends State<ForgotPassword> {
  final TextEditingController emailController=TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child:
      Padding(padding: EdgeInsetsGeometry.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Forgot Password?",
            style: AppTextStyles.title,),
            SizedBox(height: 20,),

            Text("Enter your email and we'll send you a link to reset your password",
            style: AppTextStyles.body,),

            SizedBox(height: 20,),

            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                  suffixIcon: Icon(Icons.email_outlined),
                  labelText: "email"
              ),
            ),
            SizedBox(height: 50,),

            ElevatedButton(onPressed: (){
              print(emailController.text);
            },

              child: Text("Send link"),
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
                Text("Remember your password?",
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

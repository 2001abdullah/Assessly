import 'dart:async';

import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/screens/home_screen.dart';
import 'package:assessly/screens/onboarding/onboarding_screen.dart';
import 'package:assessly/services/auth_service.dart';
import 'package:assessly/themes/app_text_styles.dart';
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});


  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
 
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    
    Timer(
      Duration(seconds: 2),

        () async{

          final loggedIn=await AuthService.isLoggedIn();
         if(!mounted) return;

         if(loggedIn)
           {
             Navigator.pushReplacementNamed(context,
                 AppRoutes.home);
           }
         else {
           Navigator.pushReplacementNamed(
             context,
             AppRoutes.onboarding,
           );
         }

        }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text("Assessly",
        style: AppTextStyles.heading
        ),

      ),
    );
  }
}

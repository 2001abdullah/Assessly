import 'package:assessly/routes/app_routes.dart';
import 'package:assessly/themes/app_colors.dart';
import 'package:flutter/material.dart';
import 'onboarding_page.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {

  final PageController pageController=PageController();
  int currentPage=0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: PageView(
              controller: pageController,
              onPageChanged: (index){
                setState(() {
                  currentPage=index;
                });
                print(currentPage);
              },
              children: [
                OnboardingPage(icon: Icons.assignment_outlined,
                    title: "Create and Manage Exams",
                    description:   "Create exams, add questions, marks and answer keys easily.",
                ),
                OnboardingPage(icon: Icons.document_scanner_outlined,
                    title: "Scan OMR Sheets",
                    description:   "Scan student answer sheets and automatically calculate marks.",
                ),
                OnboardingPage(icon: Icons.analytics_outlined,
                    title: "Analyze Performance",
                    description:   "Understand student performance, difficult questions and class results.",)

              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(3, (index) => Container(
              margin: EdgeInsets.symmetric(horizontal: 5),
              height: 8,
              width: currentPage==index?24:8,
              decoration: BoxDecoration(
                color: currentPage==index?
                    AppColors.primary:AppColors.border,
                borderRadius: BorderRadius.circular(20)
              ),
            ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                    vertical: 30,
                    horizontal: 30
                    ),
            child: SizedBox(
              height: 55,
              width: double.infinity,
              child: ElevatedButton(
                  onPressed: (){
                    if(currentPage<2)
                      {
                        pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut
                        );
                      }
                    else
                      {
                       Navigator.pushReplacementNamed(context,
                          AppRoutes.login
                          );

                      }
                  },

                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadiusGeometry.circular(14)
                  )
                ),
                child: Text(currentPage==2?
                'Get Started':
                'next'),
              ),
            ),
          ),
          SizedBox(
            height: 30,
          )


        ],
      )
    );
  }
}

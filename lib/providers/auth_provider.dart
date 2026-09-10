import 'package:assessly/services/api_service.dart';
import 'package:assessly/services/auth_service.dart';
import 'package:flutter/material.dart';

class AuthProvider extends ChangeNotifier{
  bool isLoading=false;
  bool isLoggedIn=false;

 void setLoading(bool value)
  {
    isLoading=value;
    notifyListeners();
  }

 void setLogIn(bool value)
  {
    isLoggedIn=value;
    notifyListeners();
  }
  Future<void> login(String email,String password) async
  {
    try{
      setLoading(true);

      final result= await ApiService.login(email, password);
      final token=result['token'];

      await AuthService.saveToken(token);

      setLogIn(true);
    }finally{
      setLoading(false);
    }
  }
  Future<void> logout() async{
   await AuthService.removeToken();
   setLogIn(false);
  }
  Future<void> register(
      String name,
      String email,
      String password
      ) async
  {
    try{
      setLoading(true);

      await ApiService.register(name, email, password);
    }finally{
      setLoading(false);
    }
  }

}
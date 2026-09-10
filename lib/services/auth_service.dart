import "package:shared_preferences/shared_preferences.dart";

class AuthService {
  static const String tokenkey= 'auth_token';

  static Future<void> saveToken(String token) async
  {
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString(tokenkey, token);
  }

  static Future<String?> getToken() async {
    final prefs=await SharedPreferences.getInstance();
    return prefs.getString(tokenkey);
  }

  static Future<void> removeToken() async{
    final prefs=await SharedPreferences.getInstance();
    await prefs.remove(tokenkey);
  }

  static Future<bool> isLoggedIn() async
  {
    final token= await getToken();

    return token!=null;
  }

}
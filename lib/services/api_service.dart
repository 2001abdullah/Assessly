import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl= 'http://10.0.2.2:5000/api';
  static Future<Map<String,dynamic>> login(
      String email,
      String password
      )  async
  {
    final response=await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {
        'Content-Type' : "application/json"
      },
      body: jsonEncode(
        {
          'email':email,
          'password': password
        }
      ),
    );
    final data=jsonDecode(response.body);
    if(response.statusCode==200)
      {
        return data;
      }
    else
      {
        throw Exception(data["message"]);
      }
  }
  static Future<Map<String,dynamic>> register(
      String name,
      String email,
      String password
      ) async
  {
    final response=await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {
        'Content-Type': "application/json",
      },
      body: jsonEncode({
        'name':name,
        'email':email,
        'password':password
      })
    );
    final data=jsonDecode(response.body);
    if(response.statusCode==201)
      {
        return data;
      }
    else{
      throw Exception(data['message']);
    }
  }

static Future<void> testAuthenticatedConnection(String token) async{
  final response=await http.get(
    Uri.parse('$baseUrl/auth/me'),
    headers: {
      'Authorization': 'Bearer $token'
    }
  );
  print(response.statusCode);
  print(response.body);
}
}
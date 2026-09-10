import 'package:flutter/material.dart';

class AppProvider extends ChangeNotifier{
  bool isworking=false;

  void setLoading(bool value){
    isworking=value;
    notifyListeners();
  }
}
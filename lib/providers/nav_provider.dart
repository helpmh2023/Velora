import 'package:flutter/foundation.dart';

enum AppTab {
  home('Home'),
  movies('Movies'),
  series('Series'),
  search('Search'),
  library('Library'),
  settings('Settings');

  const AppTab(this.label);
  final String label;
}

class NavProvider extends ChangeNotifier {
  AppTab _tab = AppTab.home;
  AppTab get tab => _tab;

  void select(AppTab tab) {
    if (tab == _tab) return;
    _tab = tab;
    notifyListeners();
  }
}

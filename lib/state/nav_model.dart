import 'package:flutter/foundation.dart';

/// The app's main destinations, in bottom-bar order.
enum AppTab { home, code, learn, tools, profile }

/// Lets any screen switch tabs (e.g. a Home card that opens the editor).
class NavModel extends ChangeNotifier {
  AppTab tab = AppTab.home;

  void go(AppTab value) {
    if (value == tab) return;
    tab = value;
    notifyListeners();
  }
}

// Web-specific implementation for localStorage
import 'package:web/web.dart' as web;

void setLocalStorageItem(String key, String value) {
  web.window.localStorage.setItem(key, value);
}

String? getLocalStorageItem(String key) {
  return web.window.localStorage.getItem(key);
}

void removeLocalStorageItem(String key) {
  web.window.localStorage.removeItem(key);
}
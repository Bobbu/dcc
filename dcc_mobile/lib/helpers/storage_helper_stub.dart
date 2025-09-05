// Stub implementation for non-web platforms

void setLocalStorageItem(String key, String value) {
  // No-op on non-web platforms - should use SharedPreferences instead
}

String? getLocalStorageItem(String key) {
  // No-op on non-web platforms - should use SharedPreferences instead
  return null;
}

void removeLocalStorageItem(String key) {
  // No-op on non-web platforms - should use SharedPreferences instead
}
// Stub implementation for non-web platforms
void downloadFile(String content, String filename, String mimeType) {
  // No-op on mobile platforms
  throw UnsupportedError('Download is only available on web platform');
}
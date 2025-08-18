import 'package:web/web.dart' as web;
import 'dart:convert';
import 'dart:js_interop';

void downloadFile(String content, String filename) {
  final bytes = utf8.encode(content);
  final blob = web.Blob([bytes.toJS].toJS);
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = url;
  anchor.style.display = 'none';
  anchor.download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  web.document.body!.removeChild(anchor);
  web.URL.revokeObjectURL(url);
}
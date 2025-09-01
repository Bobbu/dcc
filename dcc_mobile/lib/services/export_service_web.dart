import 'dart:js_interop';
import 'dart:convert';
import 'package:web/web.dart';

void downloadFile(String content, String filename, String mimeType) {
  final bytes = utf8.encode(content);
  final blob = Blob([bytes.toJS].toJS, BlobPropertyBag(type: mimeType));
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  
  document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  URL.revokeObjectURL(url);
}
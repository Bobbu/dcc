import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'auth_service.dart';
import 'logger_service.dart';

// Conditional import for web
import 'export_service_web.dart' if (dart.library.io) 'export_service_stub.dart';

class ExportService {
  static final String _baseUrl = dotenv.env['API_URL'] ?? '';
  
  static Future<Map<String, dynamic>> exportData({
    required String type, // 'quotes' or 'tags'
    required String destination, // 'download', 'clipboard', 's3'
    required String format, // 'json' or 'csv'
  }) async {
    try {
      LoggerService.info('📤 Starting export: type=$type, destination=$destination, format=$format');
      
      if (destination == 's3') {
        // Export to S3 and get the download link
        return await _exportToS3(type: type, format: format);
      } else if (destination == 'clipboard') {
        // Get data and copy to clipboard
        return await _exportToClipboard(type: type, format: format);
      } else if (destination == 'download' && kIsWeb) {
        // Download directly on web
        return await _exportToDownload(type: type, format: format);
      } else if (destination == 'download' && !kIsWeb) {
        // Mobile platforms don't support direct download, redirect to S3
        LoggerService.info('📱 Mobile download redirected to S3 export');
        return await _exportToS3(type: type, format: format);
      } else {
        throw Exception('Invalid export destination: $destination');
      }
    } catch (e) {
      LoggerService.error('❌ Export failed: $e', error: e);
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> _exportToS3({
    required String type,
    required String format,
  }) async {
    try {
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        throw Exception('Not authenticated');
      }
      
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/export-s3'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'type': type,
          'format': format,
          'destination': 's3',
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        LoggerService.info('✅ S3 export successful: ${data['download_url']}');
        
        return {
          'success': true,
          'downloadUrl': data['download_url'],
          's3Key': data['s3_key'],
          'expiresIn': data['expires_in'],
          'statistics': data['statistics'],
        };
      } else {
        throw Exception('Export failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      LoggerService.error('❌ S3 export error: $e', error: e);
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> _exportToClipboard({
    required String type,
    required String format,
  }) async {
    try {
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        throw Exception('Not authenticated');
      }
      
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/export-s3'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'type': type,
          'format': format,
          'destination': 'clipboard',
        }),
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final exportData = responseData['data'];
        
        String clipboardContent;
        if (format == 'json') {
          clipboardContent = const JsonEncoder.withIndent('  ').convert(exportData);
        } else {
          // Convert to CSV format
          clipboardContent = _convertToCSV(exportData, type);
        }
        
        await Clipboard.setData(ClipboardData(text: clipboardContent));
        LoggerService.info('✅ Data copied to clipboard');
        
        return {
          'success': true,
          'message': 'Data copied to clipboard',
          'statistics': responseData['statistics'],
        };
      } else {
        throw Exception('Export failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      LoggerService.error('❌ Clipboard export error: $e', error: e);
      rethrow;
    }
  }
  
  static Future<Map<String, dynamic>> _exportToDownload({
    required String type,
    required String format,
  }) async {
    try {
      if (!kIsWeb) {
        throw Exception('Download is only available on web platform');
      }
      
      final idToken = await AuthService.getIdToken();
      if (idToken == null) {
        throw Exception('Not authenticated');
      }
      
      final response = await http.post(
        Uri.parse('$_baseUrl/admin/export-s3'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'type': type,
          'format': format,
          'destination': 'download',
        }),
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final exportData = responseData['data'];
        
        String content;
        String mimeType;
        String extension;
        
        if (format == 'json') {
          content = const JsonEncoder.withIndent('  ').convert(exportData);
          mimeType = 'application/json';
          extension = 'json';
        } else {
          content = _convertToCSV(exportData, type);
          mimeType = 'text/csv';
          extension = 'csv';
        }
        
        // Create and download file for web
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
        final filename = '${type}_export_$timestamp.$extension';
        
        _downloadFile(content, filename, mimeType);
        
        LoggerService.info('✅ File downloaded: $filename');
        
        return {
          'success': true,
          'message': 'File downloaded successfully',
          'filename': filename,
          'statistics': responseData['statistics'],
        };
      } else {
        throw Exception('Export failed: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      LoggerService.error('❌ Download export error: $e', error: e);
      rethrow;
    }
  }
  
  static String _convertToCSV(Map<String, dynamic> data, String type) {
    final StringBuffer csv = StringBuffer();
    
    if (type == 'quotes' && data['quotes'] != null) {
      // CSV header
      csv.writeln('ID,Quote,Author,Tags,Created Date,Created By');
      
      // CSV rows
      for (final quote in data['quotes']) {
        final id = _escapeCsvField(quote['id'] ?? '');
        final quoteText = _escapeCsvField(quote['quote'] ?? '');
        final author = _escapeCsvField(quote['author'] ?? '');
        final tags = _escapeCsvField((quote['tags'] as List?)?.join(', ') ?? '');
        final createdDate = _escapeCsvField(quote['created_date'] ?? '');
        final createdBy = _escapeCsvField(quote['created_by'] ?? '');
        
        csv.writeln('$id,$quoteText,$author,$tags,$createdDate,$createdBy');
      }
    } else if (type == 'tags' && data['tags'] != null) {
      // CSV header
      csv.writeln('Tag,Usage Count');
      
      // CSV rows
      for (final tag in data['tags']) {
        final tagName = _escapeCsvField(tag['name'] ?? tag);
        final count = tag['count'] ?? '';
        csv.writeln('$tagName,$count');
      }
    }
    
    return csv.toString();
  }
  
  static String _escapeCsvField(String field) {
    if (field.contains(',') || field.contains('"') || field.contains('\n')) {
      return '"${field.replaceAll('"', '""')}"';
    }
    return field;
  }
  
  static void _downloadFile(String content, String filename, String mimeType) {
    if (kIsWeb) {
      downloadFile(content, filename, mimeType);
    } else {
      throw UnsupportedError('Download is only available on web platform');
    }
  }
  
  static Future<void> shareExportLink(String url) async {
    try {
      if (!kIsWeb) {
        // Use share_plus for mobile platforms
        await Share.share(
          'Quote Me Export: $url\n\nThis link expires in 48 hours.',
          subject: 'Quote Me Database Export',
        );
      } else {
        // For web, copy to clipboard
        await Clipboard.setData(ClipboardData(text: url));
      }
      LoggerService.info('✅ Export link shared');
    } catch (e) {
      LoggerService.error('❌ Failed to share link: $e', error: e);
      rethrow;
    }
  }
  
  static Future<void> openExportLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        LoggerService.info('✅ Export link opened');
      } else {
        throw Exception('Could not open URL: $url');
      }
    } catch (e) {
      LoggerService.error('❌ Failed to open link: $e', error: e);
      rethrow;
    }
  }
}
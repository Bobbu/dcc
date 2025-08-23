import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:share_plus/share_plus.dart';
import 'logger_service.dart';

class ShareService {
  static const String _webAppUrl = 'https://quote-me.anystupididea.com';

  static Future<void> shareQuote({
    required BuildContext context,
    required String quote,
    required String author,
    required String quoteId,
    List<String>? tags,
  }) async {
    LoggerService.debug('🔄 Starting share process...');
    LoggerService.debug('  Platform: ${kIsWeb ? 'Web' : Platform.operatingSystem}');
    if (!kIsWeb) {
      LoggerService.debug('  Platform version: ${Platform.operatingSystemVersion}');
    }
    
    final shareText = StringBuffer();
    
    shareText.writeln('"$quote"');
    shareText.writeln('- $author');
    
    if (tags != null && tags.isNotEmpty) {
      shareText.writeln('Tags: ${tags.join(", ")}');
    }
    
    shareText.writeln();
    shareText.writeln('Shared from Quote Me');
    shareText.writeln();
    shareText.writeln('View this quote: $_webAppUrl/quote/$quoteId');
    
    try {
      await Share.share(
        shareText.toString(),
        subject: 'Quote by $author',
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100), // Required for iPad popover positioning
      );
      LoggerService.debug('✅ Share completed successfully');
    } catch (e) {
      LoggerService.error('❌ Share error details');
      LoggerService.error('  Error type: ${e.runtimeType}');
      LoggerService.error('  Error message: $e');
      LoggerService.error('  Stack trace: ${StackTrace.current}');
      
      await _handleShareError(context, shareText.toString(), e);
    }
  }

  static Future<void> _handleShareError(
    BuildContext context,
    String shareText,
    dynamic error,
  ) async {
    if (kIsWeb) {
      // Web fallback: try clipboard
      try {
        await Clipboard.setData(ClipboardData(text: shareText));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Quote copied to clipboard!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (clipboardError) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to share quote. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      // Native device fallback: try clipboard then show error
      try {
        await Clipboard.setData(ClipboardData(text: shareText));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Share failed. Quote copied to clipboard instead.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (clipboardError) {
        LoggerService.error('❌ Clipboard error', error: clipboardError);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to share quote. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
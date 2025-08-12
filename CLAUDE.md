# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a dual-component project consisting of:
1. **AWS API (dcc_api)** - Python Lambda function behind API Gateway serving random quotes
2. **Flutter iOS App (dcc_mobile)** - Single-screen mobile app that consumes the API

The architecture follows a simple client-server pattern where the Flutter app makes HTTP requests to the AWS API to fetch and display random quotes.

## Development Commands

### AWS API Development
```bash
# Navigate to AWS directory
cd aws

# Deploy API to AWS (requires AWS CLI and SAM CLI configured)
./deploy.sh

# Note the API Key from the deployment output for testing
# Test deployed API with API key
cd ../tests
./test_api.sh
```

### Flutter App Development
```bash
# Navigate to Flutter app
cd dcc_mobile

# Install dependencies
flutter pub get

# Run on iOS simulator
flutter run

# Run tests
flutter test
```

### Project Testing
```bash
# Test API endpoint (from project root)
./tests/test_api.sh

# Open iOS Simulator
open -a Simulator
```

## Architecture Details

### API Component (`aws/`)
- **SAM Template**: `template.yaml` defines API Gateway + Lambda infrastructure with security features
- **Lambda Handler**: `lambda/quote_handler.py` contains 15 hardcoded quotes with authors
- **Response Format**: JSON with `quote` and `author` fields
- **CORS**: Configured for mobile app access with wildcard origins
- **Security**: API key authentication required, rate limiting enabled
- **Rate Limits**: 1 req/sec sustained, 5 req/sec burst, 1,000 req/day
- **Monitoring**: CloudWatch metrics and logging enabled

### Flutter App (`dcc_mobile/`)
- **Main Screen**: `lib/screens/quote_screen.dart` with responsive layout for all orientations
- **Settings Screen**: `lib/screens/settings_screen.dart` for comprehensive user preferences
- **Project Structure**: Refactored with clean separation - screens in dedicated folder
- **HTTP Client**: Uses `http: ^1.1.0` package for API calls with rate limit handling
- **Text-to-Speech**: Uses `flutter_tts: ^4.0.2` package with voice selection and testing
- **Settings Persistence**: Uses `shared_preferences: ^2.2.2` for local storage
- **State Management**: Simple setState() pattern for quote display, TTS, and settings
- **Error Handling**: User-friendly rate limit messages, network errors, and loading states
- **API URL**: Hardcoded in `_QuoteScreenState.apiUrl` constant
- **Theme**: Corporate maroon (#800000) and gold (#FFD700) color scheme
- **Audio Features**: 
  - Toggleable automatic quote reading with visual state indicators
  - Voice selection from all available system TTS voices
  - Voice testing capability with "try before you select"
  - Smart audio controls: speaker icon (enabled), speaker-slash (disabled), stop icon (speaking)
- **Category Selection**: UI for quote categories (Sports, Education, Science, Motivation, Funny, Persistence, Business)
- **Responsive Design**: Perfect centering in both portrait and landscape orientations
- **Visual Polish**: Smooth orientation handling, no overflow issues, professional layout

### Key Integration Points
1. API URL must be updated in `dcc_mobile/lib/main.dart` after AWS deployment
2. API Key must be included in Flutter app HTTP requests (`x-api-key` header)
3. API returns JSON structure that Flutter app expects (`quote` and `author` fields)
4. CORS headers in Lambda response enable cross-origin requests from mobile app
5. Rate limiting may require client-side retry logic for burst scenarios
6. Settings are persisted locally using SharedPreferences
7. Quote categories are UI-ready but await server-side implementation

## Current API Endpoint
The deployed API endpoint is: `https://guhpxakbu6.execute-api.us-east-1.amazonaws.com/prod/quote`
**Note**: API Key required for all requests

## Important Notes
- Flutter app is iOS-focused (though cross-platform capable)
- No database - quotes are hardcoded in Lambda function
- **API Security**: API key authentication and rate limiting implemented
- **Rate Limits**: 1 req/sec sustained, 5 burst, 1,000/day with friendly user messaging
- Test script validates API responses, basic functionality, and rate limiting
- **Advanced Audio System**:
  - Text-to-Speech works in iOS simulator and real devices (requires audio output)
  - Voice selection from all available system voices (typically 20-50+ voices per device)
  - Voice testing with sample phrases before selection
  - Visual audio state indicators: 🔊 (enabled), 🔇 (disabled), ⏹️ (speaking)
  - Smart audio interruption: new quotes stop previous audio playback
- **Enhanced Settings Features**:
  - Audio playback toggle with persistent state
  - Voice selection with real-time testing capability
  - Quote categories selection (UI complete, server implementation pending)
  - All settings persist between app launches using SharedPreferences
- **Responsive Design**: Perfect centering and layout in all device orientations
- Corporate branding implemented throughout with maroon and gold color scheme
- **Flutter Integration**: Must update HTTP client to include `x-api-key` header
- **Code Organization**: Clean architecture with screens separated into dedicated files
- **Future Enhancement**: Server-side category filtering will respect user preferences
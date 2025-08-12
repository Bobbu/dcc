# DCC Quote App

A simple project consisting of an AWS API and Flutter iOS app for displaying random quotes.

## Architecture

### AWS API (dcc_api)
- **API Gateway**: Single endpoint `/quote` (GET)
- **Lambda Function**: Python-based function that returns random quotes with authors
- **Response Format**: JSON containing quote text and author attribution

### Flutter iOS App
- **Main Screen**: Responsive quote display in company colors (maroon and gold theme)
- **Get Quote Button**: Fetches and displays a new random quote with smart audio handling
- **Advanced Text-to-Speech**: 
  - Automatically reads quotes aloud when loaded (if enabled)
  - Voice selection from all available system TTS voices
  - Visual audio state indicators (speaker, speaker-slash, stop icons)
  - Smart audio interruption prevents overlapping speech
- **Comprehensive Settings Screen**: Accessible via gear icon in app bar
  - **Audio Toggle**: Enable/disable automatic quote reading with persistent state
  - **Voice Selection**: Choose and test voices with "try before you select" feature
  - **Category Selection**: Choose quote categories (Sports, Education, Science, Motivation, Funny, Persistence, Business)
- **Responsive Design**: Perfect layout and centering in both portrait and landscape orientations
- **Behavior**: Each button press replaces the previous quote and reads it aloud (if audio enabled)

## Project Structure

```
dcc/
├── README.md
├── aws/                    # AWS infrastructure and Lambda code
│   ├── template.yaml       # SAM template with security features
│   ├── lambda/
│   │   └── quote_handler.py
│   └── requirements.txt
├── dcc_mobile/             # Flutter iOS application
│   ├── lib/
│   │   ├── main.dart       # App entry point and theme
│   │   └── screens/        # Screen widgets
│   │       ├── quote_screen.dart
│   │       └── settings_screen.dart
│   ├── ios/
│   ├── pubspec.yaml
│   └── ...
└── tests/
    └── test_api.sh         # API testing with rate limit validation
```

## Setup Instructions

### Prerequisites
- AWS CLI configured with appropriate permissions
- SAM CLI installed
- Flutter SDK installed
- Xcode (for iOS development)
- iOS device or simulator with audio capability for text-to-speech features

### AWS API Deployment
1. Navigate to the `aws` directory
2. Run the deployment script: `./deploy.sh`
3. Follow the SAM guided deployment prompts
4. Note the API endpoint URL and API Key from the output

### Flutter App Setup
1. Navigate to the `dcc_mobile` directory
2. Update the `apiUrl` constant in `lib/main.dart` with your API Gateway URL
3. Add the API key to your HTTP requests (see API Usage section below)
4. Install dependencies: `flutter pub get`
5. Run on iOS simulator: `flutter run`

## Development Notes

### Testing the API
You can test the deployed API directly with your API key:
```bash
curl -H "x-api-key: YOUR_API_KEY" https://your-api-id.execute-api.region.amazonaws.com/prod/quote
```

### Flutter Development
- **Enhanced Error Handling**: User-friendly messages for network issues and rate limiting
- **Responsive Design**: Perfect layout and centering in all device orientations  
- **Loading States**: Smooth loading indicators during API calls
- **Elegant UI**: Quotes displayed in beautiful card format with maroon and gold styling
- **Advanced Audio System**:
  - Text-to-Speech functionality with voice selection capabilities
  - Visual state indicators: 🔊 (audio enabled), 🔇 (audio disabled), ⏹️ (currently speaking)
  - Smart audio interruption prevents overlapping speech
  - Voice testing feature allows users to preview voices before selection
- **Comprehensive Settings Screen**:
  - Audio playback toggle with persistent storage
  - Voice selection from all available system TTS voices (typically 20-50+ voices)
  - Quote category selection (UI ready for future API implementation)  
  - All settings persist between app sessions using SharedPreferences
- **Professional Polish**:
  - Clean code architecture with screens in dedicated files
  - Smooth orientation handling without overflow issues
  - Corporate branding with maroon (#800000) and gold (#FFD700) color scheme
  - Rate limit handling with friendly user messaging

## API Usage

### Endpoint Details
- **URL**: `https://[api-id].execute-api.[region].amazonaws.com/prod/quote`
- **Method**: GET
- **Authentication**: API Key required in `x-api-key` header
- **Rate Limits**: 
  - 1 request/second (sustained)
  - 5 requests/second (burst)
  - 1,000 requests/day
- **Response**:
  ```json
  {
    "quote": "The only way to do great work is to love what you do.",
    "author": "Steve Jobs"
  }
  ```

### Security Features
- **API Key Authentication**: All requests must include a valid API key
- **Rate Limiting**: Prevents abuse with per-second, burst, and daily limits
- **Usage Monitoring**: CloudWatch metrics and logging enabled
- **CORS Configuration**: Allows cross-origin requests for Flutter app integration

### Getting Your API Key
After deployment, the API key will be displayed in the CloudFormation outputs. You can also retrieve it from:
- AWS Console → API Gateway → API Keys → dcc-api-key
- AWS CLI: `aws apigateway get-api-keys --include-values`
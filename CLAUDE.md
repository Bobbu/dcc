# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive quote management system with enterprise-grade features consisting of:
1. **AWS API Backend** - Secure, scalable API with authentication and database storage
2. **Flutter Mobile App** - Feature-rich iOS app with advanced audio and admin capabilities  
3. **Admin Management System** - Complete CRUD interface for quote management

The architecture follows modern cloud-native patterns with JWT authentication, DynamoDB storage, API Gateway security, and mobile-first design principles.

## Development Commands

### AWS API Development
```bash
# Navigate to AWS directory
cd aws

# Deploy complete stack (API Gateway, Lambda, DynamoDB, Cognito)
sam build && sam deploy

# Update environment files with latest AWS outputs
cd ..
./update_env.sh

# Test public API endpoints (includes dynamic tags endpoint)
cd tests
./test_api.sh

# Test admin API with comprehensive regression tests
./test_admin_api.sh

# Migrate quotes to DynamoDB with tags metadata initialization (one-time setup)
python3 migrate_quotes.py
```

### Flutter App Development
```bash
# Navigate to Flutter app
cd dcc_mobile

# Install dependencies (includes AWS Amplify for authentication)
flutter pub get

# Run on iOS simulator (includes admin functionality)
flutter run

# Run tests
flutter test
```

### Project Testing
```bash
# Test public API endpoint with rate limiting (from project root)
./tests/test_api.sh

# Test admin API endpoints with comprehensive regression testing
# (creates temporary admin user, tests all CRUD operations, cleans up)
./tests/test_admin_api.sh

# Test tag cleanup functionality specifically
# (creates temp admin user, tests unused tag detection and cleanup)
python3 tests/test_tag_cleanup.py

# Manual admin authentication for debugging:
aws cognito-idp admin-initiate-auth \
  --user-pool-id us-east-1_ecyuILBAu \
  --client-id 2idvhvlhgbheglr0hptel5j55 \
  --auth-flow ADMIN_NO_SRP_AUTH \
  --auth-parameters USERNAME=admin@dcc.com,PASSWORD=AdminPass123!

# Test dynamic tags endpoint
curl -H "X-Api-Key: ZRHZ2Nepyi9N8hbe9730y3UGnDSwOlGPars7blN9" \
  "https://dcc.anystupididea.com/tags"

# Open iOS Simulator for mobile testing
open -a Simulator
```

## Architecture Details

### API Component (`aws/`)
- **SAM Template**: `template.yaml` defines complete serverless infrastructure
  - API Gateway with dual authentication (API Key + Cognito JWT)
  - Lambda functions for public quotes and admin CRUD operations
  - DynamoDB table with Global Secondary Index for multi-tag querying
  - Cognito User Pool with admin group for role-based access
  - Custom domain support with SSL certificates
- **Lambda Functions**:
  - `quote_handler.py`: Public quote API with tag filtering + dynamic tags endpoint (GET /tags)
  - `admin_handler.py`: Admin CRUD operations with tags metadata management
- **Database**: DynamoDB with tags metadata caching for zero-scan performance
  - TAGS_METADATA record maintains complete tag list for O(1) retrieval
  - Admin operations automatically update tags metadata
  - No database scanning required for tag list retrieval
- **Response Format**: JSON with `quote`, `author`, `tags`, and `id` fields
- **Security Features**:
  - API Key authentication for public endpoints (rate limited)
  - Cognito JWT authentication for admin endpoints (no rate limits)
  - Admin group membership verification
  - CORS configured for mobile app access
- **Rate Limits**: 1 req/sec sustained, 5 req/sec burst, 1,000 req/day for public API
- **Monitoring**: CloudWatch metrics, logging, and distributed tracing enabled

### Flutter App (`dcc_mobile/`)
- **Architecture**: Clean separation with screens in dedicated folders and services
- **Screen Components**:
  - `quote_screen.dart`: Main app with responsive layout and category filtering
  - `settings_screen.dart`: Dynamic tag loading with voice testing and server synchronization
  - `admin_login_screen.dart`: Secure admin authentication with branded UI
  - `admin_dashboard_screen.dart`: Full quote management interface with CRUD operations
- **Authentication Service**: `lib/services/auth_service.dart`
  - AWS Amplify Cognito integration for secure authentication
  - Admin group membership verification
  - JWT token management for API calls
  - Persistent authentication state management
- **Dependencies**:
  - `http: ^1.1.0`: API communication with authentication headers
  - `flutter_tts: ^4.0.2`: Advanced text-to-speech with voice selection
  - `shared_preferences: ^2.2.2`: Local settings persistence
  - `flutter_dotenv: ^5.1.0`: Environment variable management
  - `amplify_flutter: ^2.0.0`: AWS Amplify core functionality
  - `amplify_auth_cognito: ^2.0.0`: Cognito authentication integration
- **State Management**: setState() pattern with service-layer abstraction
- **Error Handling**: Comprehensive error handling for network, auth, and API failures
- **Theme**: Professional corporate branding with maroon (#800000) and gold (#FFD700)
- **Advanced Features**:
  - **Audio System**: Voice selection, testing, and smart interruption controls
  - **Dynamic Tag Filtering**: Real-time tag loading from server with zero-scan performance
  - **Admin Management**: Complete quote CRUD with real-time updates
  - **Tag Cleanup System**: Automated removal of unused tags from metadata with confirmation dialog
  - **Responsive Design**: Perfect layout in all orientations with no overflow
  - **Security Integration**: Seamless admin access with role-based permissions

### Key Integration Points
1. **Environment Management**: Automated via `./update_env.sh` script that syncs AWS outputs to `.env` files
2. **Authentication Flow**: 
   - Public API: `x-api-key` header for rate-limited quote access
   - Admin API: `Authorization: Bearer {IdToken}` for full CRUD operations
3. **Data Flow**: DynamoDB → Lambda → API Gateway → Flutter with real-time tag filtering
4. **Security Model**: Dual-layer with API keys for public access and JWT for admin operations
5. **State Synchronization**: Admin changes immediately reflected in public API responses
6. **Error Handling**: Graceful degradation with user-friendly messages across all failure modes
7. **Custom Domain**: SSL-secured custom domain (dcc.anystupididea.com) with CloudFront distribution

## Current API Endpoints

### Public API (Rate Limited)
**Quote Retrieval:**
- **Custom Domain**: `https://dcc.anystupididea.com/quote`
- **Direct URL**: `https://iasj16a8jl.execute-api.us-east-1.amazonaws.com/prod/quote`
- **Authentication**: API Key required (`x-api-key` header)
- **Features**: Tag filtering via `?tags=Motivation,Business` query parameter

**Dynamic Tags Retrieval:**
- **Custom Domain**: `https://dcc.anystupididea.com/tags`
- **Direct URL**: `https://iasj16a8jl.execute-api.us-east-1.amazonaws.com/prod/tags`
- **Authentication**: API Key required (`x-api-key` header)
- **Features**: Returns all available tags from database (zero-scan performance)
- **Response**: `{"tags": ["All", "Action", "Business", ...], "count": 23}`

### Admin API (JWT Protected)
- **Base URL**: `https://dcc.anystupididea.com/admin/`
- **Authentication**: Cognito IdToken required (`Authorization: Bearer {token}`)
- **Quote Management Endpoints**:
  - `GET /admin/quotes` - List all quotes with metadata
  - `POST /admin/quotes` - Create new quote (auto-updates tags metadata)
  - `PUT /admin/quotes/{id}` - Update existing quote (auto-updates tags metadata)
  - `DELETE /admin/quotes/{id}` - Delete quote
- **Tag Management Endpoints**:
  - `GET /admin/tags` - Get all available tags from metadata
  - `DELETE /admin/tags/unused` - Clean up unused tags (removes tags not used by any quotes)
- **Tags Metadata Management**: All CRUD operations automatically maintain tags metadata cache with cleanup capabilities

### Admin Credentials
- **Email**: `admin@dcc.com`
- **Password**: `AdminPass123!`
- **User Pool**: `us-east-1_ecyuILBAu`
- **Client ID**: `2idvhvlhgbheglr0hptel5j55`

## Important Notes

### Production Features
- **Database**: DynamoDB with 20+ curated quotes and dynamic tag system (zero-scan performance)
- **Authentication**: Enterprise-grade Cognito integration with role-based access control
- **Security**: Dual-layer API security (API keys + JWT) with admin group verification
- **Performance**: Rate limiting, CloudWatch monitoring, tags metadata caching, custom domain with CDN
- **Mobile Platform**: iOS-focused but cross-platform capable Flutter implementation with real-time tag synchronization

### Advanced Capabilities
- **Audio System**: Professional TTS with 20-50+ voice options, testing, and smart controls
- **Admin Management**: Complete quote lifecycle management with real-time updates
- **Dynamic Tag System**: Real-time tag loading and filtering with zero-scan database performance
- **Tags Metadata Caching**: Efficient O(1) tag retrieval without database scanning
- **Automated Tag Cleanup**: Admin can remove unused tags with one-click cleanup and detailed reporting
- **Responsive Design**: Perfect layout across all device orientations and screen sizes
- **Error Handling**: Comprehensive error management with user-friendly messaging
- **State Management**: Persistent settings and authentication across app sessions

### Development Standards
- **Code Architecture**: Clean separation of concerns with service layer patterns
- **Environment Management**: Automated environment synchronization with AWS outputs
- **Testing**: Comprehensive API testing with rate limit validation and admin regression tests with temporary user management
- **Documentation**: Complete technical documentation with usage examples
- **Security**: No hardcoded credentials, environment-based configuration management

### Future Enhancements
- Additional authentication providers (Google, Apple Sign-In)
- Quote import/export functionality  
- Advanced analytics and usage metrics
- Push notifications for new quotes
- Offline mode with local caching
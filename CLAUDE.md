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

# Test individual tag management functionality
# (creates temp admin user, tests tag CRUD operations with data integrity)
python3 tests/test_tag_editor.py

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
  - `quote_handler.py`: Public quote API with tag validation, filtering + dynamic tags endpoint (GET /tags)
    - Validates requested tags against metadata
    - Gracefully handles non-existent tags
    - Falls back to "All" if no valid tags found
  - `admin_handler.py`: Admin CRUD operations with comprehensive tags management and data integrity
    - Tag rename/delete operations automatically update all affected quotes
    - Maintains tags metadata cache for O(1) retrieval
- **Database**: DynamoDB with tags metadata caching for zero-scan performance
  - TAGS_METADATA record maintains complete tag list for O(1) retrieval
  - Admin operations automatically update tags metadata with full data integrity
  - Individual tag management with automatic quote synchronization
  - Metadata records properly filtered from quote listings
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
  - `tags_editor_screen.dart`: Dedicated tag management interface with individual tag CRUD operations
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
- **Error Handling**: Comprehensive error handling with automatic retry logic for 500 errors
- **Theme**: Professional corporate branding with maroon (#800000) and gold (#FFD700)
- **Advanced Features**:
  - **Audio System**: Voice selection, testing, smart interruption controls, and simulator compatibility
  - **Dynamic Tag Filtering**: Real-time tag loading with 3-tag minimum for variety
  - **Admin Management**: Complete quote CRUD with real-time updates and advanced sorting
  - **Quote Sorting**: AppBar toggle buttons for sorting by Quote, Author, or Created Date (ascending/descending)
  - **Duplicate Management**: Smart duplicate detection and cleanup with intelligent selection
  - **Tag Management System**: Dedicated Tags Editor with individual tag CRUD operations
  - **Import System**: Copy/paste TSV import from Google Sheets with real-time progress tracking
  - **Progress Tracking**: Batch processing with visual progress bar and status updates
  - **Tag Cleanup System**: Automated removal of unused tags from metadata with confirmation dialog
  - **Data Integrity**: Automatic quote synchronization when tags are renamed or deleted
  - **Responsive Design**: Perfect layout in all orientations with no overflow
  - **Security Integration**: Seamless admin access with role-based permissions
  - **Resilience Features**: Automatic retry with exponential backoff for server errors

### Import System
The admin dashboard includes a powerful copy/paste import feature for Google Sheets data with real-time progress tracking:

**Core Features**:
- **TSV Parser**: Handles tab-separated values from Google Sheets copy/paste
- **Smart Header Detection**: Automatically skips header rows containing "Nugget" and "Source"
- **Column Mapping**: 
  - Column 1: Nugget (Quote text)
  - Column 2: Source (Author)
  - Columns 3-7: Tag1, Tag2, Tag3, Tag4, Tag5
- **Live Preview**: Shows first 3 parsed quotes before importing
- **Batch Processing**: Processes quotes in batches of 5 with 1.1-second delays to prevent rate limiting
- **Real-Time Progress**: Visual progress bar and status updates during long imports
- **Progress Tracking**: Shows "Importing 25 of 100..." with batch status updates
- **Import Feedback**: Shows success/failure counts after import with retry functionality
- **Error Handling**: Continues import even if individual quotes fail
- **Rate Limiting Protection**: Built-in delays and batch processing prevent API overload

**Progress Display**:
- **Visual Progress Bar**: Linear progress indicator with percentage completion
- **Live Counter**: "25 of 100 quotes" style progress tracking
- **Status Messages**: Real-time updates like "Processing batch 3 of 20..." and "Importing 25 of 100..."
- **Batch Visibility**: Clear indication of processing stages and completion status

**Access Method**: Admin Dashboard → Menu → "Import Quotes"

### Admin Dashboard Sorting System
The admin dashboard provides comprehensive sorting capabilities for efficient quote management:

**Sorting Features**:
- **Three Sort Fields**: Quote text, Author name, and Created Date sorting options
- **AppBar Integration**: Compact toggle buttons directly in the app bar for quick access
- **Bi-Directional Sorting**: Click once for ascending, click again for descending order
- **Visual Indicators**: Arrow icons show current sort direction, expand icons show inactive fields
- **Smart Tooltips**: Hover text explains each button's function and current sort state
- **Case-Insensitive**: Text sorting ignores case for better alphabetical organization
- **Persistent State**: Sort preferences maintained during admin session

**Sorting Options**:
- **Quote Text**: Alphabetical sorting (A-Z / Z-A) with case-insensitive comparison
- **Author Name**: Alphabetical author sorting (A-Z / Z-A) with case-insensitive comparison  
- **Created Date**: Chronological sorting (Newest First / Oldest First) by timestamp

**Default Behavior**: Starts with Created Date sorting, newest quotes first (descending order)

### Duplicate Management System
The admin dashboard includes intelligent duplicate detection and cleanup functionality:

**Core Features**:
- **Smart Detection**: Identifies duplicates by matching quote text and author exactly (case-insensitive)
- **Tag Agnostic**: Ignores tag differences when determining duplicates, as requested
- **Intelligent Selection**: Pre-selects newer duplicates for deletion while preserving the oldest quote
- **Batch Operations**: Safely deletes multiple duplicates with rate limiting protection
- **User Control**: Full control over which quotes to keep or delete with checkbox interface

**Duplicate Preview Dialog**:
- **Group Summary**: Shows total quotes found and deletion count
- **Detailed View**: Displays each duplicate group with quote preview and metadata
- **Creation Timestamps**: Shows creation dates to help identify the original quote
- **Tag Information**: Displays tags for each duplicate to assist decision-making
- **Color Coding**: Green highlights indicate the recommended quote to keep (oldest)
- **Safe Defaults**: Automatically selects newer duplicates for deletion, keeping originals

**Cleanup Process**:
- **Batch Deletion**: Processes selected quotes in batches with error handling
- **Progress Feedback**: Shows detailed success/failure counts after cleanup
- **Rate Limiting**: Includes 300ms delays between deletions to prevent API overload
- **Auto Refresh**: Automatically refreshes quote list to show results

**Access Method**: Admin Dashboard → Menu → "Clean Duplicate Quotes"

### Tags Editor System
The dedicated Tags Editor provides comprehensive tag management capabilities separate from quote management:

**Core Features**:
- **Individual Tag CRUD**: Add, rename, delete individual tags with validation
- **Data Integrity**: Tag operations automatically update all affected quotes
- **Duplicate Prevention**: Cannot add tags that already exist
- **Smart Synchronization**: Renaming tags updates all quotes using that tag
- **Safe Deletion**: Deleting tags removes them from all quotes using them
- **User-Friendly Interface**: Professional UI with confirmation dialogs
- **Real-time Feedback**: Shows how many quotes were affected by each operation

**Access Methods**:
- **Primary Access**: Admin Dashboard → Menu → "Manage Tags"
- **Direct Navigation**: Dedicated Tags Editor screen with full functionality
- **Integrated Cleanup**: Access to unused tag cleanup from within the editor

**Technical Implementation**:
- **Backend Validation**: Comprehensive server-side validation and error handling  
- **Quote Synchronization**: Automatic scanning and updating of affected quotes
- **Metadata Consistency**: Tags metadata cache updated with every operation
- **Error Recovery**: Graceful handling of network issues and API failures
- **State Management**: Real-time UI updates reflecting server changes

**Security & Data Integrity**:
- **Admin Authentication**: Full JWT authentication and group membership verification
- **Transaction Safety**: Each operation maintains database consistency
- **Audit Trail**: All tag changes logged with timestamps and user information
- **Rollback Protection**: Confirmation dialogs prevent accidental destructive operations

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
  - `POST /admin/tags` - Add new individual tag to metadata
  - `PUT /admin/tags/{tag}` - Update/rename tag (automatically updates all quotes using the tag)
  - `DELETE /admin/tags/{tag}` - Delete individual tag (removes from all quotes using it)
  - `DELETE /admin/tags/unused` - Clean up unused tags (removes tags not used by any quotes)
- **Tags Metadata Management**: All CRUD operations automatically maintain tags metadata cache with full data integrity
- **Quote Synchronization**: Tag rename/delete operations automatically update all affected quotes

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
- **Admin Management**: Complete quote lifecycle management with real-time updates and advanced sorting
- **Quote Sorting**: Three-field sorting (Quote, Author, Date) with ascending/descending toggles in AppBar
- **Duplicate Management**: Intelligent duplicate detection with smart cleanup and preservation logic
- **Progress Tracking**: Real-time batch processing with visual progress bars for long operations
- **Dynamic Tag System**: Real-time tag loading and filtering with zero-scan database performance
- **Tags Metadata Caching**: Efficient O(1) tag retrieval without database scanning
- **Individual Tag Management**: Dedicated Tags Editor for adding, renaming, and deleting individual tags
- **Data Integrity Enforcement**: Tag operations automatically synchronize with all affected quotes
- **Automated Tag Cleanup**: Admin can remove unused tags with one-click cleanup and detailed reporting
- **Import Progress**: Batch processing with real-time status updates and visual feedback
- **Rate Limiting Protection**: Built-in delays and batch processing prevent API overload
- **Metadata Filtering**: TAGS_METADATA records are properly filtered from quote listings
- **Responsive Design**: Perfect layout across all device orientations and screen sizes
- **Error Handling**: Comprehensive error management with user-friendly messaging
- **State Management**: Persistent settings and authentication across app sessions

### Resilience & Error Handling
- **Automatic Retry Logic**: 500 errors trigger up to 3 retries with exponential backoff (500ms, 1000ms, 1500ms)
- **Tag Validation**: Backend validates all requested tags and gracefully handles non-existent ones
- **TTS State Management**: Enhanced audio controls work properly in simulator with timeout fallbacks
- **Network Error Recovery**: Automatic retry for network failures with user feedback
- **Tag Selection Validation**: Requires minimum 3 tags when not using "All" to ensure quote variety
- **Substring Safety**: Handles quotes of any length without crashes in logging
- **Rate Limit Messaging**: Clear, friendly messages when API rate limits are exceeded
- **Server Error Messaging**: User-friendly "Server issue, retrying..." during automatic retries

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
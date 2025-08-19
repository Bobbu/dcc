# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Quote Me" is a comprehensive quote management system with enterprise-grade features consisting of:
1. **AWS API Backend** - Secure, scalable API with authentication, CORS support, and database storage
2. **Flutter Mobile & Web Apps** - Cross-platform applications with modern indigo theme and advanced capabilities  
3. **Admin Management System** - Complete CRUD interface with tag filtering and quote management
4. **Web Deployment Infrastructure** - Automated deployment with CloudFront CDN, S3 hosting, and SSL certificates

The architecture follows modern cloud-native patterns with JWT authentication, DynamoDB storage, API Gateway security with CORS, CloudFront distribution, and cross-platform design principles with a professional indigo color scheme.

## Development Commands

### AWS API Development

#### Standard Deployment
```bash
# Navigate to AWS directory
cd aws

# Deploy complete stack (API Gateway, Lambda, DynamoDB, Cognito, OpenAI)
# Requires .env.deployment file with OpenAI API key
source .env.deployment && sam build && sam deploy --parameter-overrides OpenAIApiKey="$OPENAI_API_KEY"

# Update environment files with latest AWS outputs
cd ..
./update_env.sh
```

#### Optimized Backend Deployment
```bash
# Deploy optimized infrastructure from scratch (recommended for new environments)
cd aws
./deploy-optimized-full.sh

# OR update existing deployment to use optimized handlers and table
./deploy-optimized.sh

# Run data migration from original table to optimized table (if needed)
python3 run_migration.py

# Test performance improvements
python3 performance_test.py
```

**✅ CURRENT STATUS: OPTIMIZED BACKEND FULLY DEPLOYED**
- **Database**: `dcc-quotes-optimized` table with 3,798 items and all 4 GSI indexes ACTIVE
- **Migration**: Data successfully migrated from original table (1,432 → 3,798 items)
- **Infrastructure**: CloudFormation stack `dcc-demo-sam-app` deployed with optimized handlers
- **Performance**: Using GSI-based queries instead of table scans for 5-25x performance improvement
- **Endpoints**: All essential operations verified working:
  - Random quotes: `GET /quote` ✅
  - Tags endpoint: `GET /tags` (351 tags) ✅  
  - Tag filtering: `GET /quote?tags=Leadership,Business` ✅
  - Custom domain: `https://dcc.anystupididea.com` ✅
- **Search & Pagination**: Advanced admin endpoints deployed and working:
  - Search: `GET /admin/search?q=leadership&limit=10` ✅
  - Author filtering: `GET /admin/quotes/author/Einstein?limit=5` ✅
  - Tag filtering: `GET /admin/quotes/tag/Business?limit=10` ✅
  - JWT authentication required for all admin endpoints ✅
  - Type-ahead ready with debounce-friendly fast responses ✅

#### API Testing
```bash
# Test public API endpoints (includes dynamic tags endpoint)
cd tests
./test_api.sh

# Test admin API with comprehensive regression tests
./test_admin_api.sh

# Test tag cleanup functionality specifically
python3 tests/test_tag_cleanup.py

# Test individual tag management functionality
python3 tests/test_tag_editor.py

# Test pagination and search functionality
./tests/test_pagination_search.sh
```

### Flutter App Development
```bash
# Navigate to Flutter app
cd dcc_mobile

# Install dependencies (includes AWS Amplify for authentication)
flutter pub get

# Run on iOS simulator (includes admin functionality)
flutter run

# Build for web
flutter build web --release

# Run tests
flutter test
```

### Web App Deployment
```bash
# Deploy complete web application with automatic SSL and CDN
./deploy-web.sh

# Deploy to custom domain
./deploy-web.sh myapp.example.com

# Deploy with custom stack name and region
./deploy-web.sh myapp.example.com my-stack us-west-2 my-flutter-app

# Update existing web deployment (rebuild and upload)
cd dcc_mobile
flutter build web --release
cd ..
aws s3 sync dcc_mobile/build/web/ s3://BUCKET_NAME/ --delete
aws cloudfront create-invalidation --distribution-id DISTRIBUTION_ID --paths "/*"
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
  - API Gateway with dual authentication (API Key for public, Cognito JWT for authenticated users)
  - Lambda functions for public quotes, user registration, admin CRUD operations, and AI tag generation
  - DynamoDB table with Global Secondary Index for multi-tag querying
  - Cognito User Pool with self-registration and role-based groups (Users, Admins)
  - Custom domain support with SSL certificates
- **Lambda Functions**:
  - `quote_handler.py`: Public quote API with tag validation, filtering + dynamic tags endpoint (GET /tags)
    - Validates requested tags against metadata
    - Gracefully handles non-existent tags
    - Falls back to "All" if no valid tags found
  - `admin_handler.py`: Admin CRUD operations with comprehensive tags management and data integrity
    - Tag rename/delete operations automatically update all affected quotes
    - Maintains tags metadata cache for O(1) retrieval
  - `auth_handler.py`: User registration and email confirmation
    - Self-service user registration with email verification
    - Automatic assignment to Users group upon registration
    - Handles password validation and Cognito integration
  - `options_handler.py`: CORS preflight handler for web browser compatibility
    - Handles OPTIONS requests without authentication
    - Returns proper CORS headers for cross-origin requests
    - Enables web application functionality
  - `openai_handler.py`: Secure OpenAI API proxy for enterprise tag generation
    - Proxies requests to OpenAI GPT-4o-mini for intelligent tag generation
    - Keeps OpenAI API key secure in Lambda environment variables
    - Handles rate limiting and error recovery for AI requests
    - Admin authentication required for all tag generation operations
- **Database**: DynamoDB with tags metadata caching for zero-scan performance
  - TAGS_METADATA record maintains complete tag list for O(1) retrieval
  - Admin operations automatically update tags metadata with full data integrity
  - Individual tag management with automatic quote synchronization
  - Metadata records properly filtered from quote listings
  - No database scanning required for tag list retrieval
- **Response Format**: JSON with `quote`, `author`, `tags`, and `id` fields
- **Security Features**:
  - API Key authentication for public endpoints (rate limited)
  - Cognito JWT authentication for registered user endpoints (no rate limits)
  - Role-based access control with Users and Admins groups
  - Self-registration with email verification required
  - Password complexity requirements (8+ chars, upper, lower, number, special char)
  - CORS configured for web and mobile app access
  - OPTIONS handlers for browser preflight requests
- **Rate Limits**: 1 req/sec sustained, 5 req/sec burst, 1,000 req/day for public API
- **Monitoring**: CloudWatch metrics, logging, and distributed tracing enabled

### Optimized Backend Architecture (`aws/template-optimized.yaml`)
**Performance-Enhanced Infrastructure with Single Table Design**
- **Optimized DynamoDB Table**: `dcc-quotes-optimized` with advanced indexing strategy
  - **Single Table Design**: All data types (quotes, tags, metadata) in one table with composite keys
  - **Global Secondary Indexes**:
    - `TypeDateIndex`: Fast retrieval of all items by type sorted by date
    - `AuthorDateIndex`: Efficient author-based queries with date sorting
    - `TagQuoteIndex`: Direct tag-to-quote mapping for instant tag filtering
    - `SearchIndex`: Text-based search optimization (future OpenSearch integration)
  - **DynamoDB Streams**: Real-time processing of data changes for analytics
  - **Point-in-Time Recovery**: Enabled for production environments
  - **TTL Support**: Automatic cleanup of temporary data (session tokens, etc.)

- **Optimized Lambda Functions**:
  - `quote_handler_optimized.py`: 2-10x faster quote retrieval using GSI queries instead of scans
    - Tag-based filtering uses `TagQuoteIndex` for O(log n) performance vs O(n) table scans
    - Author queries use `AuthorDateIndex` for instant results
    - New endpoints: `/quotes/author/{author}`, `/quotes/tag/{tag}`, `/search`
  - `admin_handler_optimized.py`: Enhanced with bulk operations and export functionality
    - **NEW**: `/admin/export` - Complete data backup endpoint for disaster recovery
    - Batch processing for large tag operations
    - Improved error handling with detailed CloudWatch logging
  - `stream_processor.py`: Real-time data processing and analytics
  - `migration.py`: One-time data migration from original to optimized table structure

- **Performance Improvements**:
  - **Tag Queries**: 5-15x faster using direct index access vs filtered scans
  - **Author Queries**: 10-25x faster using dedicated author index
  - **Random Quote Selection**: 2-3x faster using type index instead of full table scan
  - **Memory Usage**: Reduced by 40% through optimized data structures
  - **Cost Reduction**: 60-80% lower DynamoDB costs through efficient queries

- **Deployment Scripts**:
  - `deploy-optimized-full.sh`: Complete infrastructure deployment from scratch
  - `deploy-optimized.sh`: Update existing deployment to use optimized handlers
  - Automatic error handling, timing waits, and permission management
  - S3 bucket resolution and CloudFormation stack management

### Flutter App (`dcc_mobile/`)
- **App Name**: Quote Me - Modern quote management application
- **Platform Support**: iOS, Android, and Web (https://quote-me.anystupididea.com)
- **Architecture**: Clean separation with screens in dedicated folders and services
- **Screen Components**:
  - `quote_screen.dart`: Main app with responsive layout, category filtering, and unified authentication menu
  - `settings_screen.dart`: Dynamic tag loading with voice testing and server synchronization
  - `login_screen.dart`: Unified authentication for all users with role-based navigation
  - `registration_screen.dart`: Self-service user registration with email verification
  - `admin_dashboard_screen.dart`: Full quote management interface with CRUD operations and tag filtering
  - `tags_editor_screen.dart`: Dedicated tag management interface with individual tag CRUD operations
- **Authentication Service**: `lib/services/auth_service.dart`
  - AWS Amplify Cognito integration for secure authentication
  - Self-registration and email verification support
  - Role-based group membership verification (Users, Admins)
  - JWT token management for API calls
  - Persistent authentication state management
  - Unified login for all user types
- **Dependencies**:
  - `http: ^1.1.0`: API communication with authentication headers
  - `flutter_tts: ^4.0.2`: Advanced text-to-speech with voice selection
  - `shared_preferences: ^2.2.2`: Local settings persistence
  - `flutter_dotenv: ^5.1.0`: Environment variable management
  - `amplify_flutter: ^2.0.0`: AWS Amplify core functionality
  - `amplify_auth_cognito: ^2.0.0`: Cognito authentication integration
- **State Management**: setState() pattern with service-layer abstraction
- **Error Handling**: Comprehensive error handling with automatic retry logic for 500 errors
- **Theme**: Modern professional branding with:
  - **Primary Color**: Dark indigo (#3F51B5) for AppBar, buttons, and primary elements
  - **Accent Color**: Light indigo (#5C6BC0) for highlights and secondary elements
  - **Background**: Light indigo (#E8EAF6) for a cohesive, modern appearance
  - **Text**: White on dark backgrounds, indigo on light backgrounds for optimal contrast
- **Advanced Features**:
  - **Audio System**: Advanced text-to-speech with comprehensive controls:
    - Voice selection from 20-50+ available voices with real-time testing
    - Speech rate control: Very Slow (0.15), Moderate (0.45), Normal (0.55), Fast (0.75)
    - Voice pitch control: Low (0.6), Normal (1.0), High (1.4)
    - Smart interruption controls and simulator compatibility
    - Persistent settings with immediate application to quote playback
  - **Dynamic Tag Filtering**: Real-time tag loading with 3-tag minimum for variety
  - **Admin Management**: Complete quote CRUD with real-time updates, advanced sorting, and tag export functionality
  - **Quote Sorting**: AppBar toggle buttons for sorting by Quote, Author, or Created Date (ascending/descending)
  - **Tag Filtering**: Dropdown filter to view quotes by specific tags with count indicators
  - **Duplicate Management**: Smart duplicate detection and cleanup with intelligent selection
  - **Tag Management System**: Dedicated Tags Editor with individual tag CRUD operations
  - **AI Tag Generation**: OpenAI GPT-4o-mini integration for intelligent tag generation:
    - Enterprise-grade security with AWS Lambda proxy pattern
    - Batch processing with user-controlled flow (5 quotes at a time with pause/continue)
    - Real-time progress tracking with countdown timers and quote context display
    - Smart tag selection preferring existing tags over creating new ones
    - Cross-platform support (iOS, Android, Web) with CORS-compliant implementation
  - **Import System**: Copy/paste TSV import from Google Sheets with real-time progress tracking
  - **Progress Tracking**: Batch processing with visual progress bar and status updates
  - **Tag Cleanup System**: Automated removal of unused tags from metadata with confirmation dialog
  - **Data Integrity**: Automatic quote synchronization when tags are renamed or deleted
  - **Responsive Design**: Perfect layout in all orientations with no overflow
  - **Security Integration**: Seamless admin access with role-based permissions
  - **Resilience Features**: Automatic retry with exponential backoff for server errors

### Web Deployment Infrastructure (`web-infrastructure.yaml` & `deploy-web.sh`)
- **CloudFormation Template**: Complete web hosting infrastructure with automatic SSL
  - **S3 Bucket**: Static website hosting with CORS configuration
  - **CloudFront Distribution**: Global CDN with edge caching and HTTPS redirect
  - **Route53 Records**: Automatic DNS setup with alias records
  - **ACM Certificate**: Automatic SSL certificate creation and validation
  - **Origin Access Control**: Secure S3 access from CloudFront only
- **Deployment Script**: Comprehensive automation for Flutter web deployment
  - **Prerequisites Check**: Validates AWS CLI, Flutter SDK, and hosted zone
  - **Certificate Management**: Automatic SSL certificate detection and creation
  - **Flutter Build**: Automated web compilation with release optimization
  - **File Upload**: Optimized caching strategy (1 year for assets, no-cache for HTML)
  - **CloudFront Invalidation**: Cache busting for immediate updates
  - **Error Handling**: Graceful failure recovery with detailed troubleshooting
- **Features**:
  - **Custom Domains**: Support for any subdomain with existing Route53 hosted zone
  - **HTTPS Enforcement**: All traffic redirected to secure connections
  - **SPA Support**: Proper routing for single-page application architecture
  - **Performance Optimized**: Managed cache policies and compression
  - **Cost Effective**: PriceClass_100 (US, Canada, Europe) for optimal cost/performance

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

### Admin Dashboard Tag Filtering
The admin dashboard includes a powerful tag filtering system for efficient quote management:

**Filter Features**:
- **Dropdown Filter**: Located in the header below user info for easy access
- **All Tags Available**: Shows every tag currently used in your quote database
- **Quote Counts**: Each tag displays the number of quotes using it (e.g., "Leadership (12)")
- **Smart Selection**: Bold highlighting for the currently selected filter
- **Clear Button**: Quick reset to "All" quotes with a single click
- **Auto-Reset**: Filter automatically resets if a tag is completely removed from all quotes

**Filter Benefits**:
- **Efficient Editing**: Quickly find all quotes with a specific tag for bulk editing
- **Tag Consolidation**: Identify and merge similar tags (e.g., "Entrepreneurism" vs "Entrepreneurship")
- **Category Review**: Review all quotes in a particular category at once
- **Context-Aware UI**: Empty state messages change based on active filter
- **Persistent State**: Filter remains active while editing, creating, or deleting quotes

**Use Cases**:
- Finding quotes with typos or inconsistent tags
- Reviewing all quotes in a specific category
- Consolidating similar or duplicate tags
- Managing tag consistency across the database

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

### AI Tag Generation System
The admin dashboard includes an intelligent AI-powered tag generation feature powered by OpenAI GPT-4o-mini:

**Core Features**:
- **Batch Processing**: Processes quotes in batches of 5 with user-controlled flow
- **Smart Tag Selection**: Prioritizes existing tags over creating new ones for consistency
- **Progress Display**: Real-time progress tracking with countdown timers and quote context
- **Enterprise Security**: OpenAI API key secured in AWS Lambda, never exposed to client
- **Cross-Platform**: Works seamlessly on iOS, Android, and Web with CORS compliance
- **User Control**: Pause/continue functionality between batches for user oversight

**Processing Flow**:
- **Tag Analysis**: AI analyzes quote content and author to suggest relevant tags
- **Existing Tag Priority**: System prefers selecting from existing database tags
- **Batch Safety**: 5-second delays between batches prevent rate limiting
- **Context Display**: Shows current quote being processed during countdown delays
- **Progress Tracking**: Visual progress bar with "Processing quote X of Y" status

**Technical Implementation**:
- **Secure Proxy**: AWS Lambda endpoint hides OpenAI API credentials
- **Rate Limiting**: Built-in delays and error handling for API stability
- **Error Recovery**: Graceful handling of network issues and API failures
- **Real-time Updates**: Live progress display with quote and author context

**Access Method**: Admin Dashboard → Menu → "Generate tags for the tagless"

### Backup Export System
The admin dashboard includes a comprehensive data export feature for backup and disaster recovery:

**Core Features**:
- **Complete Data Export**: Exports all quotes, authors, and tags in structured format
- **Metadata Included**: Export timestamp, counts, version info for data integrity
- **Efficient Processing**: Uses optimized database indexes for fast bulk export
- **Download Ready**: Proper Content-Disposition headers for direct file download
- **Flexible Formats**: JSON (implemented) with CSV support planned

**Export Structure**:
```json
{
  "export_metadata": {
    "timestamp": "2025-08-18T18:08:37Z",
    "total_quotes": 6539,
    "total_authors": 423,
    "total_tags": 351,
    "format": "json", 
    "version": "2.0"
  },
  "quotes": [...],    // All quotes with full metadata
  "authors": [...],   // Unique sorted author list
  "tags": [...]       // Unique sorted tag list
}
```

**Query Parameters**:
- `format=json` (default) or `format=csv`
- `metadata=true` (default) to include created_by information

**Technical Implementation**:
- **Efficient Scanning**: Uses TypeDateIndex for optimized database access
- **Memory Management**: Processes large datasets without Lambda timeout issues  
- **Error Handling**: Comprehensive error recovery and logging
- **Security**: Admin JWT authentication required for all export operations

**Use Cases**:
- **Disaster Recovery**: Complete data backup before major changes
- **Data Migration**: Moving between environments or accounts
- **Analytics**: Bulk data analysis and reporting
- **Compliance**: Data export for regulatory requirements

**Access Method**: `GET /admin/export` endpoint (API Gateway route setup required)

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
**Random Quote Retrieval:**
- **Custom Domain**: `https://dcc.anystupididea.com/quote`
- **Direct URL**: `https://iasj16a8jl.execute-api.us-east-1.amazonaws.com/prod/quote`
- **Authentication**: API Key required (`x-api-key` header)
- **Features**: Tag filtering via `?tags=Motivation,Business` query parameter

**Specific Quote Retrieval:**
- **Custom Domain**: `https://dcc.anystupididea.com/quote/{id}`
- **Direct URL**: `https://iasj16a8jl.execute-api.us-east-1.amazonaws.com/prod/quote/{id}`
- **Authentication**: API Key required (`x-api-key` header)
- **Features**: Returns specific quote by ID, or "Requested quote was not found." if not found

**Dynamic Tags Retrieval:**
- **Custom Domain**: `https://dcc.anystupididea.com/tags`
- **Direct URL**: `https://iasj16a8jl.execute-api.us-east-1.amazonaws.com/prod/tags`
- **Authentication**: API Key required (`x-api-key` header)
- **Features**: Returns all available tags from database (zero-scan performance)
- **Response**: `{"tags": ["All", "Action", "Business", ...], "count": 23}`

### Authentication API (No Rate Limits)
**User Registration:**
- **Endpoint**: `POST https://dcc.anystupididea.com/auth/register`
- **Authentication**: None required
- **Body**: `{"email": "user@example.com", "password": "Password123!", "name": "Optional Name"}`
- **Features**: Self-service user registration with automatic Users group assignment

**Email Verification:**
- **Endpoint**: `POST https://dcc.anystupididea.com/auth/confirm`
- **Authentication**: None required
- **Body**: `{"email": "user@example.com", "code": "123456"}`
- **Features**: Email verification to complete registration

### Admin API (JWT Protected - Admin Group Required)
- **Base URL**: `https://dcc.anystupididea.com/admin/`
- **Authentication**: Cognito IdToken required (`Authorization: Bearer {token}`) + Admin group membership
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
- **AI Tag Generation Endpoint**:
  - `POST /admin/generate-tags` - Generate intelligent tags for quotes using OpenAI GPT-4o-mini
    - Secure proxy endpoint hiding OpenAI API key in Lambda environment
    - Body: `{"quote": "quote text", "author": "author name", "existingTags": ["tag1", "tag2"]}`
    - Returns: `{"tags": ["tag1", "tag2", "tag3"]}` (up to 5 tags)
    - Admin authentication and group membership required
- **Tags Metadata Management**: All CRUD operations automatically maintain tags metadata cache with full data integrity
- **Quote Synchronization**: Tag rename/delete operations automatically update all affected quotes

### User Management
**Registration Process:**
1. Users register via the mobile app or web interface
2. Email verification required (6-digit code sent to email)
3. Automatic assignment to "Users" group upon verification
4. Password requirements: 8+ characters, uppercase, lowercase, number, special character

**Admin Access:**
- Existing admin account: `admin@dcc.com` / `AdminPass123!`
- Admin users must be manually added to "Admins" group via AWS Console
- New users register as regular users by default

**Cognito Configuration:**
- **User Pool**: `us-east-1_ecyuILBAu`
- **Client ID**: `2idvhvlhgbheglr0hptel5j55`
- **Groups**: "Users" (default), "Admins" (manual assignment)

## Important Notes

### Production Features
- **Database**: DynamoDB with 20+ curated quotes and dynamic tag system (zero-scan performance)
- **Authentication**: Enterprise-grade Cognito integration with self-registration and role-based access control
- **Security**: Multi-layer API security (API keys for public + JWT for authenticated users) with group-based permissions and CORS support
- **User Management**: Self-service registration with email verification and automatic group assignment
- **Performance**: Rate limiting, CloudWatch monitoring, tags metadata caching, custom domain with CDN
- **Cross-Platform**: Mobile (iOS/Android) and Web (https://quote-me.anystupididea.com) with unified authentication
- **Web Deployment**: Automated CloudFormation infrastructure with S3, CloudFront, Route53, and SSL

### Advanced Capabilities
- **Audio System**: Professional TTS with 20-50+ voice options, testing, and smart controls
- **User Authentication**: Unified login system with self-registration and role-based features
- **Admin Management**: Complete quote lifecycle management with real-time updates and advanced sorting
- **Quote Sorting**: Three-field sorting (Quote, Author, Date) with ascending/descending toggles in AppBar
- **Duplicate Management**: Intelligent duplicate detection with smart cleanup and preservation logic
- **Progress Tracking**: Real-time batch processing with visual progress bars for long operations
- **Dynamic Tag System**: Real-time tag loading and filtering with zero-scan database performance
- **Tags Metadata Caching**: Efficient O(1) tag retrieval without database scanning
- **Individual Tag Management**: Dedicated Tags Editor for adding, renaming, and deleting individual tags
- **Data Integrity Enforcement**: Tag operations automatically synchronize with all affected quotes
- **Automated Tag Cleanup**: Admin can remove unused tags with one-click cleanup and detailed reporting
- **AI Tag Generation**: OpenAI GPT-4o-mini integration for intelligent tag generation:
  - Enterprise-grade security with OpenAI API key stored securely in AWS Lambda
  - Batch processing with user-controlled flow (5 quotes at a time)
  - Real-time progress display showing quote context during processing delays
  - Intelligent tag selection preferring existing tags over new ones
  - Cross-platform support with CORS-compliant AWS Lambda proxy
- **Import Progress**: Batch processing with real-time status updates and visual feedback
- **Rate Limiting Protection**: Built-in delays and batch processing prevent API overload
- **Metadata Filtering**: TAGS_METADATA records are properly filtered from quote listings
- **Responsive Design**: Perfect layout across all device orientations and screen sizes
- **Error Handling**: Comprehensive error management with user-friendly messaging
- **State Management**: Persistent settings and authentication across app sessions
- **Smart Navigation**: Context-aware menu system showing different options based on user authentication status

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
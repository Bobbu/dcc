# DCC Quote Management System

A comprehensive, enterprise-grade quote management platform featuring secure AWS backend infrastructure and a feature-rich Flutter mobile application with complete admin capabilities.

## Architecture

### AWS Backend Infrastructure
- **API Gateway**: Dual-authentication system supporting both public and admin endpoints
- **Lambda Functions**: 
  - Public quote API with DynamoDB integration and tag filtering + dynamic tags endpoint
  - Admin CRUD operations with tags metadata management and validation
- **Database**: DynamoDB with tags metadata caching for zero-scan performance
  - TAGS_METADATA record maintains complete tag list for O(1) retrieval
  - Admin operations automatically update tags metadata cache
- **Authentication**: AWS Cognito User Pool with role-based access control (admin group)
- **Security**: API key authentication for public access, JWT tokens for admin operations
- **Custom Domain**: SSL-secured custom domain (dcc.anystupididea.com) with CloudFront CDN
- **Monitoring**: CloudWatch logging, metrics, and distributed tracing

### Flutter Mobile Application
- **Multi-Screen Architecture**: Clean separation with dedicated screens and service layers
  - **Quote Screen**: Responsive main interface with category filtering and audio controls
  - **Settings Screen**: Dynamic tag loading from server with voice testing capabilities  
  - **Admin Login**: Secure authentication interface with corporate branding
  - **Admin Dashboard**: Complete quote management with real-time CRUD operations
  - **Tags Editor**: Dedicated tag management interface with individual tag CRUD operations

- **Advanced Audio System**: 
  - Professional TTS with 20-50+ voice options per device
  - Voice selection and testing with sample phrases
  - Smart audio interruption and state management
  - Visual indicators: 🔊 (enabled), 🔇 (disabled), ⏹️ (speaking)
  - Simulator compatibility with automatic timeout fallbacks

- **Admin Management Features**:
  - Secure Cognito authentication with admin group verification
  - Complete quote lifecycle management (Create, Read, Update, Delete)
  - Real-time quote list with metadata display
  - Multi-select tag editor with inline tag creation
  - Import from Google Sheets via copy/paste with preview
  - Automated unused tag cleanup with confirmation dialogs
  - Instant synchronization with public API

- **User Experience**:
  - Real-time dynamic tag loading and filtering with zero-scan performance
  - Minimum 3-tag selection requirement for quote variety
  - Responsive design perfect in all orientations
  - Persistent settings across app sessions
  - Automatic retry with exponential backoff for server errors
  - Comprehensive error handling with friendly messaging
  - Corporate maroon and gold branding throughout

## Project Structure

```
dcc/
├── README.md               # Project documentation
├── CLAUDE.md               # Claude Code guidance and architecture details
├── ENV_SETUP.md            # Environment configuration guide
├── update_env.sh           # Automated environment synchronization script
├── migrate_quotes.py       # DynamoDB population script with tagged quotes
├── aws/                    # AWS serverless infrastructure
│   ├── template.yaml       # Complete SAM template (API Gateway, Lambda, DynamoDB, Cognito)
│   ├── lambda/
│   │   ├── quote_handler.py    # Public API with tag filtering
│   │   └── admin_handler.py    # Admin CRUD operations with validation
│   ├── setup_domain.sh     # Custom domain configuration script
│   └── deploy.sh           # Deployment automation
├── dcc_mobile/             # Flutter mobile application
│   ├── .env                # Environment configuration (API keys, Cognito settings)
│   ├── lib/
│   │   ├── main.dart       # App entry point with Amplify initialization
│   │   ├── services/
│   │   │   ├── auth_service.dart   # AWS Cognito authentication service
│   │   │   ├── api_service.dart    # Public API service for quotes and tags
│   │   │   └── admin_api_service.dart  # Admin CRUD operations service
│   │   └── screens/
│   │       ├── quote_screen.dart        # Main app with admin access
│   │       ├── settings_screen.dart     # User preferences and voice testing
│   │       ├── admin_login_screen.dart  # Secure admin authentication
│   │       ├── admin_dashboard_screen.dart  # Quote management interface
│   │       └── tags_editor_screen.dart  # Individual tag management interface
│   ├── pubspec.yaml        # Dependencies (includes AWS Amplify)
│   └── ...
└── tests/
    ├── .env                # Test environment configuration
    ├── test_api.sh         # Public API testing suite with rate limiting
    ├── test_admin_api.sh   # Comprehensive admin API regression tests
    ├── test_tag_cleanup.py # Tag cleanup functionality testing
    └── test_tag_editor.py  # Individual tag management testing
```

## Setup Instructions

### Prerequisites
- **AWS CLI** configured with appropriate permissions (IAM, API Gateway, Lambda, DynamoDB, Cognito)
- **SAM CLI** installed for serverless deployment
- **Flutter SDK** installed (latest stable version)
- **Xcode** (for iOS development and simulator)
- **Python 3.x** for quote migration and environment scripts
- **iOS device or simulator** with audio capability for text-to-speech testing

### Environment Configuration
**⚠️ Important: Set up environment variables first before running the applications.**

See [ENV_SETUP.md](ENV_SETUP.md) for detailed environment setup instructions, including:
- Automatic AWS synchronization with `./update_env.sh`
- Manual `.env` file configuration
- Security best practices for API key management

### AWS Infrastructure Deployment
1. Navigate to the `aws` directory
2. Deploy the complete serverless stack:
   ```bash
   sam build && sam deploy
   ```
3. **Initial Setup Only**: Migrate quotes to DynamoDB:
   ```bash
   cd .. && python3 migrate_quotes.py
   ```
4. Update environment files with latest AWS outputs:
   ```bash
   ./update_env.sh
   ```

### Admin User Setup (One-time)
The deployment automatically creates an admin user. Default credentials:
- **Email**: `admin@dcc.com`
- **Password**: `AdminPass123!`

You can create additional admin users via AWS Console or CLI.

### Flutter App Setup
1. **Environment Configuration**: Ensure `.env` file exists (auto-created by `./update_env.sh`)
2. Navigate to the `dcc_mobile` directory
3. Install dependencies (includes AWS Amplify):
   ```bash
   flutter pub get
   ```
4. Run the complete application:
   ```bash
   flutter run
   ```

### Accessing Admin Features
1. Launch the Flutter app
2. Tap the **three-dot menu** in the app bar
3. Select **"Admin"** from the dropdown
4. Sign in with admin credentials
5. Manage quotes via the admin dashboard
6. Access Tags Editor via menu → "Manage Tags" for individual tag operations
7. Import quotes via menu → "Import Quotes" for bulk import from Google Sheets

## Development Notes

### Testing the APIs

**Public API Testing:**
```bash
# Automated test suite with rate limiting validation
./tests/test_api.sh

# Manual testing with tag filtering
curl -H "x-api-key: YOUR_API_KEY" "https://dcc.anystupididea.com/quote?tags=Motivation,Science"

# Test dynamic tags endpoint
curl -H "x-api-key: YOUR_API_KEY" "https://dcc.anystupididea.com/tags"
```

**Admin API Testing:**
```bash
# Comprehensive regression test suite (creates temp admin user, tests all operations, cleans up)
./tests/test_admin_api.sh

# Test tag cleanup functionality specifically
python3 tests/test_tag_cleanup.py

# Test individual tag management functionality
python3 tests/test_tag_editor.py

# Manual admin authentication for debugging
TOKEN=$(aws cognito-idp admin-initiate-auth \
  --user-pool-id us-east-1_ecyuILBAu \
  --client-id 2idvhvlhgbheglr0hptel5j55 \
  --auth-flow ADMIN_NO_SRP_AUTH \
  --auth-parameters USERNAME=admin@dcc.com,PASSWORD=AdminPass123! \
  --query 'AuthenticationResult.IdToken' --output text)

# Test admin endpoints
curl -H "Authorization: Bearer $TOKEN" "https://dcc.anystupididea.com/admin/quotes"
```

### Import Feature

**Google Sheets Import:**
The admin dashboard includes a powerful import feature for bulk quote creation from Google Sheets:

1. **Prepare your data** in Google Sheets with columns:
   - Column A: Nugget (Quote text)
   - Column B: Source (Author)
   - Columns C-G: Tag1, Tag2, Tag3, Tag4, Tag5 (optional)

2. **Select and copy** rows from your spreadsheet (including headers)

3. **In the app**: Admin Dashboard → Menu → "Import Quotes"

4. **Paste** your data and click "Parse Data" to preview

5. **Review** the preview showing first 3 quotes

6. **Import** all quotes with one click

The import system handles tab-separated values, automatically detects headers, and provides feedback on success/failure counts.

### Flutter Development Features

**Core Functionality:**
- **Multi-Screen Architecture**: Dedicated screens for quotes, settings, admin login, and dashboard
- **Advanced Error Handling**: Context-aware messaging for network, authentication, and API failures
- **Responsive Design**: Perfect layout optimization for all device orientations and screen sizes
- **Real-time Synchronization**: Admin changes immediately reflected in public quote display

**Audio & Voice Features:**
- **Professional TTS System**: 20-50+ voice options with real-time testing capabilities
- **Smart Audio Controls**: Automatic interruption, state management, and visual indicators
- **Voice Testing**: Sample phrase playback before voice selection commitment
- **Audio State Indicators**: 🔊 (enabled), 🔇 (disabled), ⏹️ (currently speaking)

**Admin Management:**
- **Secure Authentication**: AWS Cognito integration with admin group verification
- **Complete CRUD Operations**: Create, read, update, delete quotes with validation
- **Tag Management System**: 
  - **Tags Editor**: Dedicated interface for individual tag CRUD operations
  - **Data Integrity**: Automatic quote synchronization when tags are renamed or deleted
  - **Duplicate Prevention**: Cannot add tags that already exist
  - **Smart Synchronization**: Tag rename updates all affected quotes automatically
  - **Safe Deletion**: Removing tags updates all quotes that were using them
  - **Visual Management**: Multi-tag categorization with visual chip interface
  - **Automated Cleanup**: One-click removal of unused tags with detailed reporting
- **Real-time Updates**: Instant quote list refresh and synchronization
- **User-Friendly Interface**: Intuitive admin dashboard with confirmation dialogs

**Technical Excellence:**
- **Clean Architecture**: Service layer separation with dependency injection patterns
- **State Management**: Persistent settings and authentication across app sessions
- **Security Integration**: JWT token management with automatic renewal
- **Environment Management**: Secure configuration with no hardcoded credentials
- **Corporate Branding**: Consistent maroon (#800000) and gold (#FFD700) theming

## API Usage

### Public API Endpoints

**Quote Retrieval:**
- **URL**: `https://dcc.anystupididea.com/quote`
- **Method**: GET
- **Authentication**: API Key required (`x-api-key` header)
- **Query Parameters**: 
  - `tags` (optional): Comma-separated list (e.g., `?tags=Motivation,Business`)
- **Rate Limits**: 1 req/sec sustained, 5 req/sec burst, 1,000 req/day
- **Response**:
  ```json
  {
    "quote": "The only way to do great work is to love what you do.",
    "author": "Steve Jobs",
    "tags": ["Motivation", "Business", "Success"],
    "id": "27fc1a0a-9df4-406a-8b34-bb3fa045814c"
  }
  ```

**Dynamic Tags Retrieval:**
- **URL**: `https://dcc.anystupididea.com/tags`
- **Method**: GET
- **Authentication**: API Key required (`x-api-key` header)
- **Features**: Zero-scan performance with tags metadata caching
- **Rate Limits**: 1 req/sec sustained, 5 req/sec burst, 1,000 req/day
- **Response**:
  ```json
  {
    "tags": ["All", "Action", "Art", "Business", "Innovation", ...],
    "count": 23
  }
  ```

### Admin API Endpoints

**Authentication Required**: Cognito IdToken in `Authorization: Bearer {token}` header

**List Quotes:**
- **GET** `/admin/quotes` - Returns all quotes with metadata

**Create Quote:**
- **POST** `/admin/quotes`
- **Body**: `{"quote": "text", "author": "name", "tags": ["tag1", "tag2"]}`
- **Auto-Updates**: Tags metadata cache updated automatically

**Update Quote:**
- **PUT** `/admin/quotes/{id}`
- **Body**: `{"quote": "text", "author": "name", "tags": ["tag1", "tag2"]}`
- **Auto-Updates**: Tags metadata cache updated automatically

**Delete Quote:**
- **DELETE** `/admin/quotes/{id}`

**Get Available Tags:**
- **GET** `/admin/tags` - Returns all available tags from metadata cache
- **Response**: `{"tags": ["Action", "Business", ...], "count": 19}`

**Add Individual Tag:**
- **POST** `/admin/tags`
- **Body**: `{"tag": "NewTag"}`
- **Response**: `{"message": "Tag 'NewTag' added successfully", "tags": [...], "count": 20}`

**Rename Tag:**
- **PUT** `/admin/tags/{tag}`
- **Body**: `{"new_tag": "RenamedTag"}`
- **Auto-Updates**: All quotes using the old tag are updated automatically
- **Response**: `{"message": "Tag renamed and X quotes updated", "updated_quotes": X}`

**Delete Individual Tag:**
- **DELETE** `/admin/tags/{tag}`
- **Auto-Updates**: Removes tag from all quotes using it
- **Response**: `{"message": "Tag 'OldTag' deleted and X quotes updated", "updated_quotes": X}`

**Clean Unused Tags:**
- **DELETE** `/admin/tags/unused` - Removes tags not used by any quotes
- **Response**: `{"message": "Successfully removed X unused tags", "removed_tags": [...], "remaining_tags": [...], "count_removed": X, "count_remaining": Y}`

### Security & Infrastructure Features

**Multi-Layer Security:**
- **Public API**: API Key authentication with aggressive rate limiting (1,000 req/day)
- **Admin API**: AWS Cognito JWT tokens with admin group membership verification
- **Role-Based Access**: Admin operations require explicit group membership
- **Custom Domain**: SSL-secured custom domain with CloudFront CDN distribution

**Infrastructure Benefits:**
- **High Availability**: Serverless architecture with automatic scaling
- **Performance**: Custom domain with CloudFront edge caching
- **Monitoring**: Comprehensive CloudWatch logging and metrics
- **Cost Optimization**: Pay-per-use billing with DynamoDB on-demand pricing

**Database Features:**
- **DynamoDB**: NoSQL database with automatic scaling and backup
- **Dynamic Tags System**: Zero-scan tags metadata caching for O(1) performance
- **Multi-Tag Support**: Efficient tag-based querying with automatic metadata updates
- **Tag Validation**: Backend validates requested tags and handles non-existent ones gracefully
- **Data Integrity**: Comprehensive validation and error handling
- **Real-time Sync**: Instant propagation of admin changes to public API and tags cache

**Resilience Features:**
- **Automatic Retry Logic**: 500 errors trigger up to 3 retries with exponential backoff
- **Network Error Recovery**: Graceful handling of network failures with automatic retry
- **Lambda Cold Start Handling**: Retry mechanism handles cold start timeouts
- **DynamoDB Throttling Protection**: Backoff strategy prevents overwhelming the database
- **User-Friendly Error Messages**: Clear feedback during retries and failures

### Environment Management

**Automated Configuration:**
The `update_env.sh` script automatically synchronizes AWS deployment outputs with local environment files:
- Detects custom domain vs. direct API Gateway URLs
- Retrieves actual API key values (not just IDs)
- Updates both `tests/.env` and `dcc_mobile/.env` files
- Provides secure, automated credential management

**Manual Retrieval:**
```bash
# Get API key value
aws apigateway get-api-key --api-key $(aws cloudformation describe-stacks \
  --stack-name dcc-demo-sam-app --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyValue`].OutputValue' \
  --output text) --include-value --query 'value' --output text
```
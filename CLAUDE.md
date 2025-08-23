# CLAUDE.md

Guidance for Claude Code when working with the Quote Me codebase.

## Project Overview

"Quote Me" is an enterprise-grade quote management system:
- **AWS Backend**: Serverless API with dual authentication (API Key for public, JWT for admin)
- **Flutter Apps**: Cross-platform mobile/web with professional indigo theme
- **Admin System**: Full CRUD, search, import/export, and tag management
- **Web Infrastructure**: Automated CloudFront/S3 deployment with SSL

## Development Commands

### AWS Deployment
```bash
cd aws
./deploy.sh    # ALWAYS use this for consistent deployments
```
✅ Uses `aws/template.yaml` as single source of truth
✅ Handles OpenAI API key injection securely

**✅ DEPLOYMENT STATUS**
- Database: `dcc-quotes-optimized` with 3,798 items, 4 GSI indexes
- Performance: 5-25x improvement with GSI queries
- Domain: `https://dcc.anystupididea.com`
- All endpoints operational with JWT auth for admin

### API Testing
```bash
# Public API tests (API Key required)
./tests/test_api.sh

# Admin API tests (auto-creates temp admin user)
./tests/test_admin_api.sh
python3 tests/test_tag_cleanup.py
python3 tests/test_tag_editor.py
```

### Flutter Development
```bash
cd dcc_mobile
flutter pub get
flutter run       # iOS/Android
flutter build web --release  # Web
```

### Web Deployment
```bash
./deploy-web.sh [domain]  # Full deployment with SSL/CDN
```

## Architecture

### Backend (`aws/`)
- **Infrastructure**: SAM template with API Gateway, Lambda, DynamoDB, Cognito
- **Authentication**: Dual-layer (API Key for public, JWT for admin)
- **Lambda Functions**:
  - `quote_handler.py`: Public API with tag filtering, O(1) tag retrieval, limit up to 1000
  - `admin_handler.py`: CRUD with tag management and data integrity, limit up to 1000
  - `auth_handler.py`: User registration/verification
  - `options_handler.py`: CORS support
  - `openai_handler.py`: Secure GPT-4o-mini proxy for tag generation
- **Performance**: Tags metadata caching, GSI indexes, zero-scan operations
- **Security**: Rate limiting (public only), email verification, role-based access


### Flutter App (`dcc_mobile/`)
- **Platforms**: iOS, Android, Web (https://quote-me.anystupididea.com)
- **Key Screens**:
  - `quote_screen.dart`: Main app with About dialog, unified auth menu
  - `settings_screen.dart`: Theme selector, voice controls, tag preferences
  - `admin_dashboard_screen.dart`: Full CRUD, search, import/export
  - `tags_editor_screen.dart`: Individual tag management
  - `user_profile_screen.dart`: Profile management, Daily Nuggets prep
- **Authentication**: AWS Amplify Cognito with JWT management
- **Theme System**: Light/Dark/System modes with persistent preferences
- **Audio**: TTS with 20-50+ voices, rate/pitch controls (default: OFF)
### Key Features
- **About Dialog**: Responsive dialog with app info, accessible to all users
- **Quote Retrieval Limit**: User-configurable limit (50-1000) for quote fetching
- **AI Tag Generation**: GPT-4o-mini via secure Lambda proxy
- **Import/Export**: TSV import, multi-format export (JSON/CSV)
- **Duplicate Management**: Smart detection and cleanup
- **Search**: Universal search across quotes, authors, tags
- **Sorting**: 4-field sorting with persistent preferences
- **Progress Tracking**: Real-time status for batch operations

### Web Infrastructure
- **CloudFormation**: S3, CloudFront, Route53, ACM for SSL
- **Deployment**: `./deploy-web.sh` handles everything automatically
- **Features**: Custom domains, HTTPS enforcement, SPA routing, CDN caching

### Import/Export
**Import**: Copy/paste TSV from Google Sheets with real-time progress
**Export**: JSON/CSV to Download, Clipboard, or S3 with shareable URLs
**Access**: Admin Dashboard → Menu







## Key Integration Points
- **Environment**: `./update_env.sh` syncs AWS outputs to `.env`
- **Auth Model**: API Key (public/rate-limited), JWT (admin/unlimited)
- **Data Flow**: DynamoDB → Lambda → API Gateway → Flutter
- **Domain**: https://dcc.anystupididea.com with CloudFront/SSL

## API Endpoints

### Public (API Key, Rate Limited)
- `GET /quote` - Random quote with optional tag filtering
- `GET /quote/{id}` - Specific quote by ID
- `GET /tags` - All available tags (O(1) retrieval)
- `POST /auth/register` - User registration (no auth required)
- `POST /auth/confirm` - Email verification (no auth required)

### Admin (JWT + Admin Group)
- **Quotes**: GET/POST/PUT/DELETE `/admin/quotes[/{id}]`
- **Tags**: GET/POST/PUT/DELETE `/admin/tags[/{tag}]`
- `DELETE /admin/tags/unused` - Remove orphaned tags
- `POST /admin/generate-tags` - GPT-4o-mini tag generation

## User Management
- **Registration**: Self-service with email verification
- **Groups**: "Users" (auto), "Admins" (manual)
- **Admin**: `admin@dcc.com` / `AdminPass123!`
- **Cognito**: Pool `us-east-1_ecyuILBAu`, Client `2idvhvlhgbheglr0hptel5j55`

## Production Status
- **Database**: 3,798 quotes with O(1) tag retrieval
- **Auth**: Cognito with self-registration, role-based access
- **Performance**: 5-25x faster with GSI, CloudFront CDN
- **Platforms**: iOS, Android, Web (https://quote-me.anystupididea.com)

## Key Capabilities
- **About Dialog**: App info accessible to all users
- **Quote Retrieval Limit**: Configurable 50-1000 quotes per fetch (Settings screen)
- **Audio**: TTS with 50+ voices, rate/pitch controls (default: OFF)
- **Admin**: Full CRUD, search, sort, import/export
- **AI Tags**: GPT-4o-mini via secure Lambda proxy
- **Resilience**: Auto-retry, graceful error handling
- **Standards**: Clean architecture, automated testing

## Development Guidelines
- Keep file sizes manageable with proper separation of concerns
- Always use themes.dart for styling (never inline styles)
- Edit existing files rather than creating new ones
- Only create documentation when explicitly requested
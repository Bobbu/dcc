# Quote Me - Inspirational Quote Management System

A comprehensive quote management system with enterprise-grade features, including Flutter mobile/web applications and AWS serverless backend infrastructure.

## 🌟 Live Demo

- **Web App**: https://quote-me.anystupididea.com
- **API Endpoint**: https://dcc.anystupididea.com/quote

## 🚀 Features

### Mobile & Web Applications
- **Cross-Platform**: iOS, Android, and Web support via Flutter
- **Professional UI**: Dark indigo theme (#3F51B5) with clean, modern design
- **Dynamic Tag System**: Real-time tag loading and filtering with O(1) performance
- **Advanced Audio**: Text-to-speech with 20-50+ voice options
- **Admin Dashboard**: Complete quote management interface with tag filtering
- **Tag Management**: Dedicated editor for individual tag operations
- **Import System**: Bulk import from Google Sheets via TSV with progress tracking
- **Duplicate Detection**: Intelligent duplicate cleanup with preservation logic

### Backend Infrastructure
- **Serverless Architecture**: AWS Lambda + API Gateway + DynamoDB
- **Dual Authentication**: Public API (API Key) + Admin API (JWT)
- **Custom Domain**: SSL-secured endpoints via Route53 and CloudFront
- **High Performance**: Tags metadata caching for zero-scan operations
- **CORS Support**: Full web application compatibility
- **Rate Limiting**: 1 req/sec sustained, 5 req/sec burst, 1,000 req/day
- **Auto-scaling**: Serverless infrastructure scales automatically

## 🛠️ Technology Stack

### Frontend
- **Flutter 3.0+**: Cross-platform framework for mobile and web
- **AWS Amplify**: Cognito authentication integration
- **Material Design 3**: Modern UI components with indigo theme
- **Flutter TTS**: Professional text-to-speech engine

### Backend
- **AWS SAM**: Infrastructure as Code
- **Lambda**: Python 3.10 serverless functions with OPTIONS handlers
- **DynamoDB**: NoSQL database with metadata caching
- **API Gateway**: RESTful API with CORS and dual authentication
- **Cognito**: User authentication and authorization
- **CloudFront**: CDN for web distribution and API caching
- **Route53**: DNS management with automatic SSL
- **ACM**: SSL certificate management

## 📦 Quick Start

### Prerequisites
- Flutter SDK 3.0+
- AWS CLI configured
- Python 3.10+
- SAM CLI
- Node.js 14+

### 1. Clone & Setup
```bash
git clone https://github.com/yourusername/quote-me.git
cd quote-me
```

### 2. Deploy Backend
```bash
cd aws
sam build && sam deploy
cd ..
./update_env.sh  # Auto-configures environment
```

### 3. Run Mobile App
```bash
cd dcc_mobile
flutter pub get
flutter run
```

### 4. Deploy Web App
```bash
./deploy-web.sh  # Automatic web deployment with SSL
```

## 🌐 Web Deployment

The project includes a comprehensive web deployment solution:

```bash
# Deploy to custom domain
./deploy-web.sh myapp.example.com

# Use default configuration
./deploy-web.sh
```

This automatically:
- ✅ Creates SSL certificate via ACM
- ✅ Sets up S3 static hosting
- ✅ Configures CloudFront CDN
- ✅ Creates Route53 DNS records
- ✅ Builds and deploys Flutter web app
- ✅ Handles CORS configuration

## 🔑 API Usage

### Public Endpoints

**Get Random Quote**
```bash
curl -H "X-Api-Key: YOUR_API_KEY" \
  https://dcc.anystupididea.com/quote
```

**Get Quote with Tags**
```bash
curl -H "X-Api-Key: YOUR_API_KEY" \
  "https://dcc.anystupididea.com/quote?tags=Motivation,Business"
```

**Get Available Tags**
```bash
curl -H "X-Api-Key: YOUR_API_KEY" \
  https://dcc.anystupididea.com/tags
```

### Admin Endpoints

**Authenticate**
```bash
aws cognito-idp admin-initiate-auth \
  --user-pool-id us-east-1_ecyuILBAu \
  --client-id 2idvhvlhgbheglr0hptel5j55 \
  --auth-flow ADMIN_NO_SRP_AUTH \
  --auth-parameters USERNAME=admin@dcc.com,PASSWORD=AdminPass123!
```

**Manage Quotes**
```bash
# List all quotes
curl -H "Authorization: Bearer YOUR_ID_TOKEN" \
  https://dcc.anystupididea.com/admin/quotes

# Create quote
curl -X POST -H "Authorization: Bearer YOUR_ID_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"quote":"...", "author":"...", "tags":["..."]}' \
  https://dcc.anystupididea.com/admin/quotes
```

## 📋 Admin Features

### Admin Dashboard
- **Filter by Tag**: Dropdown filter showing quote counts per tag
- **Sort Options**: Quote text, Author name, or Created date
- **Duplicate Cleanup**: Intelligent detection and removal
- **Batch Import**: Google Sheets TSV import with progress tracking
- **Real-time Updates**: Instant synchronization with public API

### Tag Management
- **Individual Operations**: Add, rename, delete tags
- **Automatic Sync**: Quote updates when tags change
- **Unused Cleanup**: One-click removal of orphaned tags
- **Data Integrity**: Validation and duplicate prevention

### Import System
1. Copy data from Google Sheets (TSV format)
2. Admin Dashboard → Menu → Import Quotes
3. Paste data and preview
4. Import with real-time progress tracking
5. Handles rate limiting automatically

## 🔧 Project Structure

```
quote-me/
├── README.md               # This file
├── CLAUDE.md              # Claude Code guidance
├── WEB_DEPLOYMENT.md      # Web deployment guide
├── deploy-web.sh          # Web deployment script
├── web-infrastructure.yaml # CloudFormation template
├── update_env.sh          # Environment sync script
├── aws/                   # Backend infrastructure
│   ├── template.yaml      # SAM template
│   ├── lambda/
│   │   ├── quote_handler.py
│   │   ├── admin_handler.py
│   │   └── options_handler.py  # CORS handler
│   └── samconfig.toml
├── dcc_mobile/           # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/     # API services
│   │   └── screens/      # UI screens
│   ├── web/              # Web assets
│   └── pubspec.yaml
└── tests/                # Test suites
    ├── test_api.sh
    ├── test_admin_api.sh
    └── test_tag_*.py
```

## 📊 Performance & Security

### Performance
- **API Response**: < 200ms average latency
- **Tag Retrieval**: O(1) with metadata caching
- **Web Loading**: < 2s initial load with CDN
- **Mobile**: 60fps smooth animations
- **Auto-scaling**: Handles traffic spikes automatically

### Security
- **Authentication**: AWS Cognito with JWT tokens
- **API Security**: Dual-layer (API Keys + JWT)
- **HTTPS Only**: SSL/TLS encryption enforced
- **CORS**: Properly configured for web access
- **Rate Limiting**: DDoS protection via API Gateway
- **Input Validation**: Server-side validation

### Resilience
- **Auto-retry**: 3 attempts with exponential backoff
- **Error Recovery**: Graceful network failure handling
- **User Feedback**: Clear error messages
- **State Management**: Persistent settings
- **Offline Support**: Cached data when available

## 🧪 Testing

### API Tests
```bash
# Public API test suite
./tests/test_api.sh

# Admin API regression tests
./tests/test_admin_api.sh

# Tag management tests
python3 tests/test_tag_editor.py
python3 tests/test_tag_cleanup.py
```

### Flutter Tests
```bash
cd dcc_mobile
flutter test
```

## 🚢 Deployment

### Backend
```bash
cd aws
sam build
sam deploy --guided  # First time
sam deploy           # Updates
```

### Mobile Apps
```bash
# iOS
flutter build ios --release

# Android
flutter build apk --release
```

### Web App
```bash
# Full deployment
./deploy-web.sh

# Update only
cd dcc_mobile
flutter build web --release
aws s3 sync build/web/ s3://YOUR_BUCKET/ --delete
aws cloudfront create-invalidation --distribution-id YOUR_ID --paths "/*"
```

## 🎯 Roadmap

- [ ] User accounts and favorites
- [ ] Social sharing features
- [ ] Daily quote notifications
- [ ] Quote collections/categories
- [ ] Analytics dashboard
- [ ] Multi-language support
- [ ] API rate limit increases
- [ ] GraphQL API option

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

For issues and questions:
- Open an issue on GitHub
- Contact: support@quoteme.app

## 🙏 Acknowledgments

- AWS for serverless infrastructure
- Flutter team for the amazing framework
- All contributors and testers
- Quote authors and sources

---

**Quote Me** - Inspiring quotes at your fingertips 💡

Built with ❤️ using Flutter and AWS
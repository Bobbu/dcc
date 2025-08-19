# DCC API Deployment Guide

## Current Deployment Architecture

### Primary Deployment Scripts (USE THESE)
- **`deploy-optimized-full.sh`** - Complete infrastructure deployment from scratch
- **`deploy-optimized.sh`** - Lambda function updates only (for existing infrastructure)

### Primary Template
- **`template-optimized.yaml`** - Complete SAM template with all features including:
  - Optimized DynamoDB table with GSI indexes
  - All Lambda functions (quote, admin, auth, openai, migration, stream processor)
  - Complete API Gateway setup including `/admin/search` endpoint
  - Cognito User Pool with proper authorizers
  - Custom domain support
  - CORS handling

### Obsolete/Archive Files
- `template-original.yaml` - Original template (potentially obsolete)
- `template-obsolete-note.md` - Explanation of obsolete template
- `deploy.sh.original` - Original deployment script (potentially obsolete)  
- `add-search-route.sh.original` - Manual route addition script (obsolete)

## Deployment Commands

### Fresh Deployment
```bash
cd aws
./deploy-optimized-full.sh
```

### Update Existing Lambda Functions Only  
```bash
cd aws
./deploy-optimized.sh
```

### Prerequisites
- AWS CLI configured
- SAM CLI installed
- `.env.deployment` file with OpenAI API key

## Features Included
- ✅ Server-side search at `/admin/search` 
- ✅ Pagination support in admin APIs
- ✅ Complete CRUD operations for quotes and tags
- ✅ AI tag generation via OpenAI proxy
- ✅ Data export functionality at `/admin/export`
- ✅ Single table DynamoDB design with GSI indexes
- ✅ Proper CORS and authentication

## Architecture
The system uses a single table DynamoDB design (`dcc-quotes-optimized`) with:
- TypeDateIndex for fast type-based queries
- AuthorDateIndex for author-based filtering  
- TagQuoteIndex for tag-based filtering
- SearchIndex for future full-text search enhancement

All API routes go through a single API Gateway that routes to appropriate Lambda functions based on path and method.
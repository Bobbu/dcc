# DCC API - AWS Deployment

This directory contains the AWS SAM application for the Quote Me API backend.

## Architecture

- **API Gateway**: REST API with custom domain support
- **Lambda Functions**: 
  - Quote retrieval (public with API key)
  - Admin CRUD operations (Cognito JWT auth)
  - OpenAI proxy for tag generation (secure)
- **DynamoDB**: Quote storage with tag metadata
- **Cognito**: User authentication and authorization

## Prerequisites

1. AWS CLI configured with appropriate permissions
2. SAM CLI installed
3. OpenAI API key

## Setup

1. **Create deployment environment file** (keep this local, never commit):
   ```bash
   cp .env.deployment.example .env.deployment
   # Edit .env.deployment with your OpenAI API key
   ```

2. **Deploy to AWS**:
   ```bash
   ./deploy.sh
   ```

## Environment Configuration

Create `.env.deployment` with:
```bash
# OpenAI API Key for tag generation
OPENAI_API_KEY=sk-proj-your-key-here

# Optional: Certificate ARN for custom domain
CERTIFICATE_ARN=arn:aws:acm:us-east-1:123456789:certificate/abc-123
```

## Security

- **OpenAI API Key**: Stored securely in Lambda environment variables, never exposed to client
- **Authentication**: Dual-layer (API keys for public, JWT for admin)
- **CORS**: Configured for web and mobile app access
- **Rate Limiting**: Built-in API Gateway limits

## Endpoints

### Public (API Key Required)
- `GET /quote` - Get random quote with optional tag filtering
- `GET /tags` - Get all available tags

### Admin (JWT Authentication Required)
- `POST /admin/quotes` - Create quote
- `PUT /admin/quotes/{id}` - Update quote  
- `DELETE /admin/quotes/{id}` - Delete quote
- `GET /admin/quotes` - List all quotes
- `POST /admin/generate-tags` - **AI tag generation (secure proxy)**

### Admin Tag Management
- `GET /admin/tags` - Get all tags
- `POST /admin/tags` - Add new tag
- `PUT /admin/tags/{tag}` - Rename tag
- `DELETE /admin/tags/{tag}` - Delete tag
- `DELETE /admin/tags/unused` - Clean unused tags

## Monitoring

- CloudWatch logs for all Lambda functions
- API Gateway access logs
- DynamoDB metrics

## Cost Optimization

- Lambda functions with appropriate timeout settings
- DynamoDB on-demand billing
- API Gateway caching (if enabled)
- OpenAI costs controlled through your secure proxy
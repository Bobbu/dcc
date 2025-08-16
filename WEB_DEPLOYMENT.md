# Quote Me Web App Deployment Guide

This guide will help you deploy the Quote Me Flutter app as a web application on AWS at `https://quote-me.anystupididea.com`.

## Prerequisites

1. **AWS CLI** configured with appropriate permissions
2. **Flutter SDK** installed and configured
3. **Domain ownership** of `anystupididea.com` with Route53 hosted zone
4. **SSL Certificate** in AWS Certificate Manager (ACM) for `quote-me.anystupididea.com`

## Quick Deployment (Automated)

Run the automated deployment script:

```bash
./deploy-web.sh
```

This script will:
- Build the Flutter web app
- Deploy AWS infrastructure (S3, CloudFront, Route53)
- Upload files to S3
- Configure CDN and SSL
- Set up custom domain

## Manual Deployment Steps

### 1. SSL Certificate Setup

First, create an SSL certificate in AWS Certificate Manager (us-east-1 region):

```bash
# Request a certificate (replace with your domain)
aws acm request-certificate \
  --domain-name quote-me.anystupididea.com \
  --validation-method DNS \
  --region us-east-1
```

Follow the DNS validation process to verify domain ownership.

### 2. Build Flutter Web App

```bash
cd dcc_mobile
flutter clean
flutter pub get
flutter build web --release
cd ..
```

### 3. Deploy AWS Infrastructure

Update the `web-infrastructure.yaml` file with your certificate ARN and hosted zone ID, then deploy:

```bash
aws cloudformation deploy \
  --template-file web-infrastructure.yaml \
  --stack-name quote-me-web-app \
  --parameter-overrides \
      DomainName=quote-me.anystupididea.com \
      CertificateArn=your-certificate-arn \
  --capabilities CAPABILITY_IAM \
  --region us-east-1
```

### 4. Upload Files to S3

Get the S3 bucket name from the CloudFormation output and upload:

```bash
# Get bucket name
BUCKET_NAME=$(aws cloudformation describe-stacks \
  --stack-name quote-me-web-app \
  --query "Stacks[0].Outputs[?OutputKey=='WebAppBucketName'].OutputValue" \
  --output text)

# Upload static assets with long cache
aws s3 sync dcc_mobile/build/web/ s3://$BUCKET_NAME/ \
  --delete \
  --cache-control "public, max-age=31536000" \
  --exclude "*.html"

# Upload HTML files with no-cache for SPA routing
aws s3 sync dcc_mobile/build/web/ s3://$BUCKET_NAME/ \
  --cache-control "no-cache" \
  --include "*.html"
```

### 5. Invalidate CloudFront Cache

```bash
# Get distribution ID
DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
  --stack-name quote-me-web-app \
  --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
  --output text)

# Create invalidation
aws cloudfront create-invalidation \
  --distribution-id $DISTRIBUTION_ID \
  --paths "/*"
```

## Architecture

The deployment creates:

- **S3 Bucket**: Hosts static web files
- **CloudFront Distribution**: Global CDN with SSL
- **Route53 Record**: Custom domain pointing to CloudFront
- **Origin Access Control**: Secure S3 access from CloudFront only

## Configuration Details

### S3 Configuration
- **Bucket Name**: `quote-me.anystupididea.com-web-app`
- **Website Hosting**: Enabled with `index.html` as default
- **Public Access**: Blocked (accessed only via CloudFront)

### CloudFront Configuration
- **Custom Domain**: `quote-me.anystupididea.com`
- **SSL Certificate**: From ACM (us-east-1)
- **Cache Behavior**: 
  - Static assets: Long-term caching (1 year)
  - HTML files: No caching (for SPA routing)
- **Error Pages**: 403/404 redirect to `index.html` for SPA support

### Route53 Configuration
- **Record Type**: A record (alias)
- **Target**: CloudFront distribution domain
- **TTL**: Automatic (alias record)

## Updating the App

To deploy updates:

1. Make changes to your Flutter app
2. Rebuild: `flutter build web --release`
3. Re-upload to S3: `aws s3 sync dcc_mobile/build/web/ s3://$BUCKET_NAME/ --delete`
4. Invalidate CloudFront: `aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*"`

## Environment Variables

The web app will use the same `.env` file as the mobile app. Ensure your API endpoints are accessible from browsers (CORS configured).

## Troubleshooting

### Common Issues

1. **SSL Certificate Issues**
   - Ensure certificate is in us-east-1 region
   - Verify DNS validation is complete

2. **DNS Not Resolving**
   - Check Route53 hosted zone configuration
   - Verify domain nameservers point to Route53

3. **App Not Loading**
   - Check S3 bucket policy allows CloudFront access
   - Verify CloudFront distribution is deployed
   - Check browser console for CORS errors

4. **CORS Errors**
   - Ensure API Gateway has CORS enabled
   - Verify `Access-Control-Allow-Origin` headers

### Useful Commands

```bash
# Check certificate status
aws acm describe-certificate --certificate-arn YOUR_CERT_ARN --region us-east-1

# Check CloudFront distribution status
aws cloudfront get-distribution --id YOUR_DISTRIBUTION_ID

# Check Route53 record
aws route53 list-resource-record-sets --hosted-zone-id YOUR_ZONE_ID

# Test domain resolution
nslookup quote-me.anystupididea.com
dig quote-me.anystupididea.com
```

## Security Considerations

- S3 bucket is private (no public access)
- All traffic uses HTTPS (HTTP redirects to HTTPS)
- CloudFront provides DDoS protection
- Origin Access Control prevents direct S3 access

## Cost Optimization

- CloudFront PriceClass_100 (North America & Europe)
- S3 with versioning for rollback capability
- Efficient caching reduces origin requests

## Next Steps

After deployment:
1. Test the application at `https://quote-me.anystupididea.com`
2. Verify all features work in web browser
3. Set up monitoring and logging if needed
4. Consider setting up CI/CD pipeline for automated deployments
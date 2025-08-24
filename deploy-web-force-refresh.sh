#!/bin/bash

# Enhanced Flutter Web App AWS Deployment Script with Aggressive Cache Busting
# This version adds version-based cache busting and more aggressive invalidation

set -e

# Configuration (can be overridden via environment variables or arguments)
DOMAIN_NAME="${1:-${DOMAIN_NAME:-quote-me.anystupididea.com}}"
STACK_NAME="${2:-${STACK_NAME:-quote-me-web-app}}"
REGION="${3:-${REGION:-us-east-1}}"
FLUTTER_APP_DIR="${4:-${FLUTTER_APP_DIR:-dcc_mobile}}"

# Generate version timestamp for cache busting
VERSION_TIMESTAMP=$(date +%s)

# Extract root domain from full domain
ROOT_DOMAIN=$(echo $DOMAIN_NAME | sed 's/^[^.]*\.//')

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Flutter Web App AWS Deployment (Enhanced Cache Busting)${NC}"
echo "================================================"
echo "Domain: $DOMAIN_NAME"
echo "Root Domain: $ROOT_DOMAIN"
echo "Stack: $STACK_NAME"
echo "Region: $REGION"
echo "Flutter App Directory: $FLUTTER_APP_DIR"
echo "Version Timestamp: $VERSION_TIMESTAMP"
echo "================================================"
echo ""

# Function to print step headers
print_step() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "----------------------------------------"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to print warnings
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Enhanced function to build Flutter web app with cache busting
build_flutter_app_with_cache_busting() {
    print_step "Building Flutter Web App with Cache Busting"
    
    if [ ! -d "$FLUTTER_APP_DIR" ]; then
        print_error "Flutter app directory not found: $FLUTTER_APP_DIR"
        exit 1
    fi
    
    cd $FLUTTER_APP_DIR
    
    echo "Cleaning previous build..."
    flutter clean
    
    echo "Getting dependencies..."
    flutter pub get
    
    echo "Building for web (release mode) with version cache busting..."
    flutter build web --release
    
    if [ ! -d "build/web" ]; then
        print_error "Flutter web build failed - build/web directory not found"
        exit 1
    fi
    
    # Add cache-busting version to HTML files
    echo "Adding cache-busting version to HTML files..."
    find build/web -name "*.html" -type f -exec sed -i '' "s/flutter_bootstrap\.js/flutter_bootstrap.js?v=$VERSION_TIMESTAMP/g" {} +
    find build/web -name "*.html" -type f -exec sed -i '' "s/main\.dart\.js/main.dart.js?v=$VERSION_TIMESTAMP/g" {} +
    
    # Add version meta tag to index.html for debugging
    if [ -f "build/web/index.html" ]; then
        sed -i '' "/<meta charset=\"UTF-8\">/a\\
<meta name=\"app-version\" content=\"$VERSION_TIMESTAMP\">\\
<meta name=\"cache-control\" content=\"no-cache, no-store, must-revalidate\">\\
<meta name=\"pragma\" content=\"no-cache\">\\
<meta name=\"expires\" content=\"0\">" build/web/index.html
    fi
    
    cd ..
    print_success "Flutter web app built with cache busting (v$VERSION_TIMESTAMP)"
}

# Enhanced function to upload files to S3 with more aggressive cache busting
upload_to_s3_enhanced() {
    print_step "Uploading Files to S3 (Enhanced Cache Busting)"
    
    # Get S3 bucket name from CloudFormation output
    BUCKET_NAME=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='WebAppBucketName'].OutputValue" \
        --output text)
    
    if [ -z "$BUCKET_NAME" ]; then
        print_error "Could not retrieve S3 bucket name from stack outputs"
        exit 1
    fi
    
    echo "S3 Bucket: $BUCKET_NAME"
    echo "Version: $VERSION_TIMESTAMP"
    
    # First, delete all existing files to ensure clean deployment
    echo "Cleaning existing files from S3..."
    aws s3 rm s3://$BUCKET_NAME/ --recursive --region $REGION
    
    # Upload static assets with version-based cache headers
    echo "Uploading static assets with versioned cache..."
    aws s3 sync $FLUTTER_APP_DIR/build/web/ s3://$BUCKET_NAME/ \
        --delete \
        --cache-control "public, max-age=31536000" \
        --metadata "version=$VERSION_TIMESTAMP" \
        --exclude "*.html" \
        --exclude "*.json" \
        --exclude "*.js" \
        --region $REGION
    
    # Upload JS files with shorter cache and version metadata
    echo "Uploading JavaScript files..."
    aws s3 sync $FLUTTER_APP_DIR/build/web/ s3://$BUCKET_NAME/ \
        --cache-control "public, max-age=3600" \
        --metadata "version=$VERSION_TIMESTAMP" \
        --exclude "*" \
        --include "*.js" \
        --region $REGION
    
    # Upload HTML and JSON files with aggressive no-cache headers
    echo "Uploading HTML and JSON files with no-cache..."
    aws s3 sync $FLUTTER_APP_DIR/build/web/ s3://$BUCKET_NAME/ \
        --cache-control "no-cache, no-store, must-revalidate, proxy-revalidate" \
        --metadata "version=$VERSION_TIMESTAMP" \
        --exclude "*" \
        --include "*.html" \
        --include "*.json" \
        --region $REGION
    
    print_success "Files uploaded to S3 with version $VERSION_TIMESTAMP"
}

# Enhanced function to invalidate CloudFront cache more aggressively
invalidate_cloudfront_enhanced() {
    print_step "Enhanced CloudFront Cache Invalidation"
    
    # Get CloudFront distribution ID from CloudFormation output
    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --region $REGION \
        --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
        --output text)
    
    if [ -z "$DISTRIBUTION_ID" ]; then
        print_error "Could not retrieve CloudFront distribution ID"
        exit 1
    fi
    
    echo "CloudFront Distribution: $DISTRIBUTION_ID"
    echo "Creating aggressive cache invalidation..."
    
    # Create multiple invalidations for different file types
    INVALIDATION_ID1=$(aws cloudfront create-invalidation \
        --distribution-id $DISTRIBUTION_ID \
        --paths "/*" \
        --region $REGION \
        --query "Invalidation.Id" \
        --output text)
    
    # Wait a moment then create another specific invalidation
    sleep 2
    
    INVALIDATION_ID2=$(aws cloudfront create-invalidation \
        --distribution-id $DISTRIBUTION_ID \
        --paths "/index.html" "/main.dart.js" "/flutter_bootstrap.js" "/manifest.json" \
        --region $REGION \
        --query "Invalidation.Id" \
        --output text)
    
    print_success "CloudFront cache invalidations created:"
    echo "  • Global invalidation: $INVALIDATION_ID1"
    echo "  • Specific files: $INVALIDATION_ID2"
}

# Function to create a cache-busting notification
create_cache_busting_summary() {
    print_step "Cache Busting Summary"
    
    echo ""
    echo -e "${GREEN}🔄 Enhanced Cache Busting Applied:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• App Version: $VERSION_TIMESTAMP"
    echo "• S3 bucket completely cleared before upload"
    echo "• HTML/JSON files: no-cache headers"
    echo "• JS files: 1-hour cache with version metadata"
    echo "• Static assets: 1-year cache with version metadata"
    echo "• CloudFront: Multiple aggressive invalidations"
    echo "• HTML files: Version query parameters added"
    echo ""
    echo -e "${YELLOW}⚠️  For Immediate Testing:${NC}"
    echo "1. Hard refresh: Ctrl+Shift+R (Win/Linux) or Cmd+Shift+R (Mac)"
    echo "2. Open DevTools → Network → Check 'Disable cache'"
    echo "3. Try incognito/private browsing mode"
    echo "4. Check app version in DevTools → Elements → <meta name=\"app-version\">"
    echo ""
}

# Source the original deployment functions we still need
source deploy-web.sh

# Override main function for enhanced deployment
main() {
    echo -e "${BLUE}Starting enhanced deployment process...${NC}"
    echo ""
    
    # Set error trap
    trap 'handle_error "$STEP"' ERR
    
    STEP="AWS CLI Check"
    check_aws_cli
    
    STEP="Flutter Check"
    check_flutter
    
    STEP="Hosted Zone Lookup"
    get_hosted_zone_id
    
    STEP="Template Validation"
    validate_template
    
    STEP="Enhanced Flutter Build"
    build_flutter_app_with_cache_busting
    
    STEP="Infrastructure Deployment"
    deploy_infrastructure
    
    STEP="Certificate Validation"
    wait_for_certificate
    
    STEP="Enhanced S3 Upload"
    upload_to_s3_enhanced
    
    STEP="Enhanced CloudFront Invalidation"
    invalidate_cloudfront_enhanced
    
    # Clear error trap
    trap - ERR
    
    create_cache_busting_summary
    show_completion_info
}

# Check if help is requested
if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
    echo "Enhanced deployment script with aggressive cache busting"
    echo "Usage: $0 [DOMAIN_NAME] [STACK_NAME] [REGION] [FLUTTER_APP_DIR]"
    echo ""
    echo "This script includes:"
    echo "• Version-based cache busting with timestamps"
    echo "• Complete S3 bucket clearing before upload"
    echo "• Enhanced cache headers for different file types"
    echo "• Multiple CloudFront invalidations"
    echo "• HTML file versioning for JS resources"
    exit 0
fi

# Run main deployment if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
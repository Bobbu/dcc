#!/bin/bash

# setup_domain.sh - Set up custom domain for DCC API
# This script helps configure SSL certificate and DNS for dcc.anystupididea.com

set -e

echo "🌐 DCC Custom Domain Setup"
echo "========================="
echo ""

# Configuration
DOMAIN_NAME="dcc.anystupididea.com"
REGION="us-east-1"
STACK_NAME="dcc-demo-sam-app"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check prerequisites
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install AWS CLI first."
    exit 1
fi

if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

print_status "Setting up custom domain: $DOMAIN_NAME"
echo ""

# Step 1: Check if certificate exists
print_status "Step 1: Checking for SSL certificate..."

# First try exact match
CERT_ARN=$(aws acm list-certificates \
    --region us-east-1 \
    --query "CertificateList[?DomainName=='$DOMAIN_NAME'].CertificateArn | [0]" \
    --output text 2>/dev/null || echo "None")

# If no exact match, look for wildcard or SAN certificates that cover our domain
if [ "$CERT_ARN" = "None" ] || [ "$CERT_ARN" = "null" ]; then
    print_status "No exact match found, checking for wildcard/SAN certificates..."
    
    # Extract the parent domain (anystupididea.com from dcc.anystupididea.com)
    PARENT_DOMAIN=$(echo "$DOMAIN_NAME" | sed 's/^[^.]*\.//')
    
    # Look for certificates that might cover this subdomain
    # Check for: *.anystupididea.com or anystupididea.com with SANs
    ALL_CERTS=$(aws acm list-certificates --region us-east-1 --output json)
    
    for cert_arn in $(echo "$ALL_CERTS" | jq -r '.CertificateList[].CertificateArn'); do
        # Get certificate details including SANs
        CERT_DETAILS=$(aws acm describe-certificate --certificate-arn "$cert_arn" --region us-east-1 --output json)
        
        # Check if this certificate covers our domain
        COVERS_DOMAIN=$(echo "$CERT_DETAILS" | jq -r --arg domain "$DOMAIN_NAME" '
            (.Certificate.DomainName == $domain) or
            (.Certificate.DomainName == ("*." + ($domain | sub("^[^.]*\\."; "")))) or
            ((.Certificate.SubjectAlternativeNames // []) | any(. == $domain)) or
            ((.Certificate.SubjectAlternativeNames // []) | any(. == ("*." + ($domain | sub("^[^.]*\\."; "")))))
        ')
        
        if [ "$COVERS_DOMAIN" = "true" ]; then
            CERT_ARN="$cert_arn"
            CERT_DOMAIN=$(echo "$CERT_DETAILS" | jq -r '.Certificate.DomainName')
            print_success "Found certificate covering $DOMAIN_NAME: $CERT_DOMAIN"
            break
        fi
    done
fi

if [ "$CERT_ARN" = "None" ] || [ "$CERT_ARN" = "null" ]; then
    print_warning "No certificate found for $DOMAIN_NAME"
    echo ""
    echo "To set up the custom domain, you need an SSL certificate in AWS Certificate Manager."
    echo "You can either:"
    echo ""
    echo "Option 1: Create certificate manually in AWS Console"
    echo "  1. Go to AWS Certificate Manager (ACM) in us-east-1 region"
    echo "  2. Request a public certificate for: $DOMAIN_NAME"
    echo "  3. Validate domain ownership (DNS or email validation)"
    echo "  4. Wait for certificate to be issued"
    echo "  5. Re-run this script"
    echo ""
    echo "Option 2: Create certificate via CLI (requires DNS access)"
    read -p "Would you like to request a certificate now via CLI? (y/N): " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Requesting SSL certificate for $DOMAIN_NAME..."
        
        CERT_ARN=$(aws acm request-certificate \
            --domain-name "$DOMAIN_NAME" \
            --validation-method DNS \
            --region us-east-1 \
            --query 'CertificateArn' \
            --output text)
        
        print_success "Certificate requested: $CERT_ARN"
        print_warning "Certificate validation required!"
        echo ""
        echo "Next steps:"
        echo "1. Go to AWS Certificate Manager in the console"
        echo "2. Find your certificate and click on it"
        echo "3. Add the DNS validation CNAME record to your domain's DNS"
        echo "4. Wait for certificate status to change to 'Issued'"
        echo "5. Re-run this script to complete domain setup"
        echo ""
        exit 0
    else
        print_status "Certificate setup skipped. Please create certificate manually and re-run this script."
        exit 0
    fi
else
    print_success "Found certificate: ${CERT_ARN:0:50}..."
    
    # Check certificate status
    CERT_STATUS=$(aws acm describe-certificate \
        --certificate-arn "$CERT_ARN" \
        --region us-east-1 \
        --query 'Certificate.Status' \
        --output text)
    
    if [ "$CERT_STATUS" != "ISSUED" ]; then
        print_error "Certificate status: $CERT_STATUS (must be ISSUED)"
        echo "Please complete certificate validation in AWS Console and try again."
        exit 1
    fi
    
    print_success "Certificate status: $CERT_STATUS"
fi

echo ""

# Step 2: Update CloudFormation stack with custom domain
print_status "Step 2: Updating CloudFormation stack with custom domain..."

aws cloudformation update-stack \
    --stack-name "$STACK_NAME" \
    --use-previous-template \
    --parameters \
        ParameterKey=CustomDomainName,ParameterValue="$DOMAIN_NAME" \
        ParameterKey=CertificateArn,ParameterValue="$CERT_ARN" \
    --capabilities CAPABILITY_IAM \
    --region "$REGION"

print_status "Stack update initiated. Waiting for completion..."

aws cloudformation wait stack-update-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

print_success "Stack updated successfully!"

# Step 3: Get CloudFront domain for DNS setup
print_status "Step 3: Getting DNS configuration information..."

CLOUDFRONT_DOMAIN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs[?OutputKey==`CustomDomainTarget`].OutputValue | [0]' \
    --output text)

if [ "$CLOUDFRONT_DOMAIN" = "null" ] || [ -z "$CLOUDFRONT_DOMAIN" ]; then
    print_error "Could not retrieve CloudFront domain from stack outputs"
    exit 1
fi

echo ""
print_success "Custom domain setup complete!"
echo ""
print_warning "DNS Configuration Required:"
echo "To complete the setup, add this DNS record to your domain:"
echo ""
echo "  Type: CNAME"
echo "  Name: dcc"
echo "  Value: $CLOUDFRONT_DOMAIN"
echo "  TTL: 300 (or default)"
echo ""

# Step 4: Test the domain
print_status "Testing domain resolution..."

if nslookup "$DOMAIN_NAME" > /dev/null 2>&1; then
    print_success "Domain $DOMAIN_NAME resolves to an IP address"
    
    # Test if it resolves to CloudFront
    RESOLVED_IP=$(nslookup "$DOMAIN_NAME" | grep -A 1 "Name:" | tail -n 1 | awk '{print $2}' || echo "")
    CF_IP=$(nslookup "$CLOUDFRONT_DOMAIN" | grep -A 1 "Name:" | tail -n 1 | awk '{print $2}' || echo "")
    
    if [ "$RESOLVED_IP" = "$CF_IP" ]; then
        print_success "Domain correctly points to CloudFront distribution"
        echo ""
        print_status "Custom domain is ready! You can now use:"
        echo "  https://$DOMAIN_NAME/quote"
    else
        print_warning "Domain doesn't point to CloudFront yet. DNS propagation may take time."
    fi
else
    print_warning "Domain $DOMAIN_NAME doesn't resolve yet. Please add the DNS record above."
fi

echo ""
print_status "Next steps:"
echo "1. Add the CNAME record to your DNS provider"
echo "2. Wait for DNS propagation (usually 5-15 minutes)"
echo "3. Test the API: curl -H \"x-api-key: YOUR_KEY\" https://$DOMAIN_NAME/quote"
echo "4. Run '../update_env.sh' to update environment files with custom domain"

echo ""
print_success "Domain setup complete! 🎉"
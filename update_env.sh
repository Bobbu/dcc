#!/bin/bash

# update_env.sh - Automatically update .env files with current AWS API Gateway values
# This script queries AWS CloudFormation to get the current API endpoint and key,
# then updates all .env files in the project with the current values.

set -e  # Exit on any error

echo "🔍 DCC Environment Updater"
echo "=========================="
echo ""

# Configuration
STACK_NAME="dcc-demo-sam-app"
REGION="us-east-1"
# Will be used to find all .env files in the project
ENV_FILES=(
    "tests/.env"
    "dcc_mobile/.env"
)


# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Check if AWS CLI is installed and configured
if ! command -v aws &> /dev/null; then
    print_error "AWS CLI not found. Please install and configure AWS CLI first."
    exit 1
fi

print_status "Checking AWS credentials..."
if ! aws sts get-caller-identity &> /dev/null; then
    print_error "AWS credentials not configured or invalid. Please run 'aws configure' first."
    exit 1
fi

print_success "AWS CLI configured and accessible"

# Query CloudFormation stack for outputs
print_status "Querying CloudFormation stack: $STACK_NAME"

if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" &> /dev/null; then
    print_error "CloudFormation stack '$STACK_NAME' not found in region '$REGION'"
    print_warning "Make sure the stack is deployed and the name/region are correct."
    exit 1
fi

# Get stack outputs
STACK_OUTPUTS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --query 'Stacks[0].Outputs' \
    --output json)

# Extract values from outputs
API_ENDPOINT=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="QuoteEndpoint") | .OutputValue')
CUSTOM_DOMAIN_URL=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="CustomDomainQuoteEndpoint") | .OutputValue')
API_KEY_ID=$(echo "$STACK_OUTPUTS" | jq -r '.[] | select(.OutputKey=="ApiKeyValue") | .OutputValue')

# Use custom domain if available, otherwise use default API Gateway URL
if [ "$CUSTOM_DOMAIN_URL" != "null" ] && [ "$CUSTOM_DOMAIN_URL" != "Not configured" ] && [ -n "$CUSTOM_DOMAIN_URL" ]; then
    API_ENDPOINT="$CUSTOM_DOMAIN_URL"
    print_success "Using custom domain endpoint: $CUSTOM_DOMAIN_URL"
else
    print_status "Custom domain not configured, using API Gateway endpoint"
fi

# Get the actual API key value (the output only gives us the key ID)
print_status "Retrieving API key value..."
API_KEY=$(aws apigateway get-api-key \
    --api-key "$API_KEY_ID" \
    --include-value \
    --region "$REGION" \
    --query 'value' \
    --output text)

# Validate we got the values
if [ "$API_ENDPOINT" = "null" ] || [ -z "$API_ENDPOINT" ]; then
    print_error "Could not retrieve API ENDPOINT from CloudFormation outputs"
    exit 1
fi

if [ "$API_KEY" = "null" ] || [ -z "$API_KEY" ]; then
    print_error "Could not retrieve API key value"
    exit 1
fi

# Display found values
echo ""
print_success "Found current AWS values:"
echo "  API ENDPOINT: $API_ENDPOINT"
echo "  API Key: ${API_KEY:0:8}********"
echo ""

# Find all .env files in the project
# Check which .env files exist
EXISTING_FILES=()
for file in "${ENV_FILES[@]}"; do
    if [ -f "$file" ]; then
        EXISTING_FILES+=("$file")
    fi
done

if [ ${#EXISTING_FILES[@]} -eq 0 ]; then
    print_warning "No .env files found to update"
    echo "Expected locations: ${ENV_FILES[*]}"
    exit 0
fi

echo "Files to be updated:"
for file in "${EXISTING_FILES[@]}"; do
    echo "  - $file"
done
echo ""

# Confirmation prompt
print_warning "This will overwrite the API_ENDPOINT and API_KEY values in the above files."
read -p "Do you want to proceed? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Operation cancelled by user"
    exit 0
fi

echo ""
print_status "Updating .env files..."

# Function to update a single .env file
update_env_file() {
    local file="$1"
    local temp_file="${file}.tmp"
    
    print_status "Updating $file..."
    
    # Create temp file with updated values
    if [ -f "$file" ]; then
        # Update existing file, preserving other variables
        sed -E \
            -e "s|^API_KEY=.*|API_KEY=$API_KEY|g" \
            -e "s|^API_ENDPOINT=.*|API_ENDPOINT=$API_ENDPOINT|g" \
            "$file" > "$temp_file"
        
        # If no API_ENDPOINT line existed, add it
        if ! grep -q "^API_ENDPOINT=" "$temp_file"; then
            echo "API_ENDPOINT=$API_ENDPOINT" >> "$temp_file"
        fi
        
        # If no API_KEY line existed, add it  
        if ! grep -q "^API_KEY=" "$temp_file"; then
            echo "API_KEY=$API_KEY" >> "$temp_file"
        fi
        
        # For tests folder, also handle API_ENDPOINT
        if [[ "$file" == "tests/.env" ]] && ! grep -q "^API_ENDPOINT=" "$temp_file"; then
            echo "API_ENDPOINT=$API_ENDPOINT" >> "$temp_file"
        fi
    else
        # Create new file
        if [[ "$file" == "tests/.env" ]]; then
            cat > "$temp_file" << EOF
API_ENDPOINT=$API_ENDPOINT
API_KEY=$API_KEY
EOF
        else
            cat > "$temp_file" << EOF
API_ENDPOINT=$API_ENDPOINT
API_KEY=$API_KEY
EOF
        fi
    fi
    
    # Replace original with temp file
    mv "$temp_file" "$file"
    print_success "Updated $file"
}

# Update each .env file
for file in "${EXISTING_FILES[@]}"; do
    update_env_file "$file"
done

echo ""
print_success "All .env files updated successfully!"
print_status "Your applications should now use the current AWS API values."

# Offer to run tests
echo ""
read -p "Would you like to run the API tests to verify the update? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_status "Running API tests..."
    echo ""
    if [ -f "tests/test_api.sh" ]; then
        cd tests && ./test_api.sh
    else
        print_warning "Test script not found at tests/test_api.sh"
    fi
fi

echo ""
print_success "Environment update complete! 🎉"
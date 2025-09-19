#!/bin/bash
# Configure Google and Apple Identity Providers for Cognito User Pool
# This script can be used as an alternative to CloudFormation for setting up federated authentication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== COGNITO IDENTITY PROVIDERS CONFIGURATION ===${NC}"

# Load environment variables if available
if [ -f .env.deployment ]; then
    echo -e "${GREEN}✓ Loading environment variables${NC}"
    source .env.deployment
fi

# Get User Pool ID from CloudFormation
USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name quote-me-api --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' --output text)
USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name quote-me-api --query 'Stacks[0].Outputs[?OutputKey==`UserPoolClientId`].OutputValue' --output text)

if [ -z "$USER_POOL_ID" ]; then
    echo -e "${RED}❌ Could not find User Pool ID from CloudFormation stack${NC}"
    exit 1
fi

echo -e "${GREEN}✓ User Pool ID: $USER_POOL_ID${NC}"
echo -e "${GREEN}✓ User Pool Client ID: $USER_POOL_CLIENT_ID${NC}"

# Function to configure Google Identity Provider
configure_google() {
    echo -e "\n${YELLOW}Configuring Google Identity Provider...${NC}"

    if [ -z "$GOOGLE_CLIENT_ID" ] || [ -z "$GOOGLE_CLIENT_SECRET" ]; then
        echo -e "${RED}❌ GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET environment variables must be set${NC}"
        return 1
    fi

    # Check if Google provider already exists
    if aws cognito-idp describe-identity-provider --user-pool-id "$USER_POOL_ID" --provider-name Google >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Google provider already exists, updating...${NC}"
        aws cognito-idp update-identity-provider \
            --user-pool-id "$USER_POOL_ID" \
            --provider-name Google \
            --provider-details "client_id=$GOOGLE_CLIENT_ID,client_secret=$GOOGLE_CLIENT_SECRET,authorize_scopes=email openid profile" \
            --attribute-mapping "email=email,given_name=given_name,family_name=family_name,name=name"
    else
        echo -e "${BLUE}Creating new Google provider...${NC}"
        aws cognito-idp create-identity-provider \
            --user-pool-id "$USER_POOL_ID" \
            --provider-name Google \
            --provider-type Google \
            --provider-details "client_id=$GOOGLE_CLIENT_ID,client_secret=$GOOGLE_CLIENT_SECRET,authorize_scopes=email openid profile" \
            --attribute-mapping "email=email,given_name=given_name,family_name=family_name,name=name"
    fi

    echo -e "${GREEN}✓ Google Identity Provider configured${NC}"
}

# Function to configure Apple Identity Provider
configure_apple() {
    echo -e "\n${YELLOW}Configuring Apple Identity Provider...${NC}"

    if [ -z "$APPLE_SERVICES_ID" ] || [ -z "$APPLE_TEAM_ID" ] || [ -z "$APPLE_KEY_ID" ] || [ -z "$APPLE_PRIVATE_KEY" ]; then
        echo -e "${RED}❌ APPLE_SERVICES_ID, APPLE_TEAM_ID, APPLE_KEY_ID, and APPLE_PRIVATE_KEY environment variables must be set${NC}"
        return 1
    fi

    # Check if Apple provider already exists
    if aws cognito-idp describe-identity-provider --user-pool-id "$USER_POOL_ID" --provider-name SignInWithApple >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Apple provider already exists, updating...${NC}"
        aws cognito-idp update-identity-provider \
            --user-pool-id "$USER_POOL_ID" \
            --provider-name SignInWithApple \
            --provider-details "client_id=$APPLE_SERVICES_ID,team_id=$APPLE_TEAM_ID,key_id=$APPLE_KEY_ID,private_key=$APPLE_PRIVATE_KEY,authorize_scopes=email name" \
            --attribute-mapping "email=email,given_name=firstName,family_name=lastName,name=name"
    else
        echo -e "${BLUE}Creating new Apple provider...${NC}"
        aws cognito-idp create-identity-provider \
            --user-pool-id "$USER_POOL_ID" \
            --provider-name SignInWithApple \
            --provider-type SignInWithApple \
            --provider-details "client_id=$APPLE_SERVICES_ID,team_id=$APPLE_TEAM_ID,key_id=$APPLE_KEY_ID,private_key=$APPLE_PRIVATE_KEY,authorize_scopes=email name" \
            --attribute-mapping "email=email,given_name=firstName,family_name=lastName,name=name"
    fi

    echo -e "${GREEN}✓ Apple Identity Provider configured${NC}"
}

# Function to update User Pool Client
update_user_pool_client() {
    echo -e "\n${YELLOW}Updating User Pool Client with identity providers and OAuth configuration...${NC}"

    # Get current supported providers
    PROVIDERS="COGNITO"

    # Check which providers exist and add them
    if aws cognito-idp describe-identity-provider --user-pool-id "$USER_POOL_ID" --provider-name Google >/dev/null 2>&1; then
        PROVIDERS="$PROVIDERS,Google"
        echo -e "${GREEN}✓ Adding Google to supported providers${NC}"
    fi

    if aws cognito-idp describe-identity-provider --user-pool-id "$USER_POOL_ID" --provider-name SignInWithApple >/dev/null 2>&1; then
        PROVIDERS="$PROVIDERS,SignInWithApple"
        echo -e "${GREEN}✓ Adding Apple to supported providers${NC}"
    fi

    # Convert comma-separated string to array for AWS CLI
    IFS=',' read -ra PROVIDER_ARRAY <<< "$PROVIDERS"

    # Update the client with OAuth configuration
    aws cognito-idp update-user-pool-client \
        --user-pool-id "$USER_POOL_ID" \
        --client-id "$USER_POOL_CLIENT_ID" \
        --supported-identity-providers "${PROVIDER_ARRAY[@]}" \
        --callback-urls \
            "https://quote-me.anystupididea.com/auth/callback" \
            "quoteme://auth-success" \
            "http://localhost:3000/auth/callback" \
        --logout-urls \
            "https://quote-me.anystupididea.com/" \
            "http://localhost:3000" \
        --allowed-o-auth-flows "code" \
        --allowed-o-auth-scopes "email" "openid" "profile" \
        --allowed-o-auth-flows-user-pool-client \
        --explicit-auth-flows \
            "ALLOW_USER_PASSWORD_AUTH" \
            "ALLOW_REFRESH_TOKEN_AUTH" \
            "ALLOW_USER_SRP_AUTH"

    echo -e "${GREEN}✓ User Pool Client updated with providers: $PROVIDERS${NC}"
    echo -e "${GREEN}✓ OAuth flows enabled with callback URLs configured${NC}"
}

# Main execution
echo -e "\n${BLUE}Available operations:${NC}"
echo "1. Configure Google Identity Provider"
echo "2. Configure Apple Identity Provider"
echo "3. Update User Pool Client"
echo "4. Configure All (Google + Apple + Update Client)"
echo "5. Show current configuration"

if [ $# -eq 0 ]; then
    read -p "Select operation (1-5): " operation
else
    operation=$1
fi

case $operation in
    1)
        configure_google
        ;;
    2)
        configure_apple
        ;;
    3)
        update_user_pool_client
        ;;
    4)
        configure_google
        configure_apple
        update_user_pool_client
        ;;
    5)
        echo -e "\n${BLUE}Current Identity Providers:${NC}"
        aws cognito-idp list-identity-providers --user-pool-id "$USER_POOL_ID" --output table
        echo -e "\n${BLUE}Current User Pool Client Configuration:${NC}"
        aws cognito-idp describe-user-pool-client --user-pool-id "$USER_POOL_ID" --client-id "$USER_POOL_CLIENT_ID" --query 'UserPoolClient.SupportedIdentityProviders' --output table
        ;;
    *)
        echo -e "${RED}❌ Invalid operation${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}🎉 Configuration complete!${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Update Google Cloud Console with new redirect URI:"
echo "   https://quote-me-auth-1757704767.auth.us-east-1.amazoncognito.com/oauth2/idpresponse"
echo "2. Update Apple Developer Portal with new return URL:"
echo "   https://quote-me-auth-1757704767.auth.us-east-1.amazoncognito.com/oauth2/idpresponse"
echo "3. Test federated authentication in your application"
#!/bin/bash
# Check current Cognito configuration for federated authentication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== COGNITO CONFIGURATION CHECK ===${NC}"

# Get configuration from CloudFormation
USER_POOL_ID=$(aws cloudformation describe-stacks --stack-name quote-me-api --query 'Stacks[0].Outputs[?OutputKey==`UserPoolId`].OutputValue' --output text)
USER_POOL_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name quote-me-api --query 'Stacks[0].Outputs[?OutputKey==`UserPoolClientId`].OutputValue' --output text)

if [ -z "$USER_POOL_ID" ]; then
    echo -e "${RED}❌ Could not find User Pool ID from CloudFormation stack${NC}"
    exit 1
fi

echo -e "${GREEN}✓ User Pool ID: $USER_POOL_ID${NC}"
echo -e "${GREEN}✓ User Pool Client ID: $USER_POOL_CLIENT_ID${NC}"

# Get User Pool domain
USER_POOL_DOMAIN=$(aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" --query 'UserPool.Domain' --output text)
echo -e "${GREEN}✓ User Pool Domain: $USER_POOL_DOMAIN${NC}"

# Check User Pool configuration
echo -e "\n${YELLOW}User Pool Configuration:${NC}"
aws cognito-idp describe-user-pool --user-pool-id "$USER_POOL_ID" --query '{
    Name: UserPool.UserPoolName,
    Domain: UserPool.Domain,
    AutoVerifiedAttributes: UserPool.AutoVerifiedAttributes,
    Arn: UserPool.Arn
}' --output table

# Check User Pool Client configuration
echo -e "\n${YELLOW}User Pool Client Configuration:${NC}"
aws cognito-idp describe-user-pool-client --user-pool-id "$USER_POOL_ID" --client-id "$USER_POOL_CLIENT_ID" --query '{
    ClientName: UserPoolClient.ClientName,
    SupportedIdentityProviders: UserPoolClient.SupportedIdentityProviders,
    CallbackURLs: UserPoolClient.CallbackURLs,
    LogoutURLs: UserPoolClient.LogoutURLs,
    AllowedOAuthFlows: UserPoolClient.AllowedOAuthFlows,
    AllowedOAuthScopes: UserPoolClient.AllowedOAuthScopes
}' --output table

# Check Identity Providers
echo -e "\n${YELLOW}Identity Providers:${NC}"
PROVIDERS=$(aws cognito-idp list-identity-providers --user-pool-id "$USER_POOL_ID" --query 'Providers[].ProviderName' --output text)

if [ -z "$PROVIDERS" ] || [ "$PROVIDERS" = "None" ]; then
    echo -e "${RED}❌ No identity providers configured${NC}"
else
    echo -e "${GREEN}✓ Configured providers: $PROVIDERS${NC}"

    # Show details for each provider
    for provider in $PROVIDERS; do
        echo -e "\n${BLUE}Provider: $provider${NC}"
        aws cognito-idp describe-identity-provider --user-pool-id "$USER_POOL_ID" --provider-name "$provider" --query '{
            ProviderType: ProviderType,
            AttributeMapping: AttributeMapping
        }' --output table
    done
fi

# Show important URLs for external provider configuration
echo -e "\n${YELLOW}Important URLs for External Provider Configuration:${NC}"
echo -e "${GREEN}Authorization Endpoint:${NC} https://${USER_POOL_DOMAIN}.auth.us-east-1.amazoncognito.com/oauth2/authorize"
echo -e "${GREEN}Token Endpoint:${NC} https://${USER_POOL_DOMAIN}.auth.us-east-1.amazoncognito.com/oauth2/token"
echo -e "${GREEN}JWKS URI:${NC} https://cognito-idp.us-east-1.amazonaws.com/${USER_POOL_ID}/.well-known/jwks.json"
echo -e "${GREEN}Redirect URI for Providers:${NC} https://${USER_POOL_DOMAIN}.auth.us-east-1.amazoncognito.com/oauth2/idpresponse"

echo -e "\n${YELLOW}OAuth Configuration URLs:${NC}"
aws cognito-idp describe-user-pool-client --user-pool-id "$USER_POOL_ID" --client-id "$USER_POOL_CLIENT_ID" --query 'UserPoolClient.CallbackURLs' --output table

echo -e "\n${GREEN}🔍 Configuration check complete!${NC}"
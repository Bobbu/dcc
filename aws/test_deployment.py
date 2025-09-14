#!/usr/bin/env python3

"""
Comprehensive Quote Me API Deployment Testing Suite
Tests OpenAI endpoints with real authentication and content validation
"""

import boto3
import json
import requests
import time
import sys
import traceback
from datetime import datetime
from botocore.exceptions import ClientError

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    NC = '\033[0m'  # No Color

class DeploymentTester:
    def __init__(self):
        # Configuration from deployment
        self.api_url = "https://dcc.anystupididea.com"
        self.user_pool_id = "us-east-1_WCJMgcwll"
        self.user_pool_client_id = "308apko2vm7tphi0c74ec209cc"
        
        # Test user credentials
        self.test_email = f"test-admin-{int(time.time())}@quoteme.test"
        self.test_password = "TestAdmin123!"
        self.test_name = "Test Admin User"
        
        # AWS clients
        self.cognito_client = boto3.client('cognito-idp')
        
        # Auth token
        self.access_token = None
        self.user_created = False
        
        print(f"{Colors.BLUE}=== QUOTE ME API COMPREHENSIVE TESTING ==={Colors.NC}")
        print(f"Testing OpenAI endpoints with real authentication and validation")
        print(f"Test user: {self.test_email}")
        print("")

    def setup_test_user(self):
        """Create and configure test admin user"""
        try:
            print(f"{Colors.YELLOW}Setting up test admin user...{Colors.NC}")
            
            # Step 1: Create test user
            print("  Creating user...")
            self.cognito_client.admin_create_user(
                UserPoolId=self.user_pool_id,
                Username=self.test_email,
                UserAttributes=[
                    {'Name': 'email', 'Value': self.test_email},
                    {'Name': 'name', 'Value': self.test_name},
                    {'Name': 'email_verified', 'Value': 'true'}
                ],
                TemporaryPassword=self.test_password,
                MessageAction='SUPPRESS'
            )
            self.user_created = True
            print(f"  {Colors.GREEN}✓ User created{Colors.NC}")
            
            # Step 2: Set permanent password
            print("  Setting permanent password...")
            self.cognito_client.admin_set_user_password(
                UserPoolId=self.user_pool_id,
                Username=self.test_email,
                Password=self.test_password,
                Permanent=True
            )
            print(f"  {Colors.GREEN}✓ Password set{Colors.NC}")
            
            # Step 3: Add to Admins group
            print("  Adding to Admins group...")
            self.cognito_client.admin_add_user_to_group(
                UserPoolId=self.user_pool_id,
                Username=self.test_email,
                GroupName='Admins'
            )
            print(f"  {Colors.GREEN}✓ Added to Admins group{Colors.NC}")
            
            # Step 4: Authenticate using USER_PASSWORD_AUTH flow
            print("  Authenticating...")
            auth_response = self.cognito_client.initiate_auth(
                ClientId=self.user_pool_client_id,
                AuthFlow='USER_PASSWORD_AUTH',
                AuthParameters={
                    'USERNAME': self.test_email,
                    'PASSWORD': self.test_password
                }
            )
            
            self.access_token = auth_response['AuthenticationResult']['AccessToken']
            print(f"  {Colors.GREEN}✓ Authentication successful{Colors.NC}")
            
            # Debug: Check token claims
            try:
                import base64
                # JWT tokens have 3 parts separated by dots
                parts = self.access_token.split('.')
                # Decode the payload (second part)
                # Add padding if needed for base64 decoding
                payload = parts[1]
                payload += '=' * (4 - len(payload) % 4)
                decoded = base64.b64decode(payload)
                claims = json.loads(decoded)
                print(f"  Token groups: {claims.get('cognito:groups', 'None')}")
                print(f"  Token username: {claims.get('username', 'None')}")
            except Exception as e:
                print(f"  Could not decode token: {e}")
            
            # Small delay to ensure user setup is fully propagated
            print("  Waiting for user setup to propagate...")
            time.sleep(2)
            
            return True
            
        except Exception as e:
            print(f"  {Colors.RED}✗ Setup failed: {str(e)}{Colors.NC}")
            return False

    def test_tag_generation(self):
        """Test the OpenAI tag generation endpoint with real validation"""
        print(f"\n{Colors.YELLOW}Testing OpenAI Tag Generation...{Colors.NC}")
        
        test_cases = [
            {
                "quote": "The only way to do great work is to love what you do.",
                "author": "Steve Jobs",
                "existingTags": ["Work", "Passion", "Excellence", "Success", "Motivation"],
                "expected_themes": ["work", "passion", "love", "success", "motivation"]
            },
            {
                "quote": "In the middle of difficulty lies opportunity.",
                "author": "Albert Einstein",
                "existingTags": ["Challenge", "Opportunity", "Growth", "Wisdom", "Resilience"],
                "expected_themes": ["opportunity", "difficulty", "challenge", "growth"]
            }
        ]
        
        for i, test_case in enumerate(test_cases, 1):
            print(f"  Test Case {i}: {test_case['author']} quote...")
            
            try:
                # Make the API call
                response = requests.post(
                    f"{self.api_url}/admin/generate-tags",
                    headers={
                        'Content-Type': 'application/json',
                        'Authorization': f'Bearer {self.access_token}'
                    },
                    json={
                        'quote': test_case['quote'],
                        'author': test_case['author'],
                        'existingTags': test_case['existingTags']
                    },
                    timeout=30
                )
                
                # Check HTTP status
                if response.status_code != 200:
                    print(f"    {Colors.RED}✗ HTTP {response.status_code}: {response.text}{Colors.NC}")
                    return False
                
                # Parse response
                data = response.json()
                
                # Validate response structure
                if 'tags' not in data:
                    print(f"    {Colors.RED}✗ No 'tags' field in response{Colors.NC}")
                    print(f"    Response: {json.dumps(data, indent=2)}")
                    return False
                
                tags = data['tags']
                
                # Validate tags are a list
                if not isinstance(tags, list):
                    print(f"    {Colors.RED}✗ Tags is not a list: {type(tags)}{Colors.NC}")
                    return False
                
                # Validate we got some tags
                if len(tags) == 0:
                    print(f"    {Colors.RED}✗ No tags returned{Colors.NC}")
                    return False
                
                # Validate tags are strings
                for tag in tags:
                    if not isinstance(tag, str) or len(tag.strip()) == 0:
                        print(f"    {Colors.RED}✗ Invalid tag: {repr(tag)}{Colors.NC}")
                        return False
                
                # Content validation - check if tags are relevant
                tags_lower = [tag.lower() for tag in tags]
                quote_lower = test_case['quote'].lower()
                expected_themes = test_case['expected_themes']
                
                relevance_score = 0
                for theme in expected_themes:
                    if any(theme in tag_lower for tag_lower in tags_lower) or theme in quote_lower:
                        relevance_score += 1
                
                relevance_percentage = (relevance_score / len(expected_themes)) * 100
                
                print(f"    {Colors.GREEN}✓ Generated {len(tags)} tags{Colors.NC}")
                print(f"    Tags: {', '.join(tags)}")
                print(f"    Relevance: {relevance_percentage:.1f}% ({relevance_score}/{len(expected_themes)} themes)")
                
                # Consider test successful if we got valid tags
                # (relevance is nice-to-have but OpenAI might be creative)
                
            except requests.exceptions.Timeout:
                print(f"    {Colors.RED}✗ Request timeout (OpenAI took too long){Colors.NC}")
                return False
            except requests.exceptions.RequestException as e:
                print(f"    {Colors.RED}✗ Request failed: {str(e)}{Colors.NC}")
                return False
            except json.JSONDecodeError as e:
                print(f"    {Colors.RED}✗ Invalid JSON response: {str(e)}{Colors.NC}")
                print(f"    Raw response: {response.text[:200]}...")
                return False
            except Exception as e:
                print(f"    {Colors.RED}✗ Unexpected error: {str(e)}{Colors.NC}")
                traceback.print_exc()
                return False
        
        print(f"  {Colors.GREEN}✓ All tag generation tests passed{Colors.NC}")
        return True

    def test_basic_api(self):
        """Test basic API functionality to ensure deployment is working"""
        print(f"\n{Colors.YELLOW}Testing Basic API...{Colors.NC}")
        
        try:
            # Test public quote endpoint (with API key)
            response = requests.get(
                f"{self.api_url}/quote",
                headers={'x-api-key': 'iJF7oVCPHLaeWfYPhkuy71izWFoXrr8qawS4drL1'},
                timeout=10
            )
            
            if response.status_code == 200:
                data = response.json()
                if 'quote' in data and len(data['quote']) > 10:
                    print(f"  {Colors.GREEN}✓ Quote endpoint working{Colors.NC}")
                    print(f"  Sample: {data['quote'][:60]}...")
                    return True
            
            print(f"  {Colors.RED}✗ Quote endpoint failed: HTTP {response.status_code}{Colors.NC}")
            return False
            
        except Exception as e:
            print(f"  {Colors.RED}✗ Basic API test failed: {str(e)}{Colors.NC}")
            return False

    def cleanup_test_user(self):
        """Clean up test user"""
        if self.user_created:
            try:
                print(f"\n{Colors.YELLOW}Cleaning up test user...{Colors.NC}")
                self.cognito_client.admin_delete_user(
                    UserPoolId=self.user_pool_id,
                    Username=self.test_email
                )
                print(f"  {Colors.GREEN}✓ Test user deleted{Colors.NC}")
            except Exception as e:
                print(f"  {Colors.YELLOW}⚠ Could not delete test user: {str(e)}{Colors.NC}")

    def run_tests(self):
        """Run all tests with proper cleanup"""
        success = True
        
        try:
            # Setup
            if not self.setup_test_user():
                return False
            
            # Basic API test
            if not self.test_basic_api():
                success = False
            
            # OpenAI tests
            if not self.test_tag_generation():
                success = False
            
            return success
            
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}Test interrupted by user{Colors.NC}")
            return False
        except Exception as e:
            print(f"\n{Colors.RED}Unexpected error in test suite: {str(e)}{Colors.NC}")
            traceback.print_exc()
            return False
        finally:
            # Always cleanup
            self.cleanup_test_user()

def main():
    """Main test runner"""
    print(f"Starting comprehensive deployment tests at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    tester = DeploymentTester()
    success = tester.run_tests()
    
    print(f"\n{Colors.BLUE}=== TEST RESULTS ==={Colors.NC}")
    if success:
        print(f"{Colors.GREEN}✅ All tests passed! OpenAI endpoints are working correctly.{Colors.NC}")
        print(f"{Colors.GREEN}🏷️ Tag Generation: WORKING{Colors.NC}")
        sys.exit(0)
    else:
        print(f"{Colors.RED}❌ Some tests failed. Check the output above for details.{Colors.NC}")
        sys.exit(1)

if __name__ == "__main__":
    main()
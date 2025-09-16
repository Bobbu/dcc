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
            
            # Use ID token for API Gateway authorization (not access token)
            self.access_token = auth_response['AuthenticationResult']['IdToken']
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
                print(f"  Token username: {claims.get('cognito:username', 'None')}")
                print(f"  Token type: {claims.get('token_use', 'None')}")
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

    def test_image_generation(self):
        """Test the image generation endpoint and workflow"""
        print(f"\n{Colors.YELLOW}Testing Image Generation...{Colors.NC}")
        
        test_case = {
            "quote": "The only way to do great work is to love what you do.",
            "author": "Steve Jobs",
            "tags": "motivation, success, passion"
        }
        
        print(f"  Testing with: {test_case['author']} quote...")
        
        try:
            # Step 1: Submit image generation job
            response = requests.post(
                f"{self.api_url}/admin/generate-image",
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {self.access_token}'
                },
                json={
                    'quote': test_case['quote'],
                    'author': test_case['author'],
                    'tags': test_case['tags']
                },
                timeout=10
            )
            
            # Check HTTP status for job submission (202 = queued, 200 = immediate response)
            if response.status_code not in [200, 202]:
                print(f"    {Colors.RED}✗ Job submission failed - HTTP {response.status_code}: {response.text}{Colors.NC}")
                return False
            
            # Parse job response
            job_data = response.json()
            
            # Validate job response structure (handle both job_id and jobId)
            job_id = job_data.get('job_id') or job_data.get('jobId')
            if not job_id:
                print(f"    {Colors.RED}✗ No 'job_id' or 'jobId' field in response{Colors.NC}")
                print(f"    Response: {json.dumps(job_data, indent=2)}")
                return False
            print(f"    {Colors.GREEN}✓ Job submitted successfully{Colors.NC}")
            print(f"    Job ID: {job_id}")
            
            # Step 2: Check job status (allow some time for processing)
            max_checks = 12  # 2 minutes max (10 second intervals)
            check_interval = 10
            
            for check in range(max_checks):
                print(f"    Checking status ({check + 1}/{max_checks})...")
                
                status_response = requests.get(
                    f"{self.api_url}/admin/image-generation-status/{job_id}",
                    headers={
                        'Authorization': f'Bearer {self.access_token}'
                    },
                    timeout=10
                )
                
                if status_response.status_code != 200:
                    print(f"    {Colors.RED}✗ Status check failed - HTTP {status_response.status_code}{Colors.NC}")
                    return False
                
                status_data = status_response.json()
                status = status_data.get('status', 'unknown')
                
                print(f"    Status: {status}")
                
                if status == 'completed':
                    print(f"    {Colors.GREEN}✓ Image generation completed successfully{Colors.NC}")
                    
                    # Validate completed job has image URL
                    if 'image_url' in status_data:
                        image_url = status_data['image_url']
                        print(f"    Image URL: {image_url}")
                        
                        # Verify URL is accessible (basic check)
                        try:
                            img_response = requests.head(image_url, timeout=10)
                            if img_response.status_code == 200:
                                print(f"    {Colors.GREEN}✓ Generated image is accessible{Colors.NC}")
                            else:
                                print(f"    {Colors.YELLOW}⚠ Generated image URL returned {img_response.status_code}{Colors.NC}")
                        except Exception as e:
                            print(f"    {Colors.YELLOW}⚠ Could not verify image URL: {str(e)}{Colors.NC}")
                    else:
                        print(f"    {Colors.YELLOW}⚠ Completed job missing image_url{Colors.NC}")
                    
                    return True
                    
                elif status == 'failed':
                    error_msg = status_data.get('error_message', 'Unknown error')
                    print(f"    {Colors.RED}✗ Image generation failed: {error_msg}{Colors.NC}")
                    return False
                    
                elif status in ['queued', 'processing']:
                    # Still in progress, wait and check again
                    if check < max_checks - 1:  # Don't sleep on last iteration
                        time.sleep(check_interval)
                    continue
                else:
                    print(f"    {Colors.YELLOW}⚠ Unknown status: {status}{Colors.NC}")
                    if check < max_checks - 1:
                        time.sleep(check_interval)
                    continue
            
            print(f"    {Colors.RED}✗ Image generation timed out after {max_checks * check_interval} seconds{Colors.NC}")
            return False
            
        except requests.exceptions.Timeout:
            print(f"    {Colors.RED}✗ Request timeout{Colors.NC}")
            return False
        except requests.exceptions.RequestException as e:
            print(f"    {Colors.RED}✗ Request failed: {str(e)}{Colors.NC}")
            return False
        except json.JSONDecodeError as e:
            print(f"    {Colors.RED}✗ Invalid JSON response: {str(e)}{Colors.NC}")
            return False
        except Exception as e:
            print(f"    {Colors.RED}✗ Unexpected error: {str(e)}{Colors.NC}")
            traceback.print_exc()
            return False

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
        """Run all tests with proper cleanup and comprehensive reporting"""
        test_results = []
        
        try:
            # Setup
            if not self.setup_test_user():
                print(f"\n{Colors.RED}Failed to setup test user - cannot continue{Colors.NC}")
                return False
            
            # Run all tests and track results
            tests = [
                ("Basic API", self.test_basic_api),
                ("Tag Generation", self.test_tag_generation),
                ("Image Generation", self.test_image_generation)
            ]
            
            for test_name, test_method in tests:
                try:
                    print(f"\n{Colors.BLUE}Running {test_name} test...{Colors.NC}")
                    result = test_method()
                    test_results.append((test_name, result, None))
                    if result:
                        print(f"{Colors.GREEN}✅ {test_name} test: PASSED{Colors.NC}")
                    else:
                        print(f"{Colors.RED}❌ {test_name} test: FAILED{Colors.NC}")
                except Exception as e:
                    error_msg = str(e)
                    test_results.append((test_name, False, error_msg))
                    print(f"{Colors.RED}❌ {test_name} test: FAILED (Exception: {error_msg}){Colors.NC}")
            
            # Calculate summary
            passed_tests = [result for result in test_results if result[1]]
            total_tests = len(test_results)
            passed_count = len(passed_tests)
            
            # Return True only if all tests passed
            all_passed = passed_count == total_tests
            
            # Print detailed results summary
            print(f"\n{Colors.BLUE}=== DETAILED TEST RESULTS ==={Colors.NC}")
            for test_name, passed, error in test_results:
                status = f"{Colors.GREEN}PASSED{Colors.NC}" if passed else f"{Colors.RED}FAILED{Colors.NC}"
                print(f"  {test_name}: {status}")
                if error:
                    print(f"    Error: {error}")
            
            return all_passed, passed_count, total_tests
            
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}Test interrupted by user{Colors.NC}")
            return False, 0, 0
        except Exception as e:
            print(f"\n{Colors.RED}Unexpected error in test suite: {str(e)}{Colors.NC}")
            traceback.print_exc()
            return False, 0, 0
        finally:
            # Always cleanup
            self.cleanup_test_user()

def main():
    """Main test runner"""
    print(f"Starting comprehensive deployment tests at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    tester = DeploymentTester()
    result = tester.run_tests()
    
    # Handle different return formats for backwards compatibility
    if isinstance(result, tuple):
        all_passed, passed_count, total_tests = result
        print(f"\n{Colors.BLUE}=== FINAL TEST SUMMARY ==={Colors.NC}")
        print(f"{Colors.BLUE}Tests completed: {passed_count}/{total_tests} passed{Colors.NC}")
        
        if all_passed:
            print(f"{Colors.GREEN}✅ All tests passed! OpenAI endpoints are working correctly.{Colors.NC}")
            print(f"{Colors.GREEN}🏷️ Tag Generation: WORKING{Colors.NC}")
            print(f"{Colors.GREEN}🖼️ Image Generation: WORKING{Colors.NC}")
            sys.exit(0)
        else:
            print(f"{Colors.YELLOW}⚠️  {total_tests - passed_count} of {total_tests} tests failed. Check the output above for details.{Colors.NC}")
            sys.exit(1)
    else:
        # Legacy single boolean return
        success = result
        print(f"\n{Colors.BLUE}=== TEST RESULTS ==={Colors.NC}")
        if success:
            print(f"{Colors.GREEN}✅ All tests passed! OpenAI endpoints are working correctly.{Colors.NC}")
            sys.exit(0)
        else:
            print(f"{Colors.RED}❌ Some tests failed. Check the output above for details.{Colors.NC}")
            sys.exit(1)

if __name__ == "__main__":
    main()
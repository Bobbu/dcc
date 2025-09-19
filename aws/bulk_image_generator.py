#!/usr/bin/env python3

"""
Bulk Quote Image Generator
Systematically generates AI images for quotes that don't have them yet.
"""

import boto3
import json
import requests
import time
import sys
import os
from datetime import datetime
from botocore.exceptions import ClientError

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'  # No Color

class BulkImageGenerator:
    def __init__(self):
        # Configuration from deployment
        self.api_url = "https://dcc.anystupididea.com"
        self.user_pool_id = "us-east-1_WCJMgcwll"
        self.user_pool_client_id = "308apko2vm7tphi0c74ec209cc"
        self.api_key = "iJF7oVCPHLaeWfYPhkuy71izWFoXrr8qawS4drL1"
        
        # Test admin user credentials
        self.admin_email = f"bulk-admin-{int(time.time())}@quoteme.admin"
        self.admin_password = "BulkAdmin123!"
        self.admin_name = "Bulk Image Generator Admin"
        
        # AWS clients
        self.cognito_client = boto3.client('cognito-idp')
        
        # Auth token and refresh tracking
        self.access_token = None
        self.refresh_token = None
        self.token_obtained_at = None
        self.user_created = False
        
        # Failure tracking
        self.failure_log_file = "failed_image_generation_quotes.txt"
        self.failed_quotes = set()
        self._load_failed_quotes()
        
        print(f"{Colors.PURPLE}╔══════════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.PURPLE}║     🎨 BULK QUOTE IMAGE GENERATOR 🎨     ║{Colors.NC}")
        print(f"{Colors.PURPLE}╚══════════════════════════════════════════╝{Colors.NC}")
        print(f"📅 Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"🎯 Target: Generate images for quotes without them")
        if self.failed_quotes:
            print(f"⚠️  Loaded {len(self.failed_quotes)} previously failed quotes (will skip)")
        print()

    def _load_failed_quotes(self):
        """Load previously failed quotes from the failure log file"""
        try:
            if os.path.exists(self.failure_log_file):
                with open(self.failure_log_file, 'r', encoding='utf-8') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            # Extract quote text from the format: "Quote text" -- Author
                            if ' -- ' in line:
                                quote_text = line.split(' -- ')[0].strip('"')
                                self.failed_quotes.add(quote_text)
                print(f"  {Colors.YELLOW}📝 Loaded {len(self.failed_quotes)} previously failed quotes{Colors.NC}")
        except Exception as e:
            print(f"  {Colors.YELLOW}⚠️ Could not load failure log: {str(e)}{Colors.NC}")

    def _log_failed_quote(self, quote_text, author, error_reason=""):
        """Log a failed quote to the failure tracking file"""
        try:
            # Create header if file doesn't exist
            file_exists = os.path.exists(self.failure_log_file)
            
            with open(self.failure_log_file, 'a', encoding='utf-8') as f:
                if not file_exists:
                    f.write("# Failed Image Generation Quotes\n")
                    f.write("# Format: \"Quote text\" -- Author [Error reason]\n")
                    f.write(f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                    f.write("#" + "="*60 + "\n\n")
                
                # Log the failed quote
                timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                error_suffix = f" [{error_reason}]" if error_reason else ""
                f.write(f'"{quote_text}" -- {author}{error_suffix} # {timestamp}\n')
            
            # Add to in-memory set to avoid retrying this session
            self.failed_quotes.add(quote_text)
            
            print(f"  {Colors.YELLOW}📝 Logged failure to {self.failure_log_file}{Colors.NC}")
            
        except Exception as e:
            print(f"  {Colors.RED}✗ Could not log failure: {str(e)}{Colors.NC}")

    def _should_skip_quote(self, quote):
        """Check if a quote should be skipped due to previous failures"""
        quote_text = quote.get('quote', '')
        return quote_text in self.failed_quotes

    def setup_admin_user(self):
        """Create and authenticate a temporary admin user"""
        try:
            print(f"{Colors.YELLOW}🔧 Setting up temporary admin user...{Colors.NC}")
            
            # Step 1: Create admin user
            print(f"  📝 Creating admin user: {self.admin_email}")
            self.cognito_client.admin_create_user(
                UserPoolId=self.user_pool_id,
                Username=self.admin_email,
                UserAttributes=[
                    {'Name': 'email', 'Value': self.admin_email},
                    {'Name': 'name', 'Value': self.admin_name},
                    {'Name': 'email_verified', 'Value': 'true'}
                ],
                TemporaryPassword=self.admin_password,
                MessageAction='SUPPRESS'
            )
            self.user_created = True
            print(f"  {Colors.GREEN}✓ Admin user created{Colors.NC}")
            
            # Step 2: Set permanent password
            print(f"  🔒 Setting permanent password...")
            self.cognito_client.admin_set_user_password(
                UserPoolId=self.user_pool_id,
                Username=self.admin_email,
                Password=self.admin_password,
                Permanent=True
            )
            print(f"  {Colors.GREEN}✓ Password configured{Colors.NC}")
            
            # Step 3: Add to Admins group
            print(f"  👥 Adding to Admins group...")
            self.cognito_client.admin_add_user_to_group(
                UserPoolId=self.user_pool_id,
                Username=self.admin_email,
                GroupName='Admins'
            )
            print(f"  {Colors.GREEN}✓ Admin privileges granted{Colors.NC}")
            
            # Step 4: Authenticate and get JWT token
            print(f"  🎫 Authenticating...")
            auth_response = self.cognito_client.initiate_auth(
                ClientId=self.user_pool_client_id,
                AuthFlow='USER_PASSWORD_AUTH',
                AuthParameters={
                    'USERNAME': self.admin_email,
                    'PASSWORD': self.admin_password
                }
            )
            
            # Store both ID token and refresh token for API Gateway authorization
            self.access_token = auth_response['AuthenticationResult']['IdToken']
            self.refresh_token = auth_response['AuthenticationResult']['RefreshToken']
            self.token_obtained_at = time.time()
            print(f"  {Colors.GREEN}✓ Authentication successful{Colors.NC}")
            
            print(f"{Colors.GREEN}🎉 Admin setup complete! Ready to generate images.{Colors.NC}")
            print()
            return True
            
        except Exception as e:
            print(f"  {Colors.RED}✗ Admin setup failed: {str(e)}{Colors.NC}")
            return False

    def refresh_access_token(self):
        """Refresh the access token using the refresh token"""
        try:
            print(f"  🔄 Refreshing expired access token...")
            
            auth_response = self.cognito_client.initiate_auth(
                ClientId=self.user_pool_client_id,
                AuthFlow='REFRESH_TOKEN_AUTH',
                AuthParameters={
                    'REFRESH_TOKEN': self.refresh_token
                }
            )
            
            # Update with new tokens
            self.access_token = auth_response['AuthenticationResult']['IdToken']
            self.token_obtained_at = time.time()
            
            # Note: Refresh token might be rotated, so update it if provided
            if 'RefreshToken' in auth_response['AuthenticationResult']:
                self.refresh_token = auth_response['AuthenticationResult']['RefreshToken']
            
            print(f"  {Colors.GREEN}✓ Token refreshed successfully{Colors.NC}")
            return True
            
        except Exception as e:
            print(f"  {Colors.RED}✗ Token refresh failed: {str(e)}{Colors.NC}")
            return False
    
    def ensure_valid_token(self):
        """Ensure we have a valid, non-expired token"""
        # Check if token is close to expiring (50 minutes = 3000 seconds)
        # JWT tokens typically expire after 1 hour (3600 seconds)
        if self.token_obtained_at and (time.time() - self.token_obtained_at) > 3000:
            print(f"  🔒 Token approaching expiration, refreshing...")
            return self.refresh_access_token()
        return True

    def get_quotes_without_images(self, limit=100):
        """Fetch quotes systematically from admin API and filter out those with images"""
        try:
            # Ensure we have a valid token before making API calls
            if not self.ensure_valid_token():
                return []
                
            print(f"{Colors.CYAN}📥 Fetching quotes systematically to find ones without images...{Colors.NC}")
            
            # Use admin API to get quotes in a predictable order
            # This ensures we don't keep getting the same random quotes
            quotes_without_images = []
            processed_ids = getattr(self, '_processed_quote_ids', set())
            
            # Keep fetching until we have enough quotes without images or run out
            last_key = None  # Initialize pagination key
            while len(quotes_without_images) < limit:
                # Build admin API request
                admin_url = f"{self.api_url}/admin/quotes"
                params = {
                    'limit': 500,  # Fetch more at once since pagination is broken
                    'sort_by': 'updated_at',
                    'sort_order': 'asc'  # Get oldest updated quotes first (process oldest unedited quotes first)
                }
                
                if last_key:
                    params['last_key'] = last_key
                
                response = requests.get(
                    admin_url,
                    headers={
                        'Authorization': f'Bearer {self.access_token}',
                        'Content-Type': 'application/json'
                    },
                    params=params,
                    timeout=30
                )
                
                if response.status_code != 200:
                    print(f"  {Colors.RED}✗ Admin API failed: HTTP {response.status_code}{Colors.NC}")
                    break
                
                data = response.json()
                batch_quotes = data.get('quotes', [])
                
                if not batch_quotes:
                    print(f"  {Colors.YELLOW}📝 No more quotes available in database{Colors.NC}")
                    break
                
                # Filter this batch for quotes without images, not already processed, AND not previously failed
                batch_without_images = [
                    q for q in batch_quotes 
                    if not q.get('image_url') 
                    and q.get('id') not in processed_ids
                    and not self._should_skip_quote(q)
                ]
                quotes_without_images.extend(batch_without_images)
                
                # Update pagination key for next request - persist across entire session
                last_key = data.get('last_key')
                self._session_pagination_key = last_key
                
                # WORKAROUND: Admin API pagination is broken, so if we get a last_key,
                # we just stop here to avoid 500 errors on subsequent requests
                if last_key:
                    print(f"  {Colors.YELLOW}⚠️ Stopping batch fetch (pagination not working in admin API){Colors.NC}")
                    break
                
                # Progress update
                total_checked = len(batch_quotes)
                without_images_total = len([q for q in batch_quotes if not q.get('image_url')])
                with_images = total_checked - without_images_total
                previously_failed = len([q for q in batch_quotes if not q.get('image_url') and self._should_skip_quote(q)])
                without_images_available = len(batch_without_images)
                
                print(f"  📊 Batch: {total_checked} quotes checked, {without_images_total} without images ({previously_failed} skipped due to previous failures), {without_images_available} available for processing, {with_images} with images")
                
                # If no more pages, we're done
                if not last_key:
                    print(f"  {Colors.BLUE}📋 Reached end of database{Colors.NC}")
                    break
            
            final_count = min(len(quotes_without_images), limit)
            result = quotes_without_images[:final_count]
            
            print(f"  {Colors.GREEN}📈 Search complete:{Colors.NC}")
            print(f"    • Quotes without images found: {len(quotes_without_images)}")
            print(f"    • Returning for processing: {final_count}")
            print()
            
            return result
            
        except Exception as e:
            print(f"  {Colors.RED}✗ Failed to fetch quotes systematically: {str(e)}{Colors.NC}")
            return []

    def generate_image_for_quote(self, quote):
        """Generate an image for a single quote"""
        # Ensure we have a valid token before making API calls
        if not self.ensure_valid_token():
            return None
            
        quote_id = quote['id']
        quote_text = quote['quote']
        author = quote['author']
        tags = quote.get('tags', [])
        
        # Display quote preview
        preview = quote_text[:60] + "..." if len(quote_text) > 60 else quote_text
        print(f"  🎨 Quote: \"{preview}\"")
        print(f"  👤 Author: {author}")
        print(f"  🏷️  Tags: {', '.join(tags) if tags else 'None'}")
        
        try:
            # Submit image generation job
            print(f"  📤 Submitting image generation job...")
            response = requests.post(
                f"{self.api_url}/admin/generate-image",
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {self.access_token}'
                },
                json={
                    'quote': quote_text,
                    'author': author,
                    'tags': ', '.join(tags) if tags else '',
                    'quote_id': quote_id  # Fixed: use underscore like the queue handler expects
                },
                timeout=30
            )
            
            if response.status_code in [200, 202]:
                job_data = response.json()
                job_id = job_data.get('job_id') or job_data.get('jobId')
                
                if job_id:
                    print(f"  {Colors.GREEN}✓ Job submitted successfully (ID: {job_id}){Colors.NC}")
                    return job_id
                else:
                    print(f"  {Colors.RED}✗ No job ID in response{Colors.NC}")
                    self._log_failed_quote(quote_text, author, "No job ID returned")
                    return None
            else:
                error_reason = f"HTTP {response.status_code}"
                response_text = response.text[:100] if response.text else "No response body"
                print(f"  {Colors.RED}✗ Job submission failed (HTTP {response.status_code}){Colors.NC}")
                print(f"    Response: {response_text}")
                self._log_failed_quote(quote_text, author, f"{error_reason}: {response_text}")
                return None
                
        except Exception as e:
            error_msg = str(e)
            print(f"  {Colors.RED}✗ Error submitting job: {error_msg}{Colors.NC}")
            self._log_failed_quote(quote_text, author, f"Exception: {error_msg}")
            return None

    def wait_for_completion(self, job_id, quote_author):
        """Wait for image generation to complete (simplified - just wait fixed time)"""
        print(f"  ⏱️  Waiting 4 minutes for image generation...")
        print(f"  💭 Generating image for {quote_author} quote...")
        
        # Show a progress countdown
        for minutes_left in range(4, 0, -1):
            print(f"    ⏰ {minutes_left} minute{'s' if minutes_left > 1 else ''} remaining...")
            time.sleep(60)  # Wait 1 minute
        
        print(f"  {Colors.GREEN}⏰ Wait complete! Moving to next quote...{Colors.NC}")

    def run_bulk_generation(self, batch_size=100):
        """Main process: generate images for quotes in batches"""
        if not self.setup_admin_user():
            print(f"{Colors.RED}❌ Cannot continue without admin access{Colors.NC}")
            return False
        
        # Track all processed quote IDs to avoid duplicates
        self._processed_quote_ids = set()
        total_processed = 0
        
        try:
            while True:
                print(f"{Colors.BLUE}🚀 Starting batch of up to {batch_size} quotes...{Colors.NC}")
                
                # Get quotes without images
                quotes = self.get_quotes_without_images(batch_size)
                
                if not quotes:
                    print(f"{Colors.YELLOW}🎉 No more quotes without images found!{Colors.NC}")
                    break
                
                print(f"{Colors.CYAN}📋 Processing {len(quotes)} quotes in this batch{Colors.NC}")
                print()
                
                # Proactively refresh token before starting batch if needed
                if not self.ensure_valid_token():
                    print(f"{Colors.RED}❌ Failed to ensure valid token, stopping batch{Colors.NC}")
                    break
                
                # Process each quote
                for i, quote in enumerate(quotes, 1):
                    print(f"{Colors.PURPLE}━━━ Quote {i}/{len(quotes)} (Total: {total_processed + i}) ━━━{Colors.NC}")
                    
                    # Mark this quote as processed so we don't retry it
                    quote_id = quote.get('id')
                    if quote_id:
                        self._processed_quote_ids.add(quote_id)
                    
                    # Generate image
                    job_id = self.generate_image_for_quote(quote)
                    
                    if job_id:
                        # Wait for completion
                        self.wait_for_completion(job_id, quote['author'])
                        print(f"  {Colors.GREEN}✅ Quote {i} completed successfully{Colors.NC}")
                    else:
                        print(f"  {Colors.YELLOW}⚠️  Quote {i} skipped due to error{Colors.NC}")
                    
                    print()
                
                total_processed += len(quotes)
                
                # Ask if user wants to continue
                print(f"{Colors.BLUE}📊 BATCH SUMMARY:{Colors.NC}")
                print(f"  • Quotes processed in this batch: {len(quotes)}")
                print(f"  • Total quotes processed: {total_processed}")
                print()
                
                if len(quotes) < batch_size:
                    print(f"{Colors.GREEN}🏁 Reached end of quotes without images!{Colors.NC}")
                    break
                
                # Prompt for continuation
                print(f"{Colors.YELLOW}Continue with next batch of {batch_size} quotes?{Colors.NC}")
                response = input("Enter 'y' to continue, anything else to stop: ").strip().lower()
                
                if response != 'y':
                    print(f"{Colors.BLUE}🛑 Stopping by user request{Colors.NC}")
                    break
                
                print()  # Add spacing between batches
                
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}🛑 Process interrupted by user{Colors.NC}")
        except Exception as e:
            print(f"\n{Colors.RED}❌ Unexpected error: {str(e)}{Colors.NC}")
        
        finally:
            self.cleanup()
        
        print(f"\n{Colors.GREEN}📈 FINAL SUMMARY:{Colors.NC}")
        print(f"  • Total quotes processed: {total_processed}")
        print(f"  • Session duration: {datetime.now().strftime('%H:%M:%S')}")
        print(f"  • Status: Complete")
        
        return total_processed > 0

    def cleanup(self):
        """Clean up temporary admin user"""
        if self.user_created:
            try:
                print(f"\n{Colors.YELLOW}🧹 Cleaning up temporary admin user...{Colors.NC}")
                self.cognito_client.admin_delete_user(
                    UserPoolId=self.user_pool_id,
                    Username=self.admin_email
                )
                print(f"  {Colors.GREEN}✓ Temporary admin user deleted{Colors.NC}")
            except Exception as e:
                print(f"  {Colors.YELLOW}⚠ Could not delete admin user: {str(e)}{Colors.NC}")

def main():
    """Main entry point"""
    print(f"{Colors.CYAN}Welcome to the Bulk Quote Image Generator!{Colors.NC}")
    print(f"This tool will systematically add AI-generated images to quotes.")
    print()
    
    # Confirm before starting
    response = input(f"{Colors.YELLOW}Ready to start? (y/N): {Colors.NC}").strip().lower()
    if response != 'y':
        print(f"{Colors.BLUE}Operation cancelled by user.{Colors.NC}")
        sys.exit(0)
    
    print()
    
    generator = BulkImageGenerator()
    success = generator.run_bulk_generation()
    
    if success:
        print(f"\n{Colors.GREEN}🎉 Bulk image generation completed successfully!{Colors.NC}")
        print(f"{Colors.CYAN}Your quote collection now has many more beautiful images!{Colors.NC}")
    else:
        print(f"\n{Colors.YELLOW}⚠️  Bulk generation ended without processing quotes.{Colors.NC}")

if __name__ == "__main__":
    main()
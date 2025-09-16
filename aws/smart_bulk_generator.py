#!/usr/bin/env python3

"""
Smart Bulk Image Generator
- Checks job status instead of blind waiting
- Retries failed jobs
- Provides real cost tracking
"""

import boto3
import requests
import json
import time
import sys
from datetime import datetime

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    CYAN = '\033[0;36m'
    NC = '\033[0m'

class SmartBulkGenerator:
    def __init__(self):
        self.api_url = "https://dcc.anystupididea.com"
        self.user_pool_id = "us-east-1_WCJMgcwll"
        self.user_pool_client_id = "308apko2vm7tphi0c74ec209cc"
        self.api_key = "iJF7oVCPHLaeWfYPhkuy71izWFoXrr8qawS4drL1"
        
        self.cognito_client = boto3.client('cognito-idp')
        self.dynamodb = boto3.resource('dynamodb')
        self.quotes_table = self.dynamodb.Table('quote-me-quotes')
        
        self.access_token = None
        self.admin_email = None
        
        # Track statistics
        self.stats = {
            'submitted': 0,
            'completed': 0,
            'failed': 0,
            'retried': 0,
            'cost': 0.0  # DALL-E 3 costs $0.040 per image
        }
        
    def setup_admin_user(self):
        """Create temporary admin user"""
        self.admin_email = f"smart-bulk-{int(time.time())}@quoteme.admin"
        admin_password = "SmartBulk123!"
        
        try:
            print(f"{Colors.YELLOW}🔧 Setting up admin access...{Colors.NC}")
            
            self.cognito_client.admin_create_user(
                UserPoolId=self.user_pool_id,
                Username=self.admin_email,
                UserAttributes=[
                    {'Name': 'email', 'Value': self.admin_email},
                    {'Name': 'name', 'Value': 'Smart Bulk Generator'},
                    {'Name': 'email_verified', 'Value': 'true'}
                ],
                TemporaryPassword=admin_password,
                MessageAction='SUPPRESS'
            )
            
            self.cognito_client.admin_set_user_password(
                UserPoolId=self.user_pool_id,
                Username=self.admin_email,
                Password=admin_password,
                Permanent=True
            )
            
            self.cognito_client.admin_add_user_to_group(
                UserPoolId=self.user_pool_id,
                Username=self.admin_email,
                GroupName='Admins'
            )
            
            auth_response = self.cognito_client.initiate_auth(
                ClientId=self.user_pool_client_id,
                AuthFlow='USER_PASSWORD_AUTH',
                AuthParameters={
                    'USERNAME': self.admin_email,
                    'PASSWORD': admin_password
                }
            )
            
            self.access_token = auth_response['AuthenticationResult']['IdToken']
            print(f"{Colors.GREEN}✓ Admin access ready{Colors.NC}\n")
            return True
            
        except Exception as e:
            print(f"{Colors.RED}✗ Setup failed: {e}{Colors.NC}")
            return False
    
    def check_job_status(self, job_id):
        """Check the status of an image generation job"""
        try:
            # Query DynamoDB for job status
            response = self.quotes_table.get_item(
                Key={'id': f'JOB_{job_id}'}
            )
            
            if 'Item' in response:
                return response['Item'].get('status', 'unknown')
            return 'not_found'
            
        except Exception as e:
            print(f"  {Colors.YELLOW}⚠ Could not check status: {e}{Colors.NC}")
            return 'error'
    
    def wait_for_job(self, job_id, max_wait=300):
        """Wait for job completion with status checking"""
        start_time = time.time()
        last_status = None
        
        while time.time() - start_time < max_wait:
            status = self.check_job_status(job_id)
            
            if status != last_status:
                elapsed = int(time.time() - start_time)
                if status == 'processing':
                    print(f"  ⏳ [{elapsed}s] Job is processing...")
                elif status == 'completed':
                    print(f"  {Colors.GREEN}✓ [{elapsed}s] Image generated successfully!{Colors.NC}")
                    self.stats['completed'] += 1
                    self.stats['cost'] += 0.04
                    return True
                elif status == 'failed':
                    print(f"  {Colors.RED}✗ [{elapsed}s] Image generation failed{Colors.NC}")
                    self.stats['failed'] += 1
                    return False
                last_status = status
            
            time.sleep(10)  # Check every 10 seconds
        
        print(f"  {Colors.YELLOW}⚠ Timeout after {max_wait}s{Colors.NC}")
        self.stats['failed'] += 1
        return False
    
    def submit_image_job(self, quote):
        """Submit a single image generation job"""
        try:
            response = requests.post(
                f"{self.api_url}/admin/generate-image",
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {self.access_token}'
                },
                json={
                    'quote': quote['quote'],
                    'author': quote['author'],
                    'tags': ', '.join(quote.get('tags', [])),
                    'quote_id': quote['id']
                },
                timeout=30
            )
            
            if response.status_code in [200, 202]:
                job_data = response.json()
                job_id = job_data.get('job_id') or job_data.get('jobId')
                if job_id:
                    self.stats['submitted'] += 1
                    return job_id
            
            print(f"  {Colors.RED}✗ Submission failed: HTTP {response.status_code}{Colors.NC}")
            return None
            
        except Exception as e:
            print(f"  {Colors.RED}✗ Error submitting: {e}{Colors.NC}")
            return None
    
    def process_batch(self, batch_size=10):
        """Process a batch of quotes with smart handling"""
        print(f"{Colors.BLUE}📋 Fetching quotes without images...{Colors.NC}")
        
        # Get quotes without images
        response = requests.get(
            f"{self.api_url}/admin/quotes",
            headers={
                'Authorization': f'Bearer {self.access_token}',
                'Content-Type': 'application/json'
            },
            params={
                'limit': 500,
                'sort_by': 'created_at',
                'sort_order': 'asc'
            }
        )
        
        if response.status_code != 200:
            print(f"{Colors.RED}Failed to fetch quotes{Colors.NC}")
            return False
        
        quotes = response.json().get('quotes', [])
        quotes_without_images = [q for q in quotes if not q.get('image_url')]
        
        print(f"Found {len(quotes_without_images)} quotes without images\n")
        
        # Process batch
        batch = quotes_without_images[:batch_size]
        
        for i, quote in enumerate(batch, 1):
            print(f"{Colors.PURPLE}━━━ Quote {i}/{len(batch)} ━━━{Colors.NC}")
            print(f"  📝 \"{quote['quote'][:60]}...\"")
            print(f"  👤 {quote['author']}")
            
            # Submit job
            job_id = self.submit_image_job(quote)
            
            if job_id:
                print(f"  📤 Job submitted: {job_id}")
                
                # Wait for completion with status checking
                success = self.wait_for_job(job_id)
                
                if not success:
                    # Retry once if failed
                    print(f"  🔄 Retrying...")
                    job_id = self.submit_image_job(quote)
                    if job_id:
                        self.stats['retried'] += 1
                        self.wait_for_job(job_id)
            
            print()
            
            # Brief pause between submissions
            time.sleep(2)
        
        return True
    
    def show_statistics(self):
        """Display session statistics"""
        print(f"\n{Colors.CYAN}📊 SESSION STATISTICS{Colors.NC}")
        print(f"  Submitted: {self.stats['submitted']}")
        print(f"  Completed: {Colors.GREEN}{self.stats['completed']}{Colors.NC}")
        print(f"  Failed: {Colors.RED}{self.stats['failed']}{Colors.NC}")
        print(f"  Retried: {Colors.YELLOW}{self.stats['retried']}{Colors.NC}")
        print(f"  Estimated Cost: ${self.stats['cost']:.2f}")
        
        if self.stats['submitted'] > 0:
            success_rate = (self.stats['completed'] / self.stats['submitted']) * 100
            print(f"  Success Rate: {success_rate:.1f}%")
    
    def cleanup(self):
        """Clean up resources"""
        if self.admin_email:
            try:
                self.cognito_client.admin_delete_user(
                    UserPoolId=self.user_pool_id,
                    Username=self.admin_email
                )
                print(f"\n{Colors.GREEN}✓ Cleaned up admin user{Colors.NC}")
            except:
                pass
    
    def run(self, batch_size=None, auto_mode=False):
        """Main execution
        
        Args:
            batch_size: Number of quotes per batch (default 10)
            auto_mode: If True, run continuously without prompting
        """
        print(f"{Colors.PURPLE}╔═══════════════════════════════════════╗{Colors.NC}")
        print(f"{Colors.PURPLE}║    SMART BULK IMAGE GENERATOR 🎨     ║{Colors.NC}")
        print(f"{Colors.PURPLE}╚═══════════════════════════════════════╝{Colors.NC}\n")
        
        if batch_size is None:
            batch_size = 10
            
        if auto_mode:
            print(f"{Colors.CYAN}🤖 AUTO MODE: Processing {batch_size} quotes per batch{Colors.NC}")
            print(f"{Colors.CYAN}   Press Ctrl+C to stop gracefully{Colors.NC}\n")
        
        if not self.setup_admin_user():
            return
        
        try:
            while True:
                if auto_mode:
                    # In auto mode, just process batches continuously
                    print(f"\n{Colors.BLUE}🚀 Processing next batch of {batch_size} quotes...{Colors.NC}")
                    if not self.process_batch(batch_size):
                        print(f"{Colors.GREEN}✨ All quotes processed!{Colors.NC}")
                        break
                    self.show_statistics()
                    # Brief pause between batches
                    time.sleep(5)
                else:
                    # Interactive mode - ask for confirmation
                    print(f"\n{Colors.YELLOW}Process batch of {batch_size} quotes? (y/n/q): {Colors.NC}", end='')
                    choice = input().lower()
                    
                    if choice == 'q':
                        break
                    elif choice == 'y':
                        if not self.process_batch(batch_size):
                            break
                        self.show_statistics()
                    else:
                        break
                    
        except KeyboardInterrupt:
            print(f"\n{Colors.YELLOW}⚠️  Interrupted by user - finishing current job...{Colors.NC}")
        finally:
            self.show_statistics()
            self.cleanup()

if __name__ == "__main__":
    # Parse command line arguments
    batch_size = 100  # Default for overnight runs
    auto_mode = False
    
    if len(sys.argv) > 1:
        try:
            batch_size = int(sys.argv[1])
            print(f"Using batch size: {batch_size}")
        except ValueError:
            print(f"Invalid batch size: {sys.argv[1]}, using default: {batch_size}")
    
    # If batch size is provided, assume auto mode
    if len(sys.argv) > 1:
        auto_mode = True
    
    generator = SmartBulkGenerator()
    generator.run(batch_size=batch_size, auto_mode=auto_mode)
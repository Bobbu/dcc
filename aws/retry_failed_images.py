#!/usr/bin/env python3

"""
Retry Failed Image Generation Jobs
Finds quotes that had failed image generation attempts and retries them.
"""

import boto3
import requests
import json
import time
from datetime import datetime, timedelta

# Configuration
api_url = "https://dcc.anystupididea.com"
user_pool_id = "us-east-1_WCJMgcwll"
user_pool_client_id = "308apko2vm7tphi0c74ec209cc"

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    BLUE = '\033[0;34m'
    PURPLE = '\033[0;35m'
    NC = '\033[0m'

def find_failed_quotes():
    """Find quotes that failed image generation in recent logs"""
    print(f"{Colors.YELLOW}🔍 Searching for failed image generation attempts...{Colors.NC}")
    
    # Get CloudWatch logs
    logs_client = boto3.client('logs')
    
    # Search for failed jobs in the last 24 hours
    start_time = int((datetime.now() - timedelta(hours=24)).timestamp() * 1000)
    end_time = int(datetime.now().timestamp() * 1000)
    
    failed_quote_ids = set()
    
    try:
        # Search processor logs for failures
        response = logs_client.filter_log_events(
            logGroupName='/aws/lambda/quote-me-image-generation-processor',
            startTime=start_time,
            endTime=end_time,
            filterPattern='failed'
        )
        
        for event in response.get('events', []):
            message = event['message']
            # Extract quote ID from update attempts that preceded failures
            if 'Updated quote' in message:
                # Skip successful updates
                continue
            elif 'Processing image generation job' in message:
                # This is a job that was attempted - need to check if it failed
                # Get the job ID and check next messages
                pass
        
        # More robust: Query DynamoDB for quotes without images that have old updated_at
        
    except Exception as e:
        print(f"{Colors.RED}Error searching logs: {e}{Colors.NC}")
    
    return list(failed_quote_ids)

def retry_with_admin_auth():
    """Main retry process with admin authentication"""
    
    # Create temp admin user
    cognito = boto3.client('cognito-idp')
    dynamodb = boto3.resource('dynamodb')
    quotes_table = dynamodb.Table('quote-me-quotes')
    
    admin_email = f"retry-{int(time.time())}@quoteme.admin"
    admin_password = "RetryAdmin123!"
    
    try:
        print(f"{Colors.BLUE}🔧 Setting up admin access...{Colors.NC}")
        
        # Create admin user
        cognito.admin_create_user(
            UserPoolId=user_pool_id,
            Username=admin_email,
            UserAttributes=[
                {'Name': 'email', 'Value': admin_email},
                {'Name': 'name', 'Value': 'Retry Admin'},
                {'Name': 'email_verified', 'Value': 'true'}
            ],
            TemporaryPassword=admin_password,
            MessageAction='SUPPRESS'
        )
        
        # Set permanent password
        cognito.admin_set_user_password(
            UserPoolId=user_pool_id,
            Username=admin_email,
            Password=admin_password,
            Permanent=True
        )
        
        # Add to Admins group
        cognito.admin_add_user_to_group(
            UserPoolId=user_pool_id,
            Username=admin_email,
            GroupName='Admins'
        )
        
        # Authenticate
        auth_response = cognito.initiate_auth(
            ClientId=user_pool_client_id,
            AuthFlow='USER_PASSWORD_AUTH',
            AuthParameters={
                'USERNAME': admin_email,
                'PASSWORD': admin_password
            }
        )
        
        id_token = auth_response['AuthenticationResult']['IdToken']
        
        print(f"{Colors.GREEN}✓ Admin access ready{Colors.NC}\n")
        
        # Find specific quotes we know failed
        known_failed = [
            ('613ec8a6-269f-451a-b264-504e3ee61471', 'Al Pacino'),  # Timeout
            # Add more known failures here
        ]
        
        # Also search for quotes without images
        print(f"{Colors.BLUE}📊 Scanning for quotes without images...{Colors.NC}")
        
        response = requests.get(
            f"{api_url}/admin/quotes",
            headers={
                'Authorization': f'Bearer {id_token}',
                'Content-Type': 'application/json'
            },
            params={
                'limit': 100,
                'sort_by': 'updated_at',
                'sort_order': 'desc'  # Get recently attempted ones
            }
        )
        
        if response.status_code == 200:
            data = response.json()
            quotes = data.get('quotes', [])
            
            # Find quotes without images that were updated recently (likely failed)
            candidates = []
            for q in quotes:
                if not q.get('image_url'):
                    updated = q.get('updated_at', '')
                    # If updated in last 24 hours but no image, likely failed
                    if updated and '2025-09-15' in updated:
                        candidates.append((q['id'], q['author'], q['quote'][:50]))
            
            if candidates:
                print(f"{Colors.YELLOW}Found {len(candidates)} quotes that likely failed:{Colors.NC}")
                for qid, author, text in candidates[:10]:
                    print(f"  • {author}: {text}...")
                
                print(f"\n{Colors.YELLOW}Retry these quotes? (y/n): {Colors.NC}", end='')
                if input().lower() == 'y':
                    for qid, author, text in candidates:
                        print(f"\n{Colors.BLUE}🔄 Retrying: {author} - {text}...{Colors.NC}")
                        
                        # Get full quote details
                        quote_resp = requests.get(
                            f"{api_url}/quote/{qid}",
                            headers={'x-api-key': 'iJF7oVCPHLaeWfYPhkuy71izWFoXrr8qawS4drL1'}
                        )
                        
                        if quote_resp.status_code == 200:
                            quote = quote_resp.json()
                            
                            # Submit for image generation
                            retry_resp = requests.post(
                                f"{api_url}/admin/generate-image",
                                headers={
                                    'Content-Type': 'application/json',
                                    'Authorization': f'Bearer {id_token}'
                                },
                                json={
                                    'quote': quote['quote'],
                                    'author': quote['author'],
                                    'tags': ', '.join(quote.get('tags', [])),
                                    'quote_id': qid
                                },
                                timeout=30
                            )
                            
                            if retry_resp.status_code in [200, 202]:
                                job_data = retry_resp.json()
                                job_id = job_data.get('job_id') or job_data.get('jobId')
                                print(f"  {Colors.GREEN}✓ Resubmitted (Job: {job_id}){Colors.NC}")
                                
                                # Wait 2 minutes between retries to avoid overwhelming OpenAI
                                print(f"  ⏱️  Waiting 2 minutes before next retry...")
                                time.sleep(120)
                            else:
                                print(f"  {Colors.RED}✗ Failed to resubmit: {retry_resp.status_code}{Colors.NC}")
                        
                        # Don't retry too many at once
                        if candidates.index((qid, author, text)) >= 10:
                            print(f"\n{Colors.YELLOW}Stopping after 10 retries. Run again for more.{Colors.NC}")
                            break
            else:
                print(f"{Colors.GREEN}No recent failed quotes found!{Colors.NC}")
                
    finally:
        # Clean up
        try:
            cognito.admin_delete_user(
                UserPoolId=user_pool_id,
                Username=admin_email
            )
            print(f"\n{Colors.GREEN}✓ Cleaned up temp admin{Colors.NC}")
        except:
            pass

if __name__ == "__main__":
    print(f"{Colors.PURPLE}╔════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.PURPLE}║   RETRY FAILED IMAGE GENERATION JOBS   ║{Colors.NC}")
    print(f"{Colors.PURPLE}╚════════════════════════════════════════╝{Colors.NC}\n")
    
    retry_with_admin_auth()
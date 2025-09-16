#!/usr/bin/env python3

import boto3
import requests
import json
import time
from datetime import datetime

# Configuration
api_url = "https://dcc.anystupididea.com"
user_pool_id = "us-east-1_WCJMgcwll"
user_pool_client_id = "308apko2vm7tphi0c74ec209cc"

# Create temp admin user
cognito_client = boto3.client('cognito-idp')
admin_email = f"check-admin-{int(time.time())}@quoteme.admin"
admin_password = "CheckAdmin123!"

try:
    # Create admin user
    print("Creating temporary admin user...")
    cognito_client.admin_create_user(
        UserPoolId=user_pool_id,
        Username=admin_email,
        UserAttributes=[
            {'Name': 'email', 'Value': admin_email},
            {'Name': 'name', 'Value': 'Check Admin'},
            {'Name': 'email_verified', 'Value': 'true'}
        ],
        TemporaryPassword=admin_password,
        MessageAction='SUPPRESS'
    )
    
    # Set permanent password
    cognito_client.admin_set_user_password(
        UserPoolId=user_pool_id,
        Username=admin_email,
        Password=admin_password,
        Permanent=True
    )
    
    # Add to Admins group
    cognito_client.admin_add_user_to_group(
        UserPoolId=user_pool_id,
        Username=admin_email,
        GroupName='Admins'
    )
    
    # Authenticate
    auth_response = cognito_client.initiate_auth(
        ClientId=user_pool_client_id,
        AuthFlow='USER_PASSWORD_AUTH',
        AuthParameters={
            'USERNAME': admin_email,
            'PASSWORD': admin_password
        }
    )
    
    id_token = auth_response['AuthenticationResult']['IdToken']
    
    # Get quotes from admin API
    print("\nFetching quotes from admin API...")
    response = requests.get(
        f"{api_url}/admin/quotes",
        headers={
            'Authorization': f'Bearer {id_token}',
            'Content-Type': 'application/json'
        },
        params={'limit': 100}
    )
    
    if response.status_code == 200:
        data = response.json()
        quotes = data.get('quotes', [])
        
        # Analyze the data
        total_quotes = len(quotes)
        with_images = 0
        without_images = 0
        empty_string_images = 0
        null_images = 0
        
        print(f"\nAnalyzing {total_quotes} quotes...")
        print("-" * 50)
        
        for q in quotes:
            if 'image_url' in q:
                if q['image_url'] is None:
                    null_images += 1
                    without_images += 1
                elif q['image_url'] == '':
                    empty_string_images += 1
                    without_images += 1
                else:
                    with_images += 1
                    if with_images <= 3:  # Show first 3 with images
                        print(f"Quote with image: {q['id'][:20]}...")
                        print(f"  URL: {q['image_url'][:60]}...")
            else:
                without_images += 1
        
        print(f"\nSummary:")
        print(f"Total quotes in batch: {total_quotes}")
        print(f"With valid images: {with_images}")
        print(f"Without images: {without_images}")
        print(f"  - NULL image_url: {null_images}")
        print(f"  - Empty string image_url: {empty_string_images}")
        print(f"  - Missing image_url field: {without_images - null_images - empty_string_images}")
        
        # Check the filtering logic
        print(f"\nTesting filter logic:")
        filtered = [q for q in quotes if not q.get('image_url')]
        print(f"Quotes that pass 'not q.get(\"image_url\")' filter: {len(filtered)}")
        
        # Show what the filter is catching
        if filtered and with_images > 0:
            print("\nWARNING: Filter might be wrong!")
            print("Sample of what passes the filter:")
            for q in filtered[:3]:
                print(f"  ID: {q['id'][:20]}... image_url: {repr(q.get('image_url'))}")
    else:
        print(f"Error: {response.status_code}")
        print(response.text)
        
finally:
    # Clean up
    try:
        cognito_client.admin_delete_user(
            UserPoolId=user_pool_id,
            Username=admin_email
        )
        print("\nCleaned up temp admin user")
    except:
        pass
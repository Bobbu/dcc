#!/usr/bin/env python3

import boto3
import requests
import json
import time

# Configuration
api_url = "https://dcc.anystupididea.com"
user_pool_id = "us-east-1_WCJMgcwll"
user_pool_client_id = "308apko2vm7tphi0c74ec209cc"

# Create temp admin
cognito = boto3.client('cognito-idp')
admin_email = f'debug-{int(time.time())}@admin.com'
admin_pass = 'Debug123!'

try:
    # Quick admin setup
    cognito.admin_create_user(
        UserPoolId=user_pool_id,
        Username=admin_email,
        UserAttributes=[
            {'Name': 'email', 'Value': admin_email},
            {'Name': 'email_verified', 'Value': 'true'}
        ],
        TemporaryPassword=admin_pass,
        MessageAction='SUPPRESS'
    )
    cognito.admin_set_user_password(
        UserPoolId=user_pool_id,
        Username=admin_email,
        Password=admin_pass,
        Permanent=True
    )
    cognito.admin_add_user_to_group(
        UserPoolId=user_pool_id,
        Username=admin_email,
        GroupName='Admins'
    )
    
    # Auth
    auth = cognito.initiate_auth(
        ClientId=user_pool_client_id,
        AuthFlow='USER_PASSWORD_AUTH',
        AuthParameters={'USERNAME': admin_email, 'PASSWORD': admin_pass}
    )
    token = auth['AuthenticationResult']['IdToken']
    
    # Get quotes the same way bulk generator does
    print("Fetching quotes with sort_by=created_at, sort_order=asc...")
    response = requests.get(
        f"{api_url}/admin/quotes",
        headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json'
        },
        params={
            'limit': 500,
            'sort_by': 'created_at',
            'sort_order': 'asc'
        }
    )
    
    if response.status_code == 200:
        data = response.json()
        quotes = data.get('quotes', [])
        
        # Find Al Pacino quote
        pacino_found = False
        for i, q in enumerate(quotes):
            if q.get('id') == '613ec8a6-269f-451a-b264-504e3ee61471':
                pacino_found = True
                print(f"\n✅ Found Al Pacino quote at position {i}:")
                print(f"  Author: {q.get('author')}")
                print(f"  Quote: {q.get('quote')[:60]}...")
                print(f"  Has image: {bool(q.get('image_url'))}")
                break
        
        if not pacino_found:
            print(f"\n❌ Al Pacino quote NOT in the first {len(quotes)} quotes!")
            print("This explains why it wasn't processed.")
            
        # Check what we're getting
        quotes_without_images = [q for q in quotes if not q.get('image_url')]
        print(f"\nStats for first {len(quotes)} quotes (sorted by created_at ASC):")
        print(f"  Total: {len(quotes)}")
        print(f"  Without images: {len(quotes_without_images)}")
        print(f"  With images: {len(quotes) - len(quotes_without_images)}")
        
        # Show sample of quotes without images
        print(f"\nFirst 5 quotes without images:")
        for q in quotes_without_images[:5]:
            print(f"  - {q.get('author')}: {q.get('quote')[:40]}...")
            
finally:
    cognito.admin_delete_user(UserPoolId=user_pool_id, Username=admin_email)
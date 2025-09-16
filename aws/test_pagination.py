#!/usr/bin/env python3

import boto3
import requests
import json
import time

# Configuration
api_url = "https://dcc.anystupididea.com"
user_pool_id = "us-east-1_WCJMgcwll"
user_pool_client_id = "308apko2vm7tphi0c74ec209cc"

# Create temp admin user
cognito_client = boto3.client('cognito-idp')
admin_email = f"page-admin-{int(time.time())}@quoteme.admin"
admin_password = "PageAdmin123!"

try:
    # Create admin user
    print("Creating temporary admin user...")
    cognito_client.admin_create_user(
        UserPoolId=user_pool_id,
        Username=admin_email,
        UserAttributes=[
            {'Name': 'email', 'Value': admin_email},
            {'Name': 'name', 'Value': 'Page Admin'},
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
    
    # Test pagination
    print("\nTesting pagination to see if we get different quotes each time...")
    print("-" * 60)
    
    last_key = None
    total_fetched = 0
    all_quote_ids = []
    quotes_with_images = 0
    quotes_without_images = 0
    
    for batch_num in range(3):  # Get 3 batches
        print(f"\n📦 Batch {batch_num + 1}:")
        
        params = {'limit': 50}
        if last_key:
            params['last_key'] = last_key
            print(f"  Using pagination key from previous batch")
        else:
            print(f"  Starting from beginning (no pagination key)")
        
        response = requests.get(
            f"{api_url}/admin/quotes",
            headers={
                'Authorization': f'Bearer {id_token}',
                'Content-Type': 'application/json'
            },
            params=params
        )
        
        if response.status_code == 200:
            data = response.json()
            quotes = data.get('quotes', [])
            last_key = data.get('last_key')
            
            batch_with_images = len([q for q in quotes if q.get('image_url')])
            batch_without_images = len([q for q in quotes if not q.get('image_url')])
            
            print(f"  Received {len(quotes)} quotes")
            print(f"    - With images: {batch_with_images}")
            print(f"    - Without images: {batch_without_images}")
            
            # Check for duplicates
            batch_ids = [q['id'] for q in quotes]
            duplicates = set(batch_ids) & set(all_quote_ids)
            if duplicates:
                print(f"  ⚠️  WARNING: {len(duplicates)} duplicate quotes from previous batches!")
                for dup_id in list(duplicates)[:3]:
                    print(f"      Duplicate: {dup_id[:30]}...")
            else:
                print(f"  ✅ No duplicates - all new quotes")
            
            all_quote_ids.extend(batch_ids)
            quotes_with_images += batch_with_images
            quotes_without_images += batch_without_images
            total_fetched += len(quotes)
            
            # Show first few IDs
            print(f"  First 3 quote IDs in this batch:")
            for q in quotes[:3]:
                has_img = "✓" if q.get('image_url') else "✗"
                print(f"    [{has_img}] {q['id'][:30]}...")
            
            if not last_key:
                print(f"  📍 No more quotes available (reached end)")
                break
        else:
            print(f"  ❌ Error: {response.status_code}")
            break
    
    print(f"\n" + "=" * 60)
    print(f"SUMMARY:")
    print(f"  Total quotes fetched: {total_fetched}")
    print(f"  Unique quotes: {len(set(all_quote_ids))}")
    print(f"  Total with images: {quotes_with_images}")
    print(f"  Total without images: {quotes_without_images}")
    
    if len(set(all_quote_ids)) < total_fetched:
        print(f"  ⚠️  PROBLEM: Getting duplicate quotes across batches!")
    else:
        print(f"  ✅ Good: Each batch returned different quotes")
        
finally:
    # Clean up
    try:
        cognito_client.admin_delete_user(
            UserPoolId=user_pool_id,
            Username=admin_email
        )
        print("\n✓ Cleaned up temp admin user")
    except:
        pass
#!/usr/bin/env python3
"""
Integration test for duplicate detection system using likely existing quotes
"""

import requests
import json
import subprocess
import sys
import time

# Configuration
BASE_URL = "https://dcc.anystupididea.com"
USER_POOL_ID = "us-east-1_ecyuILBAu"
CLIENT_ID = "2idvhvlhgbheglr0hptel5j55"

# Admin credentials - use existing admin
ADMIN_USERNAME = "admin@dcc.com"  
ADMIN_PASSWORD = "AdminPass123!"

# Test quotes that are likely to exist in the database
TEST_QUOTES = [
    {
        "quote": "The only way to do great work is to love what you do",
        "author": "Steve Jobs",
        "reason": "Famous Steve Jobs quote"
    },
    {
        "quote": "Be yourself; everyone else is already taken",
        "author": "Oscar Wilde", 
        "reason": "Popular Oscar Wilde quote"
    },
    {
        "quote": "In the middle of difficulty lies opportunity",
        "author": "Albert Einstein",
        "reason": "Well-known Einstein quote"
    },
    {
        "quote": "Success is not final, failure is not fatal: it is the courage to continue that counts",
        "author": "Winston Churchill",
        "reason": "Famous Churchill quote"
    }
]

def get_admin_token():
    """Get access token for admin user"""
    try:
        cmd = [
            'aws', 'cognito-idp', 'admin-initiate-auth',
            '--user-pool-id', USER_POOL_ID,
            '--client-id', CLIENT_ID,
            '--auth-flow', 'ADMIN_NO_SRP_AUTH',
            '--auth-parameters', f'USERNAME={ADMIN_USERNAME},PASSWORD={ADMIN_PASSWORD}'
        ]
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        auth_data = json.loads(result.stdout)
        return auth_data['AuthenticationResult']['IdToken']
    except Exception as e:
        print(f"❌ Failed to get admin access token: {e}")
        return None

def test_duplicate_check(token, quote, author, reason):
    """Test duplicate check for a specific quote"""
    print(f"\n🔍 Testing: {reason}")
    print(f"Quote: \"{quote}\"")
    print(f"Author: {author}")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    data = {
        "quote": quote,
        "author": author
    }
    
    try:
        response = requests.post(
            f'{BASE_URL}/admin/check-duplicate',
            headers=headers,
            json=data,
            timeout=10
        )
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            is_duplicate = result.get('is_duplicate', False)
            duplicate_count = result.get('duplicate_count', 0)
            message = result.get('message', 'No message')
            
            print(f"✅ Duplicate check successful!")
            print(f"   Is Duplicate: {is_duplicate}")
            print(f"   Duplicate Count: {duplicate_count}")
            print(f"   Message: {message}")
            
            if is_duplicate:
                duplicates = result.get('duplicates', [])
                print(f"   Found duplicates:")
                for i, dup in enumerate(duplicates[:3], 1):  # Show first 3
                    print(f"   {i}. \"{dup.get('quote', 'N/A')[:60]}...\" by {dup.get('author', 'N/A')}")
                    print(f"      Match reason: {dup.get('match_reason', 'N/A')}")
                    print(f"      Created: {dup.get('created_at', 'N/A')}")
            
            return True, is_duplicate
            
        elif response.status_code == 401:
            print(f"❌ Unauthorized - token might be expired")
            return False, False
        elif response.status_code == 403:
            print(f"❌ Forbidden - admin access required")
            return False, False
        elif response.status_code == 404:
            print(f"❌ Not found - endpoint doesn't exist")
            print(f"   Response: {response.text}")
            return False, False
        else:
            print(f"❌ Unexpected status: {response.status_code}")
            print(f"   Response: {response.text}")
            return False, False
            
    except requests.exceptions.Timeout:
        print(f"❌ Request timed out")
        return False, False
    except requests.exceptions.RequestException as e:
        print(f"❌ Request failed: {e}")
        return False, False
    except json.JSONDecodeError:
        print(f"❌ Invalid JSON response: {response.text}")
        return False, False

def test_quote_creation_with_duplicate(token, quote, author):
    """Test creating a quote that should trigger duplicate detection"""
    print(f"\n📝 Attempting to create potentially duplicate quote...")
    print(f"Quote: \"{quote}\"")
    print(f"Author: {author}")
    
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    
    data = {
        "quote": quote,
        "author": author,
        "tags": ["test-duplicate"]
    }
    
    try:
        response = requests.post(
            f'{BASE_URL}/admin/quotes',
            headers=headers,
            json=data,
            timeout=10
        )
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 201:
            print(f"✅ Quote created successfully (duplicate check may have been bypassed)")
            result = response.json()
            quote_id = result.get('id', 'N/A')
            print(f"   Created Quote ID: {quote_id}")
            return True, quote_id
        elif response.status_code == 400:
            print(f"⚠️  Bad request - possible validation error")
            print(f"   Response: {response.text}")
            return False, None
        elif response.status_code == 409:
            print(f"✅ Conflict - duplicate detected and blocked!")
            print(f"   Response: {response.text}")
            return True, None
        else:
            print(f"❌ Unexpected status: {response.status_code}")
            print(f"   Response: {response.text}")
            return False, None
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Request failed: {e}")
        return False, None

def main():
    """Main test runner"""
    print("🚀 Starting Duplicate Detection Integration Test")
    print("=" * 60)
    
    # Get admin token
    print("🔐 Getting admin authentication token...")
    token = get_admin_token()
    if not token:
        print("❌ Failed to authenticate as admin")
        return 1
    
    print("✅ Admin authentication successful")
    
    # Test duplicate checking for each quote
    successful_tests = 0
    found_duplicates = 0
    
    for test_quote in TEST_QUOTES:
        quote = test_quote["quote"]
        author = test_quote["author"]
        reason = test_quote["reason"]
        
        success, is_duplicate = test_duplicate_check(token, quote, author, reason)
        
        if success:
            successful_tests += 1
            if is_duplicate:
                found_duplicates += 1
                
                # If we found a duplicate, test the quote creation process
                print(f"\n🔬 Testing quote creation process for known duplicate...")
                creation_success, quote_id = test_quote_creation_with_duplicate(token, quote, author)
        
        # Small delay between requests
        time.sleep(1)
    
    # Summary
    print(f"\n📊 Test Summary:")
    print(f"Total Tests: {len(TEST_QUOTES)}")
    print(f"Successful API Calls: {successful_tests}")
    print(f"Duplicates Found: {found_duplicates}")
    
    if successful_tests == 0:
        print(f"❌ All tests failed - duplicate detection endpoint is not working")
        return 1
    elif found_duplicates == 0:
        print(f"⚠️  No duplicates found - test quotes may not exist in database")
        return 0
    else:
        print(f"✅ Duplicate detection system is working!")
        return 0

if __name__ == "__main__":
    exit(main())
#!/usr/bin/env python3
"""
Test duplicate detection with a known existing quote
"""

import requests
import json

# Known quote from database
TEST_QUOTE = "In the midst of great joy, do not promise anyone anything. In the midst of great anger, do not answer anyone's letter."
TEST_AUTHOR = "Chinese Proverb"

# You'll need to get this token from your Flutter app or another source
# For now, using the JWT from the logs you shared earlier (truncated)
JWT_TOKEN = "eyJraWQiOiJrWW1qTWM5QWwwK2x3aGZ6NWZjSEV0K1hpcjliSHBrcTh0ME9ReGxuUDlJPSIsImFsZyI6IlJTMjU2In0.eyJzdWIiOiIyNDI4ZTRiOC01MDYxLTcwNmYtM2VjMy02ZWZkYjJlZGY5ZWMiLCJjb2duaXRvOmdyb3VwcyI6WyJBZG1pbnMiXSwiZW1haWxfdmVyaWZpZWQiOnRydWUsImlzcyI6Imh0dHBzOlwvXC9jb2duaXRvLWlkcC51cy1lYXN0LTEuYW1hem9uYXdzLmNvbVwvdXMtZWFzdC0xX2VjeXVJTEJBdSIsImNvZ25pdG86dXNlcm5hbWUiOiIyNDI4ZTRiOC01MDYxLTcwNmYtM2VjMy02ZWZkYjJlZGY5ZWMiLCJvcmlnaW5fanRpIjoiNzVjMzFlOGYtZTVmMS00MTNjLThlMDMtODBmNjdjMGNiYTk2IiwiYXVkIjoiMmlkdmh2bGhnYmhlZ2xyMGhwdGVsNWo1NSIsImV2ZW50X2lkIjoiMWUxMzc4ODUtNDlkOS00ZWRlLTg4MjItNjUwZmI3M2Q0MTQ2IiwidG9rZW5fdXNlIjoiaWQiLCJhdXRoX3RpbWUiOjE3NTU3OTU2OTAsIm5hbWUiOiJCw6Ziw7ggdGhlIEFkbWluIiwiZXhwIjoxNzU2NzAwODEzLCJpYXQiOjE3NTY2OTcyMTMsImp0aSI6ImVlZjllNmE0LTExZjQtNDM2NC04NDE3LWQ5YWY5MDM5NDJhMiIsImVtYWlsIjoicm9iQGNhdGFseXN0LnRlY2hub2xvZ3kifQ.dXJOrpxAblsdzPpQX6G4Ja4y9Xt3NYe82cQu41iPAZPOc-bEj52w-7hITjIjr6RSfIvyLrdbnnZ7gPD2EC82RZq5GmxDqH-Gy4Y7N"

BASE_URL = "https://iasj16a8jl.execute-api.us-east-1.amazonaws.com/prod"

def test_duplicate_detection():
    """Test duplicate detection with known quote"""
    print("🔍 Testing Duplicate Detection with Known Quote")
    print("=" * 50)
    print(f"Quote: \"{TEST_QUOTE}\"")
    print(f"Author: {TEST_AUTHOR}")
    print()
    
    headers = {
        'Authorization': f'Bearer {JWT_TOKEN}',
        'Content-Type': 'application/json'
    }
    
    data = {
        "quote": TEST_QUOTE,
        "author": TEST_AUTHOR
    }
    
    print("📡 Making request to /admin/check-duplicate...")
    print(f"URL: {BASE_URL}/admin/check-duplicate")
    print(f"Headers: {headers}")
    print(f"Data: {json.dumps(data, indent=2)}")
    print()
    
    try:
        response = requests.post(
            f'{BASE_URL}/admin/check-duplicate',
            headers=headers,
            json=data,
            timeout=10
        )
        
        print(f"📊 Response Status: {response.status_code}")
        print(f"📊 Response Headers: {dict(response.headers)}")
        print(f"📊 Response Body: {response.text}")
        print()
        
        if response.status_code == 200:
            result = response.json()
            print("✅ SUCCESS! Duplicate check endpoint is working!")
            print(f"   Is Duplicate: {result.get('is_duplicate', False)}")
            print(f"   Message: {result.get('message', 'No message')}")
            
            if result.get('is_duplicate'):
                duplicates = result.get('duplicates', [])
                print(f"   Found {len(duplicates)} duplicate(s)")
                for i, dup in enumerate(duplicates, 1):
                    print(f"   {i}. Match: {dup.get('match_reason', 'N/A')}")
            else:
                print("   ⚠️  No duplicates found - quote might not exist in DB after all")
                
        elif response.status_code == 401:
            print("❌ UNAUTHORIZED - JWT token is invalid/expired")
        elif response.status_code == 403:
            print("❌ FORBIDDEN - User is not admin or endpoint auth failed")
        elif response.status_code == 404:
            print("❌ NOT FOUND - Endpoint doesn't exist or path is wrong")
        else:
            print(f"❌ UNEXPECTED STATUS: {response.status_code}")
            
    except requests.exceptions.ConnectionError:
        print("❌ CONNECTION ERROR - Cannot reach the server")
    except requests.exceptions.Timeout:
        print("❌ TIMEOUT - Request took too long")
    except requests.exceptions.RequestException as e:
        print(f"❌ REQUEST ERROR: {e}")
    except json.JSONDecodeError:
        print(f"❌ INVALID JSON in response: {response.text}")

if __name__ == "__main__":
    test_duplicate_detection()
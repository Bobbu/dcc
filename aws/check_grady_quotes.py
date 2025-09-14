#!/usr/bin/env python3
"""
Direct DynamoDB check for Grady Booch quotes
"""

import boto3
import json
from boto3.dynamodb.conditions import Key, Attr

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('quote-me-quotes')

def search_grady_booch_quotes():
    """Search for existing Grady Booch quotes directly in DynamoDB"""
    print("Searching for Grady Booch quotes in DynamoDB...")
    
    try:
        # Scan the table looking for Grady Booch quotes
        response = table.scan(
            FilterExpression=Attr('author').contains('Grady') | Attr('author').contains('Booch')
        )
        
        items = response.get('Items', [])
        grady_quotes = []
        
        for item in items:
            # Skip metadata items
            if item.get('id', '').startswith('TAGS_') or not item.get('quote'):
                continue
                
            author = item.get('author', '').lower()
            if 'grady' in author and 'booch' in author:
                grady_quotes.append(item)
        
        print(f"Found {len(grady_quotes)} quotes by Grady Booch:")
        for i, quote in enumerate(grady_quotes, 1):
            print(f"{i}. '{quote['quote'][:80]}...'")
            print(f"   Author: {quote['author']}")
            print(f"   ID: {quote['id']}")
            print(f"   Created: {quote.get('created_at', 'Unknown')}")
            print()
        
        return grady_quotes
        
    except Exception as e:
        print(f"Error searching DynamoDB: {e}")
        return []

def check_total_quotes():
    """Check total number of quotes in database"""
    try:
        response = table.scan(
            Select='COUNT',
            FilterExpression=Attr('id').not_exists() | (~Attr('id').begins_with('TAGS_'))
        )
        
        # More accurate count by scanning all items
        scan_kwargs = {}
        total_quotes = 0
        
        while True:
            response = table.scan(**scan_kwargs)
            items = response.get('Items', [])
            
            # Count only actual quotes, not metadata
            for item in items:
                if not item.get('id', '').startswith('TAGS_') and item.get('quote'):
                    total_quotes += 1
            
            if 'LastEvaluatedKey' not in response:
                break
            scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']
        
        print(f"Total quotes in database: {total_quotes}")
        
    except Exception as e:
        print(f"Error counting quotes: {e}")

if __name__ == "__main__":
    print("=== Direct DynamoDB Search for Grady Booch Quotes ===\n")
    
    # Check total quotes first
    check_total_quotes()
    print()
    
    # Search for Grady Booch quotes
    grady_quotes = search_grady_booch_quotes()
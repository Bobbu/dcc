#!/usr/bin/env python3
"""
Generate tags table from existing quotes
"""

import boto3
import json
from collections import Counter

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

def generate_tags_from_quotes():
    """Extract all unique tags from quotes and populate tags table"""
    quotes_table = dynamodb.Table('quote-me-quotes')
    tags_table = dynamodb.Table('quote-me-tags')
    
    print("Scanning quotes to extract tags...")
    
    # Scan all quotes
    response = quotes_table.scan()
    items = response['Items']
    
    while 'LastEvaluatedKey' in response:
        response = quotes_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])
    
    # Extract all tags
    all_tags = []
    for item in items:
        if 'tags' in item and item['tags']:
            all_tags.extend(item['tags'])
    
    # Count occurrences
    tag_counts = Counter(all_tags)
    unique_tags = set(all_tags)
    
    print(f"Found {len(unique_tags)} unique tags from {len(items)} quotes")
    
    # Write to tags table in batches
    with tags_table.batch_writer() as batch:
        for tag in unique_tags:
            batch.put_item(Item={
                'tag': tag,
                'count': tag_counts[tag]
            })
    
    print(f"Created tags table with {len(unique_tags)} tags")
    return len(unique_tags)

if __name__ == "__main__":
    generate_tags_from_quotes()
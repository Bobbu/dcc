#!/usr/bin/env python3
"""
Migrate data from old DCC tables to new Quote Me tables
"""

import boto3
import json
from decimal import Decimal

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def migrate_quotes():
    """Migrate quotes from dcc-quotes-optimized to quote-me-quotes"""
    old_table = dynamodb.Table('dcc-quotes-optimized')
    new_table = dynamodb.Table('quote-me-quotes')
    
    print("Migrating quotes...")
    
    # Scan old table
    response = old_table.scan()
    items = response['Items']
    
    while 'LastEvaluatedKey' in response:
        response = old_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])
    
    print(f"Found {len(items)} quotes to migrate")
    
    # Write to new table in batches
    with new_table.batch_writer() as batch:
        for item in items:
            # Skip any job records that might have been accidentally stored
            if 'job_id' in item or 'status' in item:
                continue
            
            # Ensure required fields exist
            if 'id' in item and 'quote' in item and 'author' in item:
                batch.put_item(Item=item)
    
    print(f"Migrated {len(items)} quotes successfully")
    return len(items)

def migrate_tags():
    """Migrate tags from dcc-tags to quote-me-tags"""
    old_table = dynamodb.Table('dcc-tags')
    new_table = dynamodb.Table('quote-me-tags')
    
    print("Migrating tags...")
    
    try:
        # Scan old table
        response = old_table.scan()
        items = response['Items']
        
        while 'LastEvaluatedKey' in response:
            response = old_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response['Items'])
        
        print(f"Found {len(items)} tags to migrate")
        
        # Write to new table in batches
        with new_table.batch_writer() as batch:
            for item in items:
                if 'tag' in item:
                    batch.put_item(Item=item)
        
        print(f"Migrated {len(items)} tags successfully")
        return len(items)
    except Exception as e:
        if "ResourceNotFoundException" in str(e):
            print("Old tags table not found, skipping tag migration")
            return 0
        raise

def main():
    print("Starting data migration from DCC to Quote Me tables...")
    
    quotes_count = migrate_quotes()
    tags_count = migrate_tags()
    
    print("\nMigration complete!")
    print(f"Total quotes migrated: {quotes_count}")
    print(f"Total tags migrated: {tags_count}")

if __name__ == "__main__":
    main()
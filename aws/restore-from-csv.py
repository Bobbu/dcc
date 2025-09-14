#!/usr/bin/env python3
"""
Restore quotes from CSV backup to new DynamoDB tables
"""

import boto3
import csv
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

def restore_quotes_from_csv(csv_filename):
    """Restore quotes from CSV to DynamoDB tables"""
    
    quotes_table_name = 'dcc-quotes-optimized-dcc-api-complete'
    tags_table_name = 'dcc-tags-dcc-api-complete'
    
    quotes_table = dynamodb.Table(quotes_table_name)
    tags_table = dynamodb.Table(tags_table_name)
    
    print(f"Restoring quotes from {csv_filename}...")
    print(f"Target tables: {quotes_table_name}, {tags_table_name}")
    
    quotes_restored = 0
    all_tags = set()
    
    # Read and restore quotes
    with open(csv_filename, 'r', encoding='utf-8') as csvfile:
        reader = csv.DictReader(csvfile)
        
        with quotes_table.batch_writer() as batch:
            for row in reader:
                quote_text = row['Quote'].strip()
                author = row['Author'].strip()
                
                if not quote_text or not author:
                    continue
                
                # Collect tags (Tag1 through Tag20)
                tags = []
                for i in range(1, 21):
                    tag = row.get(f'Tag{i}', '').strip()
                    if tag:
                        tags.append(tag)
                        all_tags.add(tag)
                
                # Create quote item
                quote_item = {
                    'id': str(uuid.uuid4()),
                    'quote': quote_text,
                    'author': author,
                    'tags': tags,
                    'created_at': datetime.utcnow().isoformat()
                }
                
                batch.put_item(Item=quote_item)
                quotes_restored += 1
    
    print(f"✓ Restored {quotes_restored} quotes")
    
    # Restore tags table
    print(f"Restoring {len(all_tags)} unique tags...")
    
    with tags_table.batch_writer() as batch:
        for tag in all_tags:
            batch.put_item(Item={'tag': tag})
    
    print(f"✓ Restored {len(all_tags)} tags")
    
    return quotes_restored, len(all_tags)

if __name__ == "__main__":
    csv_file = "quotes_export_20250911_152053.csv"
    quotes_restored, tags_restored = restore_quotes_from_csv(csv_file)
    
    print(f"\nRestore complete!")
    print(f"  - Quotes restored: {quotes_restored}")
    print(f"  - Tags restored: {tags_restored}")
    print(f"  - System ready for testing!")
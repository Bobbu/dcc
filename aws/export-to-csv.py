#!/usr/bin/env python3
"""
Export DynamoDB quotes to CSV format matching Google Sheets structure
"""

import boto3
import csv
from datetime import datetime

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

def export_quotes_to_csv():
    """Export quotes from DynamoDB to CSV with Quote, Author, and up to 20 tags"""
    
    table_name = 'dcc-quotes-optimized'
    table = dynamodb.Table(table_name)
    
    print(f"Exporting quotes from {table_name}...")
    
    # Scan the entire table
    response = table.scan()
    items = response['Items']
    
    while 'LastEvaluatedKey' in response:
        response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
        items.extend(response['Items'])
    
    print(f"Found {len(items)} quotes to export")
    
    # Create CSV file with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_filename = f"quotes_export_{timestamp}.csv"
    
    # Write to CSV
    with open(csv_filename, 'w', newline='', encoding='utf-8') as csvfile:
        # Create header with Quote, Author, and Tag1-Tag20
        fieldnames = ['Quote', 'Author'] + [f'Tag{i}' for i in range(1, 21)]
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        # Write header
        writer.writeheader()
        
        # Write each quote
        quotes_written = 0
        for item in items:
            # Skip any non-quote items (like job records)
            if 'quote' not in item or 'author' not in item:
                continue
                
            row = {
                'Quote': item.get('quote', ''),
                'Author': item.get('author', '')
            }
            
            # Add tags (up to 20)
            tags = item.get('tags', [])
            for i, tag in enumerate(tags[:20], 1):  # Limit to first 20 tags
                row[f'Tag{i}'] = tag
            
            # Fill remaining tag columns with empty strings
            for i in range(len(tags) + 1, 21):
                row[f'Tag{i}'] = ''
            
            writer.writerow(row)
            quotes_written += 1
    
    print(f"✓ Exported {quotes_written} quotes to {csv_filename}")
    
    # Show some statistics
    max_tags = max(len(item.get('tags', [])) for item in items if 'quote' in item)
    quotes_with_tags = sum(1 for item in items if 'quote' in item and item.get('tags'))
    
    print(f"\nStatistics:")
    print(f"  - Total quotes: {quotes_written}")
    print(f"  - Quotes with tags: {quotes_with_tags}")
    print(f"  - Maximum tags on a single quote: {max_tags}")
    
    return csv_filename

if __name__ == "__main__":
    export_quotes_to_csv()
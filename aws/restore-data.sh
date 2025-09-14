#!/bin/bash

# Restore data to Quote Me tables from CSV backup

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== DATA RESTORATION ===${NC}"
echo ""

# Find the most recent CSV backup
CSV_FILE=$(ls -t quotes_export_*.csv 2>/dev/null | head -1)

if [ -z "$CSV_FILE" ]; then
    echo -e "${RED}Error: No CSV backup found${NC}"
    echo "Please run export-to-csv.py first to create a backup"
    exit 1
fi

echo "Found backup: $CSV_FILE"

# Create Python restore script
cat > restore-quote-me-data.py << 'EOF'
#!/usr/bin/env python3
"""
Restore quotes from CSV backup to Quote Me tables
"""

import boto3
import csv
import uuid
import sys
from datetime import datetime

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

def restore_quotes_from_csv(csv_filename):
    """Restore quotes from CSV to Quote Me DynamoDB tables"""
    
    quotes_table_name = 'quote-me-quotes'
    tags_table_name = 'quote-me-tags'
    
    quotes_table = dynamodb.Table(quotes_table_name)
    tags_table = dynamodb.Table(tags_table_name)
    
    print(f"Restoring from: {csv_filename}")
    print(f"Target tables: {quotes_table_name}, {tags_table_name}")
    print("")
    
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
                
                if quotes_restored % 100 == 0:
                    print(f"  Processed {quotes_restored} quotes...")
    
    print(f"✓ Restored {quotes_restored} quotes")
    
    # Restore tags table
    print(f"Restoring {len(all_tags)} unique tags...")
    
    with tags_table.batch_writer() as batch:
        for tag in all_tags:
            batch.put_item(Item={'tag': tag})
    
    print(f"✓ Restored {len(all_tags)} tags")
    
    return quotes_restored, len(all_tags)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 restore-quote-me-data.py <csv_file>")
        sys.exit(1)
    
    csv_file = sys.argv[1]
    quotes_restored, tags_restored = restore_quotes_from_csv(csv_file)
    
    print("")
    print("Restore complete!")
    print(f"  Quotes: {quotes_restored}")
    print(f"  Tags: {tags_restored}")
EOF

chmod +x restore-quote-me-data.py

# Run the restore
echo -e "${YELLOW}Restoring data...${NC}"
python3 restore-quote-me-data.py "$CSV_FILE"

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ Data restoration successful!${NC}"
    
    # Test the restored data
    STACK_NAME="quote-me-api"
    API_URL=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiUrl`].OutputValue' \
        --output text 2>/dev/null)
    
    API_KEY_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ApiKeyId`].OutputValue' \
        --output text 2>/dev/null)
    
    if [ -n "$API_KEY_ID" ] && [ "$API_KEY_ID" != "None" ]; then
        API_KEY_VALUE=$(aws apigateway get-api-key --api-key $API_KEY_ID --include-value --query value --output text)
        
        echo ""
        echo -e "${YELLOW}Testing restored data...${NC}"
        RESPONSE=$(curl -s "$API_URL/quote" -H "x-api-key: $API_KEY_VALUE")
        
        if [ $? -eq 0 ]; then
            QUOTE=$(echo "$RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('quote', 'Error')[:60])")
            echo -e "${GREEN}✓ API working with restored data${NC}"
            echo "Sample quote: \"$QUOTE...\""
        fi
    fi
else
    echo -e "${RED}Data restoration failed!${NC}"
    exit 1
fi
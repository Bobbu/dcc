#!/usr/bin/env python3
"""
Backup DynamoDB tables to local JSON files
"""

import boto3
import json
import os
from datetime import datetime
from decimal import Decimal

class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return float(obj)
        return super(DecimalEncoder, self).default(obj)

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

def backup_table(table_name, backup_dir):
    """Backup a DynamoDB table to a JSON file"""
    try:
        table = dynamodb.Table(table_name)
        
        print(f"Backing up {table_name}...")
        
        # Scan the entire table
        response = table.scan()
        items = response['Items']
        
        while 'LastEvaluatedKey' in response:
            response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response['Items'])
        
        # Save to file
        backup_file = os.path.join(backup_dir, f"{table_name}_backup.json")
        with open(backup_file, 'w') as f:
            json.dump(items, f, cls=DecimalEncoder, indent=2)
        
        print(f"  ✓ Backed up {len(items)} items to {backup_file}")
        return len(items)
        
    except Exception as e:
        if "ResourceNotFoundException" in str(e):
            print(f"  ✗ Table {table_name} not found")
            return 0
        else:
            print(f"  ✗ Error backing up {table_name}: {e}")
            return -1

def main():
    # Create backup directory with timestamp
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = f"dynamodb_backup_{timestamp}"
    os.makedirs(backup_dir, exist_ok=True)
    
    print(f"Creating backups in {backup_dir}/")
    print("=" * 50)
    
    # Tables to backup
    tables = [
        'dcc-quotes-optimized',
        'dcc-tags',
        'quote-me-quotes',
        'quote-me-tags'
    ]
    
    total_items = 0
    backed_up_tables = []
    
    for table_name in tables:
        count = backup_table(table_name, backup_dir)
        if count > 0:
            total_items += count
            backed_up_tables.append(table_name)
    
    print("=" * 50)
    print(f"Backup complete!")
    print(f"Total items backed up: {total_items}")
    print(f"Tables backed up: {', '.join(backed_up_tables)}")
    print(f"Backup location: {backup_dir}/")
    
    # Create restore script
    restore_script = os.path.join(backup_dir, "restore.py")
    with open(restore_script, 'w') as f:
        f.write('''#!/usr/bin/env python3
"""
Restore DynamoDB tables from backup
"""

import boto3
import json
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb', region_name='us-east-1')

def restore_table(table_name, backup_file):
    """Restore a DynamoDB table from a JSON file"""
    if not os.path.exists(backup_file):
        print(f"  ✗ Backup file {backup_file} not found")
        return 0
    
    try:
        table = dynamodb.Table(table_name)
        
        print(f"Restoring {table_name} from {backup_file}...")
        
        with open(backup_file, 'r') as f:
            items = json.load(f, parse_float=Decimal)
        
        # Write items in batches
        with table.batch_writer() as batch:
            for item in items:
                batch.put_item(Item=item)
        
        print(f"  ✓ Restored {len(items)} items to {table_name}")
        return len(items)
        
    except Exception as e:
        print(f"  ✗ Error restoring {table_name}: {e}")
        return -1

# Restore all backed up tables
for file in os.listdir('.'):
    if file.endswith('_backup.json'):
        table_name = file.replace('_backup.json', '')
        restore_table(table_name, file)
''')
    
    os.chmod(restore_script, 0o755)
    print(f"Restore script created: {restore_script}")

if __name__ == "__main__":
    main()
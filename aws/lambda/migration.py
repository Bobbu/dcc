import json
import boto3
import logging
import os
from decimal import Decimal
from datetime import datetime, timezone
import uuid
from collections import defaultdict

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
old_table_name = os.environ['OLD_TABLE_NAME']
new_table_name = os.environ['NEW_TABLE_NAME']

old_table = dynamodb.Table(old_table_name)
new_table = dynamodb.Table(new_table_name)

def lambda_handler(event, context):
    """Main migration handler - can be invoked manually or via API"""
    try:
        logger.info("Starting DynamoDB migration...")
        
        # Get migration parameters from event
        dry_run = event.get('dry_run', False)
        batch_size = event.get('batch_size', 25)  # DynamoDB batch_write_item limit
        start_key = event.get('start_key')  # For resuming interrupted migrations
        
        # Validate parameters
        batch_size = min(batch_size, 25)  # Enforce DynamoDB limits
        
        if dry_run:
            logger.info("DRY RUN MODE - No data will be written")
        
        # Perform migration
        migration_stats = migrate_data(dry_run, batch_size, start_key)
        
        logger.info("Migration completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Migration completed successfully' + (' (DRY RUN)' if dry_run else ''),
                'stats': migration_stats
            }, cls=DecimalEncoder)
        }
        
    except Exception as e:
        logger.error(f"Migration failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': f'Migration failed: {str(e)}'})
        }

def migrate_data(dry_run=False, batch_size=25, start_key=None):
    """Migrate all data from old table to new optimized structure"""
    stats = {
        'quotes_processed': 0,
        'quotes_migrated': 0,
        'tags_created': 0,
        'tag_mappings_created': 0,
        'authors_created': 0,
        'errors': []
    }
    
    try:
        # Step 1: Scan old table and collect all data
        logger.info("Scanning old table for quotes...")
        quotes = scan_old_table(start_key)
        logger.info(f"Found {len(quotes)} quotes to migrate")
        
        if not quotes:
            return stats
        
        # Step 2: Analyze data and prepare for migration
        tag_stats = defaultdict(int)
        author_stats = defaultdict(lambda: {'count': 0, 'tags': set(), 'dates': []})
        
        # Filter out metadata records and only process actual quotes
        actual_quotes = []
        for quote in quotes:
            stats['quotes_processed'] += 1
            
            # Skip metadata records like TAGS_METADATA
            quote_id = quote.get('id', '')
            if quote_id.startswith('TAGS_') or not quote.get('quote'):
                logger.info(f"Skipping metadata record: {quote_id}")
                continue
                
            actual_quotes.append(quote)
            
            # Collect tag statistics
            for tag in quote.get('tags', []):
                if tag:
                    tag_stats[tag] += 1
            
            # Collect author statistics
            author = quote.get('author', '')
            if author:
                author_stats[author]['count'] += 1
                author_stats[author]['tags'].update(quote.get('tags', []))
                if quote.get('created_at'):
                    author_stats[author]['dates'].append(quote['created_at'])
        
        # Update quotes list to only include actual quotes
        quotes = actual_quotes
        
        logger.info(f"Found {len(tag_stats)} unique tags and {len(author_stats)} unique authors")
        
        if dry_run:
            stats['quotes_migrated'] = len(quotes)
            stats['tags_created'] = len(tag_stats)
            stats['authors_created'] = len(author_stats)
            stats['tag_mappings_created'] = sum(len(quote.get('tags', [])) for quote in quotes)
            return stats
        
        # Step 3: Migrate data in batches
        batch_items = []
        
        # Process quotes in batches
        for i, quote in enumerate(quotes):
            try:
                # Prepare quote items for new table
                quote_items = prepare_quote_for_migration(quote)
                batch_items.extend(quote_items)
                
                # Write batch when it's full or at the end
                if len(batch_items) >= batch_size or i == len(quotes) - 1:
                    write_batch(batch_items, stats)
                    batch_items = []
                    
            except Exception as e:
                error_msg = f"Error processing quote {quote.get('id', 'unknown')}: {str(e)}"
                logger.error(error_msg)
                stats['errors'].append(error_msg)
        
        # Step 4: Create tag metadata
        logger.info("Creating tag metadata...")
        create_tag_metadata(tag_stats, stats, dry_run)
        
        # Step 5: Create author aggregations
        logger.info("Creating author aggregations...")
        create_author_aggregations(author_stats, stats, dry_run)
        
        logger.info(f"Migration completed. Stats: {stats}")
        return stats
        
    except Exception as e:
        error_msg = f"Migration error: {str(e)}"
        logger.error(error_msg)
        stats['errors'].append(error_msg)
        raise

def scan_old_table(start_key=None):
    """Scan the old table to get all quotes"""
    quotes = []
    
    try:
        scan_params = {
            'Select': 'ALL_ATTRIBUTES'
        }
        
        if start_key:
            scan_params['ExclusiveStartKey'] = start_key
        
        response = old_table.scan(**scan_params)
        quotes.extend(response['Items'])
        
        # Handle pagination
        while 'LastEvaluatedKey' in response:
            scan_params['ExclusiveStartKey'] = response['LastEvaluatedKey']
            response = old_table.scan(**scan_params)
            quotes.extend(response['Items'])
            logger.info(f"Scanned {len(quotes)} quotes so far...")
        
        return quotes
        
    except Exception as e:
        logger.error(f"Error scanning old table: {str(e)}")
        raise

def prepare_quote_for_migration(old_quote):
    """Convert old quote format to new optimized format"""
    items = []
    
    try:
        # Generate quote ID if not present
        quote_id = old_quote.get('id', str(uuid.uuid4()))
        
        # Use existing timestamps or create new ones
        now = datetime.now(timezone.utc).isoformat()
        created_at = old_quote.get('created_at', now)
        updated_at = old_quote.get('updated_at', now)
        
        # Handle empty authors (DynamoDB GSI doesn't allow empty strings)
        author = old_quote.get('author', '').strip()
        if not author:
            author = 'Unknown'
        
        # Prepare main quote item
        quote_item = {
            'PK': f'QUOTE#{quote_id}',
            'SK': f'QUOTE#{quote_id}',
            'type': 'quote',
            'id': quote_id,
            'quote': old_quote.get('quote', ''),
            'author': author,
            'author_normalized': author.lower(),
            'quote_normalized': old_quote.get('quote', '')[:100].lower(),  # First 100 chars for search
            'tags': old_quote.get('tags', []),
            'created_at': created_at,
            'updated_at': updated_at,
            'created_by': old_quote.get('created_by', 'migration')
        }
        
        items.append(quote_item)
        
        # Prepare tag-quote mapping items
        for tag in old_quote.get('tags', []):
            if tag:  # Skip empty tags
                tag_mapping_item = {
                    'PK': f'TAG#{tag}',
                    'SK': f'QUOTE#{quote_id}',
                    'type': 'tag_quote_mapping',
                    'quote_id': quote_id,
                    'author': author,
                    'created_at': created_at
                }
                items.append(tag_mapping_item)
        
        return items
        
    except Exception as e:
        logger.error(f"Error preparing quote for migration: {str(e)}")
        raise

def write_batch(items, stats):
    """Write a batch of items to the new table"""
    try:
        if not items:
            return
        
        # Split into batches of 25 (DynamoDB limit)
        batch_size = 25
        for i in range(0, len(items), batch_size):
            batch = items[i:i + batch_size]
            
            request_items = {
                new_table.name: [
                    {'PutRequest': {'Item': item}}
                    for item in batch
                ]
            }
            
            # Execute batch write
            response = dynamodb.meta.client.batch_write_item(RequestItems=request_items)
            
            # Handle unprocessed items
            unprocessed = response.get('UnprocessedItems', {})
            retry_count = 0
            max_retries = 3
            
            while unprocessed and retry_count < max_retries:
                logger.warning(f"Retrying {len(unprocessed)} unprocessed items...")
                retry_count += 1
                
                response = dynamodb.meta.client.batch_write_item(RequestItems=unprocessed)
                unprocessed = response.get('UnprocessedItems', {})
            
            if unprocessed:
                error_msg = f"Failed to process {len(unprocessed)} items after {max_retries} retries"
                logger.error(error_msg)
                stats['errors'].append(error_msg)
            
            # Update stats
            quotes_in_batch = sum(1 for item in batch if item.get('type') == 'quote')
            mappings_in_batch = sum(1 for item in batch if item.get('type') == 'tag_quote_mapping')
            
            stats['quotes_migrated'] += quotes_in_batch
            stats['tag_mappings_created'] += mappings_in_batch
            
        logger.info(f"Wrote batch of {len(items)} items")
        
    except Exception as e:
        logger.error(f"Error writing batch: {str(e)}")
        raise

def create_tag_metadata(tag_stats, stats, dry_run=False):
    """Create tag metadata records"""
    try:
        if dry_run:
            stats['tags_created'] = len(tag_stats)
            return
        
        now = datetime.now(timezone.utc).isoformat()
        batch_items = []
        
        for tag_name, count in tag_stats.items():
            if tag_name:  # Skip empty tags
                tag_item = {
                    'PK': f'TAG#{tag_name}',
                    'SK': f'TAG#{tag_name}',
                    'type': 'tag',
                    'name': tag_name,
                    'name_normalized': tag_name.lower(),
                    'created_at': now,
                    'updated_at': now,
                    'created_by': 'migration',
                    'quote_count': count,
                    'last_used': now
                }
                batch_items.append(tag_item)
        
        # Write tags in batches
        if batch_items:
            temp_stats = {'quotes_migrated': 0, 'tag_mappings_created': 0, 'errors': stats['errors']}
            write_batch(batch_items, temp_stats)
            stats['tags_created'] = len(batch_items)
        
    except Exception as e:
        logger.error(f"Error creating tag metadata: {str(e)}")
        raise

def create_author_aggregations(author_stats, stats, dry_run=False):
    """Create author aggregation records"""
    try:
        if dry_run:
            stats['authors_created'] = len(author_stats)
            return
        
        now = datetime.now(timezone.utc).isoformat()
        batch_items = []
        
        for author_name, data in author_stats.items():
            if author_name:  # Skip empty authors
                dates = data['dates']
                first_date = min(dates) if dates else now
                last_date = max(dates) if dates else now
                
                author_item = {
                    'PK': f'AUTHOR#{author_name}',
                    'SK': f'AUTHOR#{author_name}',
                    'type': 'author',
                    'name': author_name,
                    'name_normalized': author_name.lower(),
                    'created_at': now,
                    'updated_at': now,
                    'quote_count': data['count'],
                    'tags_used': list(data['tags']),
                    'first_quote_date': first_date,
                    'last_quote_date': last_date
                }
                batch_items.append(author_item)
        
        # Write authors in batches
        if batch_items:
            temp_stats = {'quotes_migrated': 0, 'tag_mappings_created': 0, 'errors': stats['errors']}
            write_batch(batch_items, temp_stats)
            stats['authors_created'] = len(batch_items)
        
    except Exception as e:
        logger.error(f"Error creating author aggregations: {str(e)}")
        raise

class DecimalEncoder(json.JSONEncoder):
    """Helper class to convert DynamoDB Decimal types to int/float"""
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super(DecimalEncoder, self).default(obj)
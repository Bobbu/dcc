import json
import boto3
from boto3.dynamodb.conditions import Key
import logging
import os
from decimal import Decimal
from datetime import datetime, timezone

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
table_name = os.environ['TABLE_NAME']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    """Process DynamoDB Stream events to maintain aggregations"""
    try:
        logger.info(f"Processing {len(event['Records'])} stream records")
        
        for record in event['Records']:
            try:
                process_stream_record(record)
            except Exception as e:
                logger.error(f"Error processing individual record: {str(e)}")
                # Continue processing other records
                
        return {'statusCode': 200, 'body': 'Successfully processed stream records'}
        
    except Exception as e:
        logger.error(f"Error in stream processor: {str(e)}")
        return {'statusCode': 500, 'body': f'Error processing stream: {str(e)}'}

def process_stream_record(record):
    """Process a single stream record"""
    event_name = record['eventName']
    
    if event_name == 'INSERT':
        process_insert_event(record)
    elif event_name == 'MODIFY':
        process_modify_event(record)
    elif event_name == 'REMOVE':
        process_remove_event(record)

def process_insert_event(record):
    """Process INSERT events"""
    try:
        new_image = record['dynamodb']['NewImage']
        item_type = new_image.get('type', {}).get('S')
        
        if item_type == 'quote':
            # Update tag counts and author aggregations for new quote
            quote_data = parse_dynamodb_item(new_image)
            update_aggregations_for_quote_insert(quote_data)
            
        elif item_type == 'tag_quote_mapping':
            # Update tag usage statistics
            tag_name = extract_tag_from_pk(new_image.get('PK', {}).get('S', ''))
            if tag_name:
                update_tag_count(tag_name, increment=1)
                mapping_data = parse_dynamodb_item(new_image)
                update_tag_last_used(tag_name, mapping_data.get('created_at'))
                
    except Exception as e:
        logger.error(f"Error processing INSERT event: {str(e)}")

def process_modify_event(record):
    """Process MODIFY events"""
    try:
        old_image = record['dynamodb'].get('OldImage', {})
        new_image = record['dynamodb']['NewImage']
        item_type = new_image.get('type', {}).get('S')
        
        if item_type == 'quote':
            # Handle quote updates (tag changes, author changes)
            old_quote = parse_dynamodb_item(old_image) if old_image else {}
            new_quote = parse_dynamodb_item(new_image)
            handle_quote_update(old_quote, new_quote)
            
    except Exception as e:
        logger.error(f"Error processing MODIFY event: {str(e)}")

def process_remove_event(record):
    """Process REMOVE events"""
    try:
        old_image = record['dynamodb']['OldImage']
        item_type = old_image.get('type', {}).get('S')
        
        if item_type == 'quote':
            # Update aggregations for removed quote
            quote_data = parse_dynamodb_item(old_image)
            update_aggregations_for_quote_remove(quote_data)
            
        elif item_type == 'tag_quote_mapping':
            # Decrement tag count
            tag_name = extract_tag_from_pk(old_image.get('PK', {}).get('S', ''))
            if tag_name:
                update_tag_count(tag_name, increment=-1)
                
    except Exception as e:
        logger.error(f"Error processing REMOVE event: {str(e)}")

def update_aggregations_for_quote_insert(quote_data):
    """Update all aggregations when a quote is inserted"""
    try:
        author = quote_data.get('author')
        tags = quote_data.get('tags', [])
        created_at = quote_data.get('created_at')
        
        # Update author aggregation
        if author:
            update_author_stats(author, tags, created_at, increment=1)
        
        # Update tag counts (handled by tag_quote_mapping inserts)
        
    except Exception as e:
        logger.error(f"Error updating aggregations for quote insert: {str(e)}")

def update_aggregations_for_quote_remove(quote_data):
    """Update all aggregations when a quote is removed"""
    try:
        author = quote_data.get('author')
        tags = quote_data.get('tags', [])
        
        # Update author aggregation
        if author:
            update_author_stats(author, tags, None, increment=-1)
            
    except Exception as e:
        logger.error(f"Error updating aggregations for quote remove: {str(e)}")

def handle_quote_update(old_quote, new_quote):
    """Handle quote updates by comparing old and new versions"""
    try:
        old_author = old_quote.get('author')
        new_author = new_quote.get('author')
        old_tags = set(old_quote.get('tags', []))
        new_tags = set(new_quote.get('tags', []))
        
        # Handle author change
        if old_author != new_author:
            if old_author:
                update_author_stats(old_author, list(old_tags), None, increment=-1)
            if new_author:
                update_author_stats(new_author, list(new_tags), new_quote.get('updated_at'), increment=1)
        
        # Handle tag changes (tag mappings will trigger their own events)
        
    except Exception as e:
        logger.error(f"Error handling quote update: {str(e)}")

def update_tag_count(tag_name, increment=1):
    """Update the quote count for a tag"""
    try:
        now = datetime.now(timezone.utc).isoformat()
        
        response = table.update_item(
            Key={
                'PK': f'TAG#{tag_name}',
                'SK': f'TAG#{tag_name}'
            },
            UpdateExpression='SET quote_count = if_not_exists(quote_count, :zero) + :inc, updated_at = :now',
            ExpressionAttributeValues={
                ':inc': increment,
                ':zero': 0,
                ':now': now
            },
            ReturnValues='ALL_NEW'
        )
        
        logger.info(f"Updated tag {tag_name} count by {increment}")
        
    except Exception as e:
        logger.error(f"Error updating tag count for {tag_name}: {str(e)}")

def update_tag_last_used(tag_name, timestamp):
    """Update the last used timestamp for a tag"""
    try:
        if not timestamp:
            timestamp = datetime.now(timezone.utc).isoformat()
            
        table.update_item(
            Key={
                'PK': f'TAG#{tag_name}',
                'SK': f'TAG#{tag_name}'
            },
            UpdateExpression='SET last_used = :timestamp, updated_at = :now',
            ExpressionAttributeValues={
                ':timestamp': timestamp,
                ':now': datetime.now(timezone.utc).isoformat()
            }
        )
        
    except Exception as e:
        logger.error(f"Error updating tag last used for {tag_name}: {str(e)}")

def update_author_stats(author_name, tags, timestamp, increment=1):
    """Update author statistics and aggregations"""
    try:
        now = datetime.now(timezone.utc).isoformat()
        author_normalized = author_name.lower()
        
        if increment > 0:
            # Adding quotes
            update_expression = '''SET 
                quote_count = if_not_exists(quote_count, :zero) + :inc,
                tags_used = list_append(if_not_exists(tags_used, :empty_list), :tags),
                last_quote_date = :timestamp,
                updated_at = :now'''
            
            if not timestamp:
                timestamp = now
                
            expression_values = {
                ':inc': increment,
                ':zero': 0,
                ':empty_list': [],
                ':tags': tags,
                ':timestamp': timestamp,
                ':now': now
            }
            
            # Also set first_quote_date if this is the first quote
            update_expression += ', first_quote_date = if_not_exists(first_quote_date, :timestamp)'
            
        else:
            # Removing quotes
            update_expression = '''SET 
                quote_count = if_not_exists(quote_count, :zero) + :inc,
                updated_at = :now'''
            
            expression_values = {
                ':inc': increment,
                ':zero': 0,
                ':now': now
            }
        
        # Upsert author record
        table.update_item(
            Key={
                'PK': f'AUTHOR#{author_name}',
                'SK': f'AUTHOR#{author_name}'
            },
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_values
        )
        
        # Also create/update the type record for queries
        table.put_item(
            Item={
                'PK': f'AUTHOR#{author_name}',
                'SK': f'AUTHOR#{author_name}',
                'type': 'author',
                'name': author_name,
                'name_normalized': author_normalized,
                'updated_at': now
            },
            ConditionExpression='attribute_not_exists(PK) OR #type = :author_type',
            ExpressionAttributeNames={'#type': 'type'},
            ExpressionAttributeValues={':author_type': 'author'}
        )
        
        logger.info(f"Updated author stats for {author_name}")
        
    except Exception as e:
        logger.error(f"Error updating author stats for {author_name}: {str(e)}")

def parse_dynamodb_item(dynamodb_item):
    """Parse DynamoDB item from stream format to Python dict"""
    try:
        item = {}
        for key, value in dynamodb_item.items():
            if 'S' in value:
                item[key] = value['S']
            elif 'N' in value:
                item[key] = Decimal(value['N'])
            elif 'SS' in value:
                item[key] = value['SS']
            elif 'NS' in value:
                item[key] = [Decimal(n) for n in value['NS']]
            elif 'BOOL' in value:
                item[key] = value['BOOL']
            elif 'NULL' in value:
                item[key] = None
            # Add more type handling as needed
        
        return item
        
    except Exception as e:
        logger.error(f"Error parsing DynamoDB item: {str(e)}")
        return {}

def extract_tag_from_pk(pk):
    """Extract tag name from TAG#tagname format"""
    try:
        if pk and pk.startswith('TAG#'):
            return pk[4:]  # Remove 'TAG#' prefix
        return None
    except:
        return None

def extract_author_from_pk(pk):
    """Extract author name from AUTHOR#authorname format"""
    try:
        if pk and pk.startswith('AUTHOR#'):
            return pk[7:]  # Remove 'AUTHOR#' prefix
        return None
    except:
        return None
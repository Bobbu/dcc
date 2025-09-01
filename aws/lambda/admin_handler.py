import json
import boto3
import os
import uuid
import re
from datetime import datetime
from boto3.dynamodb.conditions import Key, Attr

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ.get('QUOTES_TABLE_NAME', 'dcc-quotes-optimized'))

def normalize_text(text):
    """Normalizes text for softer comparison by removing extra whitespace,
    punctuation variations, and common differences"""
    if not text:
        return ""
    
    text = (text.strip()
            .lower()
            # Remove extra whitespace
            .replace('\n', ' ')
            .replace('\t', ' ')
            # Normalize punctuation
            .replace('"', '"').replace('"', '"')  # Smart quotes
            .replace(''', "'").replace(''', "'")  # Smart apostrophes  
            .replace('—', '-').replace('–', '-')  # Em/en dashes
            .replace('…', '...')  # Ellipsis
            # Remove trailing periods from authors
            .rstrip('.'))
    # Clean up multiple spaces
    text = re.sub(r'\s+', ' ', text)
    return text

def calculate_similarity(text1, text2):
    """Calculates similarity ratio between two strings using a simple
    character-based approach suitable for quotes and author names"""
    if not text1 and not text2:
        return 1.0
    if not text1 or not text2:
        return 0.0
    
    # For very similar lengths, use character-by-character comparison
    if abs(len(text1) - len(text2)) <= 3:
        matches = 0
        max_length = max(len(text1), len(text2))
        
        for i in range(max_length):
            if i < len(text1) and i < len(text2) and text1[i] == text2[i]:
                matches += 1
        return matches / max_length if max_length > 0 else 0.0
    
    # For different lengths, use word-based comparison
    words1 = text1.split(' ')
    words2 = text2.split(' ')
    
    common_words = 0
    for word1 in words1:
        if word1 in words2 and len(word1) > 2:
            common_words += 1
    
    total_words = len(words1) + len(words2)
    return (2.0 * common_words) / total_words if total_words > 0 else 0.0

def are_similar_quotes(quote1_text, quote1_author, quote2_text, quote2_author):
    """Checks if two quotes are similar enough to be considered duplicates"""
    normalized_quote1 = normalize_text(quote1_text)
    normalized_quote2 = normalize_text(quote2_text)
    normalized_author1 = normalize_text(quote1_author)
    normalized_author2 = normalize_text(quote2_author)
    
    # Exact match after normalization
    if normalized_quote1 == normalized_quote2 and normalized_author1 == normalized_author2:
        return True, "exact_match"
    
    # Similar quote text with exact author match
    quote_similarity = calculate_similarity(normalized_quote1, normalized_quote2)
    if quote_similarity >= 0.90 and normalized_author1 == normalized_author2:
        return True, f"similar_quote_same_author_{quote_similarity:.2f}"
    
    # Exact quote with similar author (handles attribution variations)
    author_similarity = calculate_similarity(normalized_author1, normalized_author2)
    if normalized_quote1 == normalized_quote2 and author_similarity >= 0.85:
        return True, f"same_quote_similar_author_{author_similarity:.2f}"
    
    # Both quote and author are very similar (for cases with minor differences)
    if quote_similarity >= 0.95 and author_similarity >= 0.90:
        return True, f"both_similar_q{quote_similarity:.2f}_a{author_similarity:.2f}"
    
    return False, None

def get_user_claims(event):
    """Extract user claims from Cognito JWT token"""
    claims = event.get('requestContext', {}).get('authorizer', {}).get('claims', {})
    
    # Check if user is in admin group
    groups = claims.get('cognito:groups', '')
    is_admin = 'Admins' in groups if groups else False
    
    return {
        'username': claims.get('cognito:username', 'unknown'),
        'email': claims.get('email', ''),
        'is_admin': is_admin,
        'groups': groups
    }

def create_response(status_code, body, headers=None):
    """Create standardized API response"""
    default_headers = {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token",
        "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS"
    }
    
    if headers:
        default_headers.update(headers)
    
    return {
        "statusCode": status_code,
        "headers": default_headers,
        "body": json.dumps(body) if isinstance(body, (dict, list)) else body
    }

def update_tags_metadata(new_tags):
    """Update the tags metadata record with new tags"""
    try:
        metadata_id = "TAGS_METADATA"
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        # Get current tags metadata
        try:
            response = table.get_item(Key={'id': metadata_id})
            current_tags = set(response.get('Item', {}).get('tags', []))
        except:
            current_tags = set()
        
        # Merge in new tags
        if new_tags:
            current_tags.update(new_tags)
        
        # Update metadata record
        table.put_item(Item={
            'id': metadata_id,
            'tags': sorted(list(current_tags)),  # Keep sorted for consistency
            'updated_at': timestamp
        })
        
        print(f"✅ Updated tags metadata: {sorted(list(current_tags))}")
        
    except Exception as e:
        print(f"❌ Error updating tags metadata: {e}")
        # Don't fail the main operation if metadata update fails

def get_tags_metadata():
    """Get all available tags from metadata record"""
    try:
        response = table.get_item(Key={'id': 'TAGS_METADATA'})
        if 'Item' in response:
            return response['Item']['tags']
        return []
    except Exception as e:
        print(f"Error getting tags metadata: {e}")
        return []

def validate_quote_data(data):
    """Validate quote data structure"""
    required_fields = ['quote', 'author']
    optional_fields = ['tags']
    
    errors = []
    
    # Check required fields
    for field in required_fields:
        if field not in data or not data[field] or not data[field].strip():
            errors.append(f"'{field}' is required and cannot be empty")
    
    # Validate tags if provided
    if 'tags' in data:
        if not isinstance(data['tags'], list):
            errors.append("'tags' must be an array")
        elif not all(isinstance(tag, str) and tag.strip() for tag in data['tags']):
            errors.append("All tags must be non-empty strings")
    
    return errors

def handle_create_quote(event, user_claims):
    """Handle POST /admin/quotes"""
    print("🔥 handle_create_quote called!")
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate input
        validation_errors = validate_quote_data(body)
        if validation_errors:
            return create_response(400, {
                "error": "Validation failed",
                "details": validation_errors
            })
        
        # Check for duplicates
        quote_text = body['quote'].strip()
        author = body['author'].strip()
        
        print(f"🔍 Checking for duplicates: '{quote_text}' by '{author}'")
        
        try:
            # Scan for potential duplicates using fuzzy matching
            duplicates_found = []
            scan_kwargs = {'ProjectionExpression': 'id, quote, author, created_at'}
            
            while True:
                response = table.scan(**scan_kwargs)
                
                for item in response.get('Items', []):
                    # Skip non-quote items (like metadata)
                    if 'quote' not in item or 'author' not in item:
                        continue
                        
                    if are_similar_quotes(quote_text, author, item['quote'], item['author']):
                        duplicates_found.append({
                            'id': item['id'],
                            'quote': item['quote'],
                            'author': item['author'],
                            'created_at': item.get('created_at', ''),
                            'match_reason': 'Similar quote and author'
                        })
                
                if 'LastEvaluatedKey' not in response:
                    break
                scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']
            
            print(f"🔍 Found {len(duplicates_found)} potential duplicates")
            if duplicates_found:
                print(f"❌ BLOCKING duplicate creation - found {len(duplicates_found)} matches")
                return create_response(409, {
                    "error": "Duplicate quote detected",
                    "message": f"Found {len(duplicates_found)} similar quote(s)",
                    "is_duplicate": True,
                    "duplicate_count": len(duplicates_found),
                    "duplicates": duplicates_found[:5]  # Return first 5 matches
                })
            else:
                print("✅ No duplicates found, proceeding with creation")
                
        except Exception as e:
            print(f"Error checking for duplicates: {e}")
            # Continue with quote creation if duplicate check fails
            # This ensures the system is resilient to duplicate check failures
        
        # Create new quote
        quote_id = str(uuid.uuid4())
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        quote_item = {
            'id': quote_id,
            'quote': body['quote'].strip(),
            'author': body['author'].strip(),
            'tags': body.get('tags', []),
            'created_at': timestamp,
            'updated_at': timestamp,
            'created_by': user_claims['username']
        }
        
        # Save to DynamoDB
        table.put_item(Item=quote_item)
        
        # Update tags metadata
        update_tags_metadata(quote_item['tags'])
        
        return create_response(201, {
            "message": "Quote created successfully",
            "quote": quote_item
        })
        
    except json.JSONDecodeError:
        return create_response(400, {"error": "Invalid JSON in request body"})
    except Exception as e:
        print(f"Error creating quote: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_update_quote(event, user_claims):
    """Handle PUT /admin/quotes/{id}"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get quote ID from path
        quote_id = event.get('pathParameters', {}).get('id')
        if not quote_id:
            return create_response(400, {"error": "Quote ID is required"})
        
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        
        # Validate input
        validation_errors = validate_quote_data(body)
        if validation_errors:
            return create_response(400, {
                "error": "Validation failed",
                "details": validation_errors
            })
        
        # Check if quote exists
        try:
            response = table.get_item(Key={'id': quote_id})
            if 'Item' not in response:
                return create_response(404, {"error": "Quote not found"})
        except Exception as e:
            print(f"Error checking quote existence: {e}")
            return create_response(500, {"error": "Internal server error"})
        
        # Update quote
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        updated_item = {
            'id': quote_id,
            'quote': body['quote'].strip(),
            'author': body['author'].strip(),
            'tags': body.get('tags', []),
            'updated_at': timestamp,
            'updated_by': user_claims['username']
        }
        
        # Preserve creation metadata
        existing_quote = response['Item']
        updated_item['created_at'] = existing_quote.get('created_at', timestamp)
        updated_item['created_by'] = existing_quote.get('created_by', 'unknown')
        
        # Save updated item
        table.put_item(Item=updated_item)
        
        # Update tags metadata
        update_tags_metadata(updated_item['tags'])
        
        return create_response(200, {
            "message": "Quote updated successfully",
            "quote": updated_item
        })
        
    except json.JSONDecodeError:
        return create_response(400, {"error": "Invalid JSON in request body"})
    except Exception as e:
        print(f"Error updating quote: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_delete_quote(event, user_claims):
    """Handle DELETE /admin/quotes/{id}"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get quote ID from path
        quote_id = event.get('pathParameters', {}).get('id')
        if not quote_id:
            return create_response(400, {"error": "Quote ID is required"})
        
        # Check if quote exists
        try:
            response = table.get_item(Key={'id': quote_id})
            if 'Item' not in response:
                return create_response(404, {"error": "Quote not found"})
        except Exception as e:
            print(f"Error checking quote existence: {e}")
            return create_response(500, {"error": "Internal server error"})
        
        # Delete quote
        table.delete_item(Key={'id': quote_id})
        
        return create_response(200, {
            "message": "Quote deleted successfully",
            "deleted_quote_id": quote_id
        })
        
    except Exception as e:
        print(f"Error deleting quote: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_list_quotes(event, user_claims):
    """Handle GET /admin/quotes with proper sorting and pagination"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Parse query parameters
        query_params = event.get('queryStringParameters') or {}
        limit = min(int(query_params.get('limit', 50)), 1000)  # Cap at 1000
        sort_by = query_params.get('sort_by', 'created_at')
        sort_order = query_params.get('sort_order', 'desc')
        last_key = query_params.get('last_key')
        
        print(f"Admin quotes request: limit={limit}, sort_by={sort_by}, sort_order={sort_order}")
        
        # Validate sort field
        valid_sort_fields = {'quote', 'author', 'created_at', 'updated_at'}
        if sort_by not in valid_sort_fields:
            return create_response(400, {
                "error": "Invalid sort field", 
                "valid_fields": list(valid_sort_fields)
            })
        
        # Validate sort order
        if sort_order not in ['asc', 'desc']:
            return create_response(400, {
                "error": "Invalid sort order", 
                "valid_orders": ['asc', 'desc']
            })
        
        # Get all quotes (we'll sort in memory since DynamoDB doesn't support arbitrary field sorting)
        scan_params = {}
        all_quotes = []
        
        while True:
            if last_key and len(all_quotes) == 0:  # Only use last_key on first scan
                try:
                    import json
                    scan_params['ExclusiveStartKey'] = json.loads(last_key)
                except:
                    pass  # Invalid last_key, ignore it
            
            response = table.scan(**scan_params)
            items = response.get('Items', [])
            
            # Filter out metadata records - only include actual quotes
            quotes_batch = [item for item in items if item.get('id') != 'TAGS_METADATA']
            all_quotes.extend(quotes_batch)
            
            # Check if we have more data
            if 'LastEvaluatedKey' not in response:
                break
            scan_params['ExclusiveStartKey'] = response['LastEvaluatedKey']
        
        print(f"Retrieved {len(all_quotes)} total quotes from database")
        
        # Sort quotes based on requested field and order
        reverse_sort = (sort_order == 'desc')
        
        if sort_by == 'quote':
            all_quotes.sort(key=lambda x: x.get('quote', '').lower(), reverse=reverse_sort)
        elif sort_by == 'author':
            all_quotes.sort(key=lambda x: x.get('author', '').lower(), reverse=reverse_sort)
        elif sort_by == 'created_at':
            all_quotes.sort(key=lambda x: x.get('created_at', ''), reverse=reverse_sort)
        elif sort_by == 'updated_at':
            all_quotes.sort(key=lambda x: x.get('updated_at', ''), reverse=reverse_sort)
        
        # Apply pagination after sorting
        total_count = len(all_quotes)
        quotes_page = all_quotes[:limit]
        
        # Determine if there are more quotes
        has_more = len(all_quotes) > limit
        next_last_key = None
        
        if has_more and len(quotes_page) > 0:
            # Create a simple pagination key based on the last item's sort field
            last_item = quotes_page[-1]
            next_last_key = json.dumps({
                'id': last_item['id'],
                'sort_field': last_item.get(sort_by, ''),
                'sort_by': sort_by,
                'sort_order': sort_order
            })
        
        print(f"Returning {len(quotes_page)} quotes (total: {total_count}, has_more: {has_more})")
        
        return create_response(200, {
            "quotes": quotes_page,
            "total_count": total_count,
            "count": len(quotes_page),
            "has_more": has_more,
            "last_key": next_last_key
        })
        
    except Exception as e:
        print(f"Error listing quotes: {e}")
        import traceback
        traceback.print_exc()
        return create_response(500, {"error": "Internal server error"})

def handle_get_tags(event, user_claims):
    """Handle GET /admin/tags"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        tags = get_tags_metadata()
        return create_response(200, {
            "tags": tags,
            "count": len(tags)
        })
        
    except Exception as e:
        print(f"Error getting tags: {e}")
        return create_response(500, {"error": "Internal server error"})

def get_used_tags():
    """Get all tags that are actually used in quotes"""
    try:
        # Scan all quotes to find used tags
        response = table.scan()
        quotes = response.get('Items', [])
        
        used_tags = set()
        for quote in quotes:
            # Skip metadata records
            if quote.get('id') == 'TAGS_METADATA':
                continue
            # Add all tags from this quote
            quote_tags = quote.get('tags', [])
            if isinstance(quote_tags, list):
                used_tags.update(quote_tags)
        
        return sorted(list(used_tags))
        
    except Exception as e:
        print(f"Error getting used tags: {e}")
        return []

def handle_cleanup_unused_tags(event, user_claims):
    """Handle DELETE /admin/tags/unused"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get current tags metadata
        current_tags = set(get_tags_metadata())
        
        # Get actually used tags
        used_tags = set(get_used_tags())
        
        # Find unused tags
        unused_tags = current_tags - used_tags
        
        if not unused_tags:
            return create_response(200, {
                "message": "No unused tags found",
                "removed_tags": [],
                "remaining_tags": sorted(list(used_tags)),
                "count_removed": 0,
                "count_remaining": len(used_tags)
            })
        
        # Update metadata to only include used tags
        metadata_id = "TAGS_METADATA"
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        table.put_item(Item={
            'id': metadata_id,
            'tags': sorted(list(used_tags)),
            'updated_at': timestamp
        })
        
        print(f"✅ Cleaned up unused tags: {sorted(list(unused_tags))}")
        print(f"✅ Remaining tags: {sorted(list(used_tags))}")
        
        return create_response(200, {
            "message": f"Successfully removed {len(unused_tags)} unused tags",
            "removed_tags": sorted(list(unused_tags)),
            "remaining_tags": sorted(list(used_tags)),
            "count_removed": len(unused_tags),
            "count_remaining": len(used_tags)
        })
        
    except Exception as e:
        print(f"Error cleaning up unused tags: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_add_tag(event, user_claims):
    """Handle POST /admin/tags"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        new_tag = body.get('tag', '').strip()
        
        if not new_tag:
            return create_response(400, {"error": "Tag name is required"})
        
        # Get current tags
        current_tags = set(get_tags_metadata())
        
        if new_tag in current_tags:
            return create_response(400, {"error": f"Tag '{new_tag}' already exists"})
        
        # Add new tag
        current_tags.add(new_tag)
        
        # Update metadata
        metadata_id = "TAGS_METADATA"
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        table.put_item(Item={
            'id': metadata_id,
            'tags': sorted(list(current_tags)),
            'updated_at': timestamp
        })
        
        print(f"✅ Added new tag: {new_tag}")
        
        return create_response(201, {
            "message": f"Successfully added tag '{new_tag}'",
            "tag": new_tag,
            "all_tags": sorted(list(current_tags))
        })
        
    except json.JSONDecodeError:
        return create_response(400, {"error": "Invalid JSON in request body"})
    except Exception as e:
        print(f"Error adding tag: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_update_tag(event, user_claims):
    """Handle PUT /admin/tags/{old_tag}"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get old tag from path
        old_tag = event.get('pathParameters', {}).get('tag')
        if not old_tag:
            return create_response(400, {"error": "Tag name is required in path"})
        
        # Parse request body
        body = json.loads(event.get('body', '{}'))
        new_tag = body.get('tag', '').strip()
        
        if not new_tag:
            return create_response(400, {"error": "New tag name is required"})
        
        if old_tag == new_tag:
            return create_response(400, {"error": "New tag name must be different from old tag name"})
        
        # Get current tags
        current_tags = set(get_tags_metadata())
        
        if old_tag not in current_tags:
            return create_response(404, {"error": f"Tag '{old_tag}' not found"})
        
        if new_tag in current_tags:
            return create_response(400, {"error": f"Tag '{new_tag}' already exists"})
        
        # Update tag in metadata
        current_tags.remove(old_tag)
        current_tags.add(new_tag)
        
        # Update metadata
        metadata_id = "TAGS_METADATA"
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        table.put_item(Item={
            'id': metadata_id,
            'tags': sorted(list(current_tags)),
            'updated_at': timestamp
        })
        
        # Update all quotes that use this tag
        response = table.scan()
        all_items = response.get('Items', [])
        quotes_updated = 0
        
        for item in all_items:
            if item.get('id') != 'TAGS_METADATA' and 'tags' in item:
                if old_tag in item['tags']:
                    # Update the tags in this quote
                    updated_tags = [new_tag if tag == old_tag else tag for tag in item['tags']]
                    item['tags'] = updated_tags
                    item['updated_at'] = timestamp
                    table.put_item(Item=item)
                    quotes_updated += 1
        
        print(f"✅ Updated tag '{old_tag}' to '{new_tag}' in {quotes_updated} quotes")
        
        return create_response(200, {
            "message": f"Successfully updated tag '{old_tag}' to '{new_tag}'",
            "old_tag": old_tag,
            "new_tag": new_tag,
            "quotes_updated": quotes_updated,
            "all_tags": sorted(list(current_tags))
        })
        
    except json.JSONDecodeError:
        return create_response(400, {"error": "Invalid JSON in request body"})
    except Exception as e:
        print(f"Error updating tag: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_delete_tag(event, user_claims):
    """Handle DELETE /admin/tags/{tag}"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        # Get tag from path
        tag_to_delete = event.get('pathParameters', {}).get('tag')
        if not tag_to_delete:
            return create_response(400, {"error": "Tag name is required in path"})
        
        # Get current tags
        current_tags = set(get_tags_metadata())
        
        if tag_to_delete not in current_tags:
            return create_response(404, {"error": f"Tag '{tag_to_delete}' not found"})
        
        # Remove tag from metadata
        current_tags.remove(tag_to_delete)
        
        # Update metadata
        metadata_id = "TAGS_METADATA"
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        table.put_item(Item={
            'id': metadata_id,
            'tags': sorted(list(current_tags)),
            'updated_at': timestamp
        })
        
        # Remove tag from all quotes that use it
        response = table.scan()
        all_items = response.get('Items', [])
        quotes_updated = 0
        
        for item in all_items:
            if item.get('id') != 'TAGS_METADATA' and 'tags' in item:
                if tag_to_delete in item['tags']:
                    # Remove the tag from this quote
                    item['tags'] = [tag for tag in item['tags'] if tag != tag_to_delete]
                    item['updated_at'] = timestamp
                    table.put_item(Item=item)
                    quotes_updated += 1
        
        print(f"✅ Deleted tag '{tag_to_delete}' from {quotes_updated} quotes")
        
        return create_response(200, {
            "message": f"Successfully deleted tag '{tag_to_delete}'",
            "deleted_tag": tag_to_delete,
            "quotes_updated": quotes_updated,
            "all_tags": sorted(list(current_tags))
        })
        
    except Exception as e:
        print(f"Error deleting tag: {e}")
        return create_response(500, {"error": "Internal server error"})

def handle_check_duplicate(event, user_claims):
    """Check if a quote is a duplicate of an existing quote"""
    if not user_claims['is_admin']:
        return create_response(403, {"error": "Forbidden", "message": "Admin access required"})
    
    try:
        body = json.loads(event.get('body', '{}'))
        quote_text = body.get('quote', '').strip()
        author = body.get('author', '').strip()
        
        if not quote_text or not author:
            return create_response(400, {"error": "Quote and author are required"})
        
        print(f"🔍 Checking for duplicates of: '{quote_text[:50]}...' by {author}")
        
        # Scan all quotes to check for duplicates
        # Using scan because we need to check all quotes with fuzzy matching
        # This is acceptable for duplicate checking during quote addition
        duplicates_found = []
        
        try:
            # Scan the table in chunks
            scan_kwargs = {}
            
            while True:
                response = table.scan(**scan_kwargs)
                items = response.get('Items', [])
                
                for item in items:
                    # Skip non-quote items (like metadata)
                    if item.get('id', '').startswith('TAGS_') or not item.get('quote'):
                        continue
                    
                    existing_quote = item.get('quote', '')
                    existing_author = item.get('author', '')
                    
                    is_similar, match_reason = are_similar_quotes(
                        quote_text, author,
                        existing_quote, existing_author
                    )
                    
                    if is_similar:
                        duplicates_found.append({
                            "id": item.get('id'),
                            "quote": existing_quote,
                            "author": existing_author,
                            "created_at": item.get('created_at'),
                            "match_reason": match_reason
                        })
                
                # Check if there are more items to scan
                if 'LastEvaluatedKey' not in response:
                    break
                scan_kwargs['ExclusiveStartKey'] = response['LastEvaluatedKey']
                
        except Exception as e:
            print(f"Error scanning for duplicates: {e}")
            return create_response(500, {"error": "Failed to check for duplicates"})
        
        print(f"🔍 Found {len(duplicates_found)} potential duplicates")
        
        if duplicates_found:
            return create_response(200, {
                "is_duplicate": True,
                "duplicate_count": len(duplicates_found),
                "duplicates": duplicates_found[:5],  # Return up to 5 matches
                "message": f"Found {len(duplicates_found)} similar quote(s)"
            })
        else:
            return create_response(200, {
                "is_duplicate": False,
                "duplicate_count": 0,
                "duplicates": [],
                "message": "No duplicates found"
            })
            
    except json.JSONDecodeError:
        return create_response(400, {"error": "Invalid JSON in request body"})
    except Exception as e:
        print(f"Error in duplicate check: {e}")
        return create_response(500, {"error": "Internal server error"})

def lambda_handler(event, context):
    """
    AWS Lambda handler for admin quote management.
    Handles CRUD operations for quotes with Cognito authentication.
    """
    print("🔥🔥🔥 LAMBDA START")
    print(f"🚀 LAMBDA ENTRY: {event.get('httpMethod')} {event.get('path')}")
    try:
        # Extract user claims from Cognito
        user_claims = get_user_claims(event)
        print(f"Admin request from user: {user_claims['username']}, is_admin: {user_claims['is_admin']}")
        
        # Route based on HTTP method and path
        method = event.get('httpMethod', '')
        path = event.get('path', '')
        
        if method == 'POST' and path == '/admin/quotes':
            return handle_create_quote(event, user_claims)
        elif method == 'PUT' and path.startswith('/admin/quotes/'):
            return handle_update_quote(event, user_claims)
        elif method == 'DELETE' and path.startswith('/admin/quotes/'):
            return handle_delete_quote(event, user_claims)
        elif method == 'GET' and path == '/admin/quotes':
            return handle_list_quotes(event, user_claims)
        elif method == 'GET' and path == '/admin/tags':
            return handle_get_tags(event, user_claims)
        elif method == 'POST' and path == '/admin/tags':
            return handle_add_tag(event, user_claims)
        elif method == 'PUT' and path.startswith('/admin/tags/'):
            return handle_update_tag(event, user_claims)
        elif method == 'DELETE' and path == '/admin/tags/unused':
            return handle_cleanup_unused_tags(event, user_claims)
        elif method == 'DELETE' and path.startswith('/admin/tags/'):
            return handle_delete_tag(event, user_claims)
        elif method == 'POST' and path == '/admin/check-duplicate':
            return handle_check_duplicate(event, user_claims)
        else:
            return create_response(404, {"error": "Not found"})
            
    except Exception as e:
        print(f"Lambda error: {e}")
        return create_response(500, {"error": "Internal server error"})
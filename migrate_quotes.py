#!/usr/bin/env python3
"""
Migrate hardcoded quotes to DynamoDB with tags
"""

import boto3
import uuid
from datetime import datetime

# Initialize DynamoDB
dynamodb = boto3.resource('dynamodb', region_name='us-east-1')
table = dynamodb.Table('dcc-quotes')

# Hardcoded quotes with assigned tags
quotes_data = [
    {
        "quote": "The only way to do great work is to love what you do.",
        "author": "Steve Jobs",
        "tags": ["Motivation", "Business", "Success"]
    },
    {
        "quote": "Innovation distinguishes between a leader and a follower.",
        "author": "Steve Jobs", 
        "tags": ["Business", "Innovation", "Leadership"]
    },
    {
        "quote": "Life is what happens to you while you're busy making other plans.",
        "author": "John Lennon",
        "tags": ["Motivation", "Life"]
    },
    {
        "quote": "The future belongs to those who believe in the beauty of their dreams.",
        "author": "Eleanor Roosevelt",
        "tags": ["Motivation", "Dreams", "Success"]
    },
    {
        "quote": "It is during our darkest moments that we must focus to see the light.",
        "author": "Aristotle",
        "tags": ["Motivation", "Persistence", "Wisdom"]
    },
    {
        "quote": "The way to get started is to quit talking and begin doing.",
        "author": "Walt Disney",
        "tags": ["Motivation", "Action", "Business"]
    },
    {
        "quote": "Don't let yesterday take up too much of today.",
        "author": "Will Rogers",
        "tags": ["Motivation", "Life", "Wisdom"]
    },
    {
        "quote": "You learn more from failure than from success. Don't let it stop you. Failure builds character.",
        "author": "Unknown",
        "tags": ["Motivation", "Persistence", "Learning"]
    },
    {
        "quote": "If you are working on something that you really care about, you don't have to be pushed. The vision pulls you.",
        "author": "Steve Jobs",
        "tags": ["Motivation", "Passion", "Business"]
    },
    {
        "quote": "Experience is a hard teacher because she gives the test first, the lesson afterward.",
        "author": "Vernon Law",
        "tags": ["Education", "Learning", "Sports", "Wisdom"]
    },
    {
        "quote": "Knowing is not enough; we must apply. Wishing is not enough; we must do.",
        "author": "Johann Wolfgang von Goethe",
        "tags": ["Action", "Learning", "Motivation"]
    },
    {
        "quote": "Whether you think you can or you think you can't, you're right.",
        "author": "Henry Ford",
        "tags": ["Motivation", "Mindset", "Business"]
    },
    {
        "quote": "I have not failed. I've just found 10,000 ways that won't work.",
        "author": "Thomas A. Edison",
        "tags": ["Persistence", "Science", "Innovation"]
    },
    {
        "quote": "A person who never made a mistake never tried anything new.",
        "author": "Albert Einstein",
        "tags": ["Learning", "Science", "Innovation"]
    },
    {
        "quote": "If you want to lift yourself up, lift up someone else.",
        "author": "Booker T. Washington",
        "tags": ["Leadership", "Motivation", "Education"]
    },
    {
        "quote": "To live a creative life, we must lose our fear of being wrong.",
        "author": "Joseph Chilton Pearce",
        "tags": ["Creativity", "Motivation", "Art"]
    },
    {
        "quote": "Success is not final, failure is not fatal: it is the courage to continue that counts.",
        "author": "Winston Churchill",
        "tags": ["Persistence", "Motivation", "Success"]
    },
    {
        "quote": "The only impossible journey is the one you never begin.",
        "author": "Tony Robbins",
        "tags": ["Motivation", "Action", "Success"]
    }
]

def create_quote_record(quote_data):
    """Create a quote record with tag explosion for GSI"""
    quote_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat() + 'Z'
    
    # Main quote record
    quote_record = {
        'id': quote_id,
        'quote': quote_data['quote'],
        'author': quote_data['author'],
        'tags': quote_data['tags'],
        'created_at': timestamp,
        'updated_at': timestamp
    }
    
    return quote_record, quote_id

def create_tag_records(quote_id, tags):
    """Create individual tag records for GSI querying"""
    tag_records = []
    for tag in tags:
        tag_record = {
            'tag': tag,
            'quote_id': quote_id
        }
        tag_records.append(tag_record)
    return tag_records

def initialize_tags_metadata(all_tags):
    """Initialize the tags metadata record"""
    try:
        timestamp = datetime.utcnow().isoformat() + 'Z'
        
        tags_metadata = {
            'id': 'TAGS_METADATA',
            'tags': sorted(list(all_tags)),
            'updated_at': timestamp
        }
        
        table.put_item(Item=tags_metadata)
        print(f"✅ Initialized tags metadata with {len(all_tags)} tags: {sorted(list(all_tags))}")
        
    except Exception as e:
        print(f"❌ Error initializing tags metadata: {e}")

def migrate_quotes():
    """Migrate all quotes to DynamoDB"""
    print("🚀 Starting quote migration to DynamoDB...")
    
    success_count = 0
    error_count = 0
    all_tags = set()  # Collect all unique tags
    
    for i, quote_data in enumerate(quotes_data, 1):
        try:
            # Create main quote record
            quote_record, quote_id = create_quote_record(quote_data)
            
            # Put main record
            table.put_item(Item=quote_record)
            
            # Collect tags for metadata
            all_tags.update(quote_data['tags'])
            
            print(f"✅ {i:2d}. {quote_data['author']}: {quote_data['quote'][:50]}...")
            print(f"    Tags: {', '.join(quote_data['tags'])}")
            print(f"    ID: {quote_id}")
            print()
            
            success_count += 1
            
        except Exception as e:
            print(f"❌ Error migrating quote {i}: {e}")
            error_count += 1
    
    print(f"\n📊 Migration Summary:")
    print(f"✅ Successfully migrated: {success_count} quotes")
    print(f"❌ Errors: {error_count}")
    print(f"📋 Total: {len(quotes_data)} quotes")
    
    if success_count > 0:
        # Initialize tags metadata
        initialize_tags_metadata(all_tags)
        
        print(f"\n🎯 DynamoDB table 'dcc-quotes' now contains {success_count} quotes with tags!")
        print(f"🏷️  Tags metadata initialized with {len(all_tags)} unique tags")
        print("📝 Next steps:")
        print("   1. Deploy updated Lambda functions")
        print("   2. Test admin /tags endpoint")
        print("   3. Update Flutter settings to load dynamic tags")

if __name__ == "__main__":
    migrate_quotes()
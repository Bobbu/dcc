#!/usr/bin/env python3
"""
Script to run the DynamoDB migration locally for testing
"""
import os
import sys

# Add lambda directory to path so we can import the migration module
sys.path.append(os.path.join(os.path.dirname(__file__), 'lambda'))

# Set environment variables for the migration
os.environ['OLD_TABLE_NAME'] = 'dcc-quotes'
os.environ['NEW_TABLE_NAME'] = 'dcc-quotes-optimized'

# Import and run the migration
from migration import lambda_handler

if __name__ == '__main__':
    print("Starting DynamoDB migration...")
    
    # Test event for migration
    test_event = {
        'dry_run': False,  # Set to True for dry run
        'batch_size': 25,
        'start_key': None
    }
    
    try:
        result = lambda_handler(test_event, None)
        print(f"Migration completed with status: {result['statusCode']}")
        print(f"Response: {result['body']}")
    except Exception as e:
        print(f"Migration failed: {str(e)}")
        sys.exit(1)
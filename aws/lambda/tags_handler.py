import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
tags_table = dynamodb.Table(os.environ['TAGS_TABLE_NAME'])

def decimal_default(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event, context):
    """Handle tags endpoint requests"""
    try:
        # Get all tags
        response = tags_table.scan()
        tags = [item['tag'] for item in response['Items']]
        
        # Continue scanning if there are more items
        while 'LastEvaluatedKey' in response:
            response = tags_table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            tags.extend([item['tag'] for item in response['Items']])
        
        # Sort tags alphabetically
        tags.sort()
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, X-Api-Key'
            },
            'body': json.dumps(tags, default=decimal_default)
        }
        
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'message': 'Internal server error'})
        }
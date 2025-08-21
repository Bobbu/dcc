import json

def lambda_handler(event, context):
    """
    Handle OPTIONS requests for CORS preflight
    """
    
    # Get the origin from the request headers
    origin = event.get('headers', {}).get('origin') or event.get('headers', {}).get('Origin')
    
    # Allow specific origins - add your web app domain here
    allowed_origins = [
        'https://quote-me.anystupididea.com',
        'https://dcc.anystupididea.com',
        'http://localhost:3000',  # For local development
        'http://127.0.0.1:3000'   # For local development
    ]
    
    # Determine the origin to return
    if origin in allowed_origins:
        allow_origin = origin
    else:
        allow_origin = '*'  # Fallback for other origins
    
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': allow_origin,
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,x-api-key',
            'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
            'Access-Control-Allow-Credentials': 'true',
            'Access-Control-Max-Age': '86400'
        },
        'body': json.dumps({'message': 'CORS preflight successful'})
    }
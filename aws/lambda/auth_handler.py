import json
import boto3
import os
from botocore.exceptions import ClientError

cognito_client = boto3.client('cognito-idp')

def lambda_handler(event, context):
    """
    Handle user authentication operations (registration, confirmation)
    """
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'POST,OPTIONS'
    }
    
    try:
        print(f"Received event: {json.dumps(event)}")
        
        # Get the path and method
        path = event.get('path', '')
        method = event.get('httpMethod', '')
        
        if method != 'POST':
            return {
                'statusCode': 405,
                'headers': headers,
                'body': json.dumps({'error': 'Method not allowed'})
            }
        
        # Parse the request body
        request_body = event.get('body', '{}')
        print(f"Request body: {request_body}")
        
        # Handle potential escaped characters in the body
        try:
            body = json.loads(request_body)
        except json.JSONDecodeError as e:
            print(f"JSON decode error: {e}")
            # Try to handle common escaping issues
            # Replace escaped special characters that shouldn't be escaped in JSON
            cleaned_body = request_body.replace('\\!', '!')
            body = json.loads(cleaned_body)
        
        # Handle different auth endpoints
        if path == '/auth/register':
            return handle_registration(body, headers)
        elif path == '/auth/confirm':
            return handle_confirmation(body, headers)
        else:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({'error': 'Endpoint not found'})
            }
            
    except Exception as e:
        print(f"Error in auth_handler: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': 'Internal server error'})
        }

def handle_registration(body, headers):
    """
    Handle user registration with automatic group assignment
    """
    try:
        email = body.get('email')
        password = body.get('password')
        name = body.get('name', '')
        
        if not email or not password:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Email and password are required'})
            }
        
        # Get User Pool ID and Client ID from environment or CloudFormation exports
        user_pool_id = os.environ.get('USER_POOL_ID')
        client_id = os.environ.get('USER_POOL_CLIENT_ID')
        
        # Register the user
        response = cognito_client.sign_up(
            ClientId=client_id,
            Username=email,
            Password=password,
            UserAttributes=[
                {'Name': 'email', 'Value': email},
                {'Name': 'name', 'Value': name}
            ]
        )
        
        # Add user to Users group after registration
        try:
            cognito_client.admin_add_user_to_group(
                UserPoolId=user_pool_id,
                Username=email,
                GroupName='Users'
            )
            print(f"Added user {email} to Users group")
        except Exception as group_error:
            print(f"Error adding user to group: {group_error}")
            # Continue even if group assignment fails
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': 'Registration successful. Please check your email for verification code.',
                'userSub': response['UserSub'],
                'codeDeliveryDetails': response.get('CodeDeliveryDetails', {})
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        
        if error_code == 'UsernameExistsException':
            return {
                'statusCode': 409,
                'headers': headers,
                'body': json.dumps({'error': 'User already exists'})
            }
        elif error_code == 'InvalidPasswordException':
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Password does not meet requirements'})
            }
        else:
            print(f"Cognito error: {error_code} - {error_message}")
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': error_message})
            }
    except Exception as e:
        print(f"Registration error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': 'Registration failed'})
        }

def handle_confirmation(body, headers):
    """
    Handle email confirmation for new users
    """
    try:
        email = body.get('email')
        code = body.get('code')
        
        if not email or not code:
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Email and confirmation code are required'})
            }
        
        client_id = os.environ.get('USER_POOL_CLIENT_ID')
        user_pool_id = os.environ.get('USER_POOL_ID')
        
        # Confirm the user
        cognito_client.confirm_sign_up(
            ClientId=client_id,
            Username=email,
            ConfirmationCode=code
        )
        
        # Add user to Users group after confirmation
        try:
            cognito_client.admin_add_user_to_group(
                UserPoolId=user_pool_id,
                Username=email,
                GroupName='Users'
            )
            print(f"Added confirmed user {email} to Users group")
        except Exception as group_error:
            print(f"Error adding confirmed user to group: {group_error}")
            # Continue even if group assignment fails - user can still sign in
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': 'Email confirmed successfully. You can now sign in.'
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        
        if error_code == 'CodeMismatchException':
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Invalid confirmation code'})
            }
        elif error_code == 'ExpiredCodeException':
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': 'Confirmation code has expired'})
            }
        else:
            print(f"Confirmation error: {error_code} - {error_message}")
            return {
                'statusCode': 400,
                'headers': headers,
                'body': json.dumps({'error': error_message})
            }
    except Exception as e:
        print(f"Confirmation error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': 'Confirmation failed'})
        }
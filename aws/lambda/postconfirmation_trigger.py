import json
import logging
import boto3
import os

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize Cognito client
cognito = boto3.client('cognito-idp')

def lambda_handler(event, context):
    """
    Handle Cognito PostConfirmation trigger
    This function automatically adds confirmed users to the "Users" group
    """
    logger.info(f"PostConfirmation trigger event: {json.dumps(event, default=str)}")
    
    try:
        trigger_source = event.get('triggerSource')
        user_pool_id = event['userPoolId']
        username = event['userName']
        
        if trigger_source in ['PostConfirmation_ConfirmSignUp', 'PostConfirmation_ConfirmForgotPassword']:
            logger.info(f"Adding user {username} to Users group")
            
            try:
                # Add user to the "Users" group
                cognito.admin_add_user_to_group(
                    UserPoolId=user_pool_id,
                    Username=username,
                    GroupName='Users'
                )
                logger.info(f"✅ Successfully added user {username} to Users group")
                
            except Exception as group_error:
                logger.error(f"❌ Failed to add user {username} to Users group: {str(group_error)}")
                # Don't raise exception here as it would block the confirmation process
        else:
            logger.info(f"No action needed for trigger source: {trigger_source}")
    
    except Exception as e:
        logger.error(f"Error in PostConfirmation trigger: {str(e)}")
        # Don't raise the exception as it would block user confirmation
    
    logger.info(f"Returning event: {json.dumps(event, default=str)}")
    return event
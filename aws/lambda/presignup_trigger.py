import json
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Handle Cognito PreSignUp trigger for external providers
    This function automatically confirms users signing up via external identity providers like Google
    """
    logger.info(f"PreSignUp trigger event: {json.dumps(event, default=str)}")
    
    try:
        trigger_source = event.get('triggerSource')
        
        if trigger_source == 'PreSignUp_ExternalProvider':
            # Automatically confirm users from external providers (like Google)
            logger.info("Auto-confirming user from external provider (Google)")
            
            # Auto-confirm the user
            event['response']['autoConfirmUser'] = True
            
            # Auto-verify email since it comes from a trusted provider
            event['response']['autoVerifyEmail'] = True
            
            # Auto-verify phone if provided
            if 'phone_number' in event['request']['userAttributes']:
                event['response']['autoVerifyPhone'] = True
            
            logger.info("User auto-confirmed for external provider sign-up")
        else:
            # For regular Cognito sign-ups, don't auto-confirm
            logger.info(f"Regular sign-up detected: {trigger_source}")
    
    except Exception as e:
        logger.error(f"Error in PreSignUp trigger: {str(e)}")
        # Don't raise the exception as it would block user sign-up
        # Just log the error and continue
    
    logger.info(f"Returning event: {json.dumps(event, default=str)}")
    return event
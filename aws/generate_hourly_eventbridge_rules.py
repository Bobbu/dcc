#!/usr/bin/env python3
"""
Generate CloudFormation template for 24 hourly EventBridge rules.
Each rule triggers once per hour and the batcher handles all timezones.
"""

import json

def generate_hourly_rules():
    """Generate 24 EventBridge rules (one per hour)."""
    
    rules = {}
    permissions = {}
    
    for hour in range(24):
        hour_str = f"{hour:02d}"
        
        # Create rule name
        rule_name = f"EventBridgeRuleHour{hour_str}"
        permission_name = f"NotificationBatcherPermissionHour{hour_str}"
        
        # Create the EventBridge rule
        rules[rule_name] = {
            "Type": "AWS::Events::Rule",
            "Properties": {
                "Name": f"daily-nuggets-hour-{hour_str}",
                "Description": f"Trigger Daily Nuggets delivery for hour {hour_str}:00 across all timezones",
                "ScheduleExpression": f"cron(0 {hour} * * ? *)",  # Every day at this hour UTC
                "State": "ENABLED",
                "Targets": [
                    {
                        "Arn": {"Fn::GetAtt": ["NotificationBatcherFunction", "Arn"]},
                        "Id": f"NotificationBatcherHour{hour_str}Target",
                        "Input": json.dumps({
                            "source": "aws.scheduler",
                            "detail": {
                                "hour_utc": hour,
                                "trigger_time": f"{hour_str}:00"
                            }
                        }, indent=None)
                    }
                ]
            }
        }
        
        # Create Lambda permission for EventBridge to invoke
        permissions[permission_name] = {
            "Type": "AWS::Lambda::Permission",
            "Properties": {
                "FunctionName": {"Ref": "NotificationBatcherFunction"},
                "Action": "lambda:InvokeFunction",
                "Principal": "events.amazonaws.com",
                "SourceArn": {"Fn::GetAtt": [rule_name, "Arn"]}
            }
        }
    
    # Generate the CloudFormation template snippet
    template = {
        "Resources": {
            **rules,
            **permissions
        }
    }
    
    return template

def save_template():
    """Save the generated template."""
    template = generate_hourly_rules()
    
    # Save as JSON for easy inclusion
    with open('hourly_eventbridge_rules.json', 'w') as f:
        json.dump(template, f, indent=2)
    
    # Also save as YAML snippet
    yaml_content = "  # 24-Hour EventBridge Rules for Daily Nuggets\n"
    yaml_content += "  # Each rule triggers once per hour UTC and the batcher handles timezone calculations\n\n"
    
    for hour in range(24):
        hour_str = f"{hour:02d}"
        yaml_content += f"""  EventBridgeRuleHour{hour_str}:
    Type: AWS::Events::Rule
    Properties:
      Name: daily-nuggets-hour-{hour_str}
      Description: "Trigger Daily Nuggets delivery for hour {hour_str}:00 across all timezones"
      ScheduleExpression: "cron(0 {hour} * * ? *)"
      State: ENABLED
      Targets:
        - Arn: !GetAtt NotificationBatcherFunction.Arn
          Id: "NotificationBatcherHour{hour_str}Target"
          Input: !Sub |
            {{
              "source": "aws.scheduler",
              "detail": {{
                "hour_utc": {hour},
                "trigger_time": "{hour_str}:00"
              }}
            }}

  NotificationBatcherPermissionHour{hour_str}:
    Type: AWS::Lambda::Permission
    Properties:
      FunctionName: !Ref NotificationBatcherFunction
      Action: lambda:InvokeFunction
      Principal: events.amazonaws.com
      SourceArn: !GetAtt EventBridgeRuleHour{hour_str}.Arn

"""
    
    with open('hourly_eventbridge_rules.yaml', 'w') as f:
        f.write(yaml_content)
    
    print("Generated 24-hour EventBridge rules!")
    print("Files created:")
    print("  - hourly_eventbridge_rules.json")
    print("  - hourly_eventbridge_rules.yaml")
    print(f"\nTotal rules: 24")
    print(f"Total Lambda permissions: 24")
    print("\nSchedule coverage:")
    print("  - Every hour from 00:00 to 23:00 UTC")
    print("  - Supports all timezones worldwide")
    print("  - Users can choose any hour for delivery")

if __name__ == "__main__":
    save_template()
#!/usr/bin/env python3
"""
Update template.yaml to replace timezone-specific EventBridge rules with 24 hourly rules.
This enables users to choose any hour for their Daily Nuggets delivery.
"""

def generate_hourly_rules_yaml():
    """Generate YAML for 24 hourly EventBridge rules."""
    
    yaml_content = """  # 24-Hour EventBridge Rules for Daily Nuggets
  # Users can choose any hour (00:00-23:00) for delivery in their timezone
  # Each rule triggers once per hour UTC, and the batcher handles timezone calculations
"""
    
    # Generate rules for each hour
    for hour in range(24):
        hour_str = f"{hour:02d}"
        
        # Add the EventBridge rule
        yaml_content += f"""
  EventBridgeRuleHour{hour_str}:
    Type: AWS::Events::Rule
    Properties:
      Name: daily-nuggets-hour-{hour_str}
      Description: "Trigger Daily Nuggets for users preferring {hour_str}:00 delivery"
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
            }}"""
    
    # Add Lambda permissions after all rules
    yaml_content += """

  # Lambda Permissions for EventBridge Rules
"""
    
    for hour in range(24):
        hour_str = f"{hour:02d}"
        yaml_content += f"""
  NotificationBatcherPermissionHour{hour_str}:
    Type: AWS::Lambda::Permission
    Properties:
      FunctionName: !Ref NotificationBatcherFunction
      Action: lambda:InvokeFunction
      Principal: events.amazonaws.com
      SourceArn: !GetAtt EventBridgeRuleHour{hour_str}.Arn"""
    
    return yaml_content

def update_template():
    """Update the template.yaml file."""
    
    # Read the current template
    with open('template.yaml', 'r') as f:
        lines = f.readlines()
    
    # Find the start and end of the EventBridge rules section
    start_idx = None
    end_idx = None
    
    for i, line in enumerate(lines):
        # Find the comment about EventBridge rules
        if 'EventBridge Rules for different timezones' in line:
            start_idx = i
        
        # Find where the old Lambda permissions end (look for the next resource after permissions)
        if start_idx and 'DailyNuggetsEventPermissionLondon:' in line:
            # Find the end of this resource
            for j in range(i+1, len(lines)):
                if lines[j].strip() and not lines[j].startswith(' '):
                    end_idx = j
                    break
                elif 'Type:' in lines[j] and 'AWS::Lambda::Permission' not in lines[j]:
                    end_idx = j - 1
                    break
                elif '# ' in lines[j] and j > i + 5:  # Found next section comment
                    end_idx = j - 1
                    break
    
    if not start_idx:
        print("Could not find EventBridge rules section in template.yaml")
        return False
    
    # If we didn't find the end, look for the next major resource
    if not end_idx:
        for i in range(start_idx + 100, min(start_idx + 200, len(lines))):
            if lines[i].startswith('  ') and not lines[i].startswith('    ') and 'Type:' not in lines[i]:
                if ':' in lines[i]:
                    end_idx = i - 1
                    break
    
    if not end_idx:
        print("Could not find end of EventBridge rules section")
        return False
    
    print(f"Found EventBridge rules section: lines {start_idx+1} to {end_idx+1}")
    
    # Generate new rules
    new_rules = generate_hourly_rules_yaml()
    
    # Construct the new template
    new_lines = lines[:start_idx] + [new_rules + '\n'] + lines[end_idx+1:]
    
    # Write the updated template
    with open('template.yaml', 'w') as f:
        f.writelines(new_lines)
    
    print("✅ Successfully updated template.yaml with 24 hourly EventBridge rules!")
    print("   - Removed: 5 timezone-specific rules (Eastern, Central, Mountain, Pacific, London)")
    print("   - Added: 24 hourly rules (00:00 to 23:00 UTC)")
    print("   - Users can now choose any hour for Daily Nuggets delivery!")
    
    return True

if __name__ == "__main__":
    if update_template():
        print("\n🚀 Next step: Run ./deploy.sh to deploy the updated rules")
    else:
        print("\n❌ Failed to update template.yaml")
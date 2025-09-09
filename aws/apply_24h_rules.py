#!/usr/bin/env python3
"""
Replace timezone-specific EventBridge rules with 24-hour rules in template.yaml
This enables users to choose any hour for their Daily Nuggets delivery.
"""

import re
from datetime import datetime

def apply_24h_rules():
    """Replace the old EventBridge rules with new 24-hour rules."""
    
    # Read the original template
    with open('template.yaml', 'r') as f:
        content = f.read()
    
    # Create backup
    backup_name = f'template.yaml.backup.{datetime.now().strftime("%Y%m%d_%H%M%S")}'
    with open(backup_name, 'w') as f:
        f.write(content)
    print(f"✅ Created backup: {backup_name}")
    
    # Read the new 24-hour rules
    with open('eventbridge_rules_24h.yaml', 'r') as f:
        new_rules = f.read()
    
    # Find and replace the EventBridge section
    # Pattern to match from the EventBridge comment to the end of London permission
    pattern = r'  # EventBridge Rules for different timezones.*?SourceArn: !GetAtt EventBridgeRuleLondon\.Arn\n'
    
    # Use re.DOTALL to match across multiple lines
    match = re.search(pattern, content, re.DOTALL)
    
    if match:
        # Replace the old rules with new ones
        content = content[:match.start()] + new_rules + '\n' + content[match.end():]
        
        # Write the updated template
        with open('template.yaml', 'w') as f:
            f.write(content)
        
        print("✅ Successfully updated template.yaml with 24-hour EventBridge rules!")
        print("")
        print("📊 Summary of changes:")
        print("   - Removed: 5 timezone-specific rules (Eastern, Central, Mountain, Pacific, London)")
        print("   - Removed: 5 Lambda permissions for old rules")
        print("   - Added: 24 hourly rules (00:00 to 23:00 UTC)")
        print("   - Added: 24 Lambda permissions for new rules")
        print("")
        print("🎯 User Benefits:")
        print("   - Can choose ANY hour for delivery (6 AM, 8 AM, 10 PM, etc.)")
        print("   - Works with any timezone worldwide")
        print("   - More flexible scheduling options")
        print("")
        print("💰 Cost Impact:")
        print("   - EventBridge: < $0.01/month (essentially free)")
        print("   - Lambda: Still within free tier")
        print("")
        print("🚀 Next steps:")
        print("   1. Review the changes: git diff template.yaml")
        print("   2. Deploy: sam build && sam deploy")
        return True
    else:
        print("❌ Could not find the EventBridge rules section in template.yaml")
        print("   The template may have already been updated or has a different structure.")
        return False

if __name__ == "__main__":
    apply_24h_rules()
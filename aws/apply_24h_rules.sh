#!/bin/bash

# Script to replace timezone-specific EventBridge rules with 24-hour rules
# This enables users to choose any hour for their Daily Nuggets delivery

echo "🕐 Updating template.yaml with 24-hour EventBridge rules..."

# Backup the original template
cp template.yaml template.yaml.backup.$(date +%Y%m%d_%H%M%S)
echo "✅ Created backup of template.yaml"

# Use sed to remove the old EventBridge rules section
# This removes from the comment line to the end of London permission
sed -i '' '/# EventBridge Rules for different timezones/,/SourceArn: !GetAtt EventBridgeRuleLondon.Arn/d' template.yaml

# Find the line number where we should insert the new rules (before GatewayResponse4xx)
LINE_NUM=$(grep -n "GatewayResponse4xx:" template.yaml | cut -d: -f1)

# Insert the new 24-hour rules before the GatewayResponse4xx
sed -i '' "${LINE_NUM}i\\
$(cat eventbridge_rules_24h.yaml)
" template.yaml

echo "✅ Replaced 5 timezone-specific rules with 24 hourly rules"
echo ""
echo "📊 Summary of changes:"
echo "   - Removed: Eastern, Central, Mountain, Pacific, London rules"
echo "   - Added: 24 hourly rules (00:00 to 23:00 UTC)"
echo "   - Added: 24 Lambda permissions for EventBridge"
echo ""
echo "🎯 Benefits:"
echo "   - Users can now choose ANY hour for delivery (not just 8 AM)"
echo "   - Supports all timezones worldwide"
echo "   - More flexible and user-friendly"
echo ""
echo "🚀 Next step: Run ./deploy.sh to deploy the changes"
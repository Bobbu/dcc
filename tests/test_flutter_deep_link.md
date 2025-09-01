# Flutter Deep Link Testing Guide

## Testing the Profile Deep Link

### Method 1: Using ADB (Android)
```bash
# Test universal link
adb shell am start -W -a android.intent.action.VIEW -d "https://quote-me.anystupididea.com/profile" com.example.dcc_mobile

# Test custom scheme  
adb shell am start -W -a android.intent.action.VIEW -d "quoteme://profile" com.example.dcc_mobile
```

### Method 2: Using iOS Simulator
```bash
# Test universal link
xcrun simctl openurl booted "https://quote-me.anystupididea.com/profile"

# Test custom scheme
xcrun simctl openurl booted "quoteme://profile"
```

### Method 3: Manual Testing
1. Send yourself an email with the deep link
2. Open email on your mobile device
3. Tap "Manage your subscription" link
4. Should open Quote Me app directly to Profile screen

### Expected Behavior
- Link opens Quote Me app
- Navigates directly to User Profile screen
- User can manage Daily Nuggets subscription settings
- No authentication required (deep link handles app launch)

## Verification Checklist
✅ GoRouter has `/profile` route defined
✅ UserProfileScreen imported in main.dart
✅ Android manifest has intent filters configured
✅ iOS Info.plist has URL schemes configured  
✅ Daily Nuggets email template uses correct URL
✅ Lambda function deployed with updated template
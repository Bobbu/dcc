# Sign in with Apple Configuration Instructions

## Overview
I've successfully added Sign in with Apple functionality to your Flutter app. The code is ready, but you need to complete some configuration steps on the Apple Developer side and AWS Cognito.

## What's Been Done ✅
1. **Login Screen**: Added "Sign in with Apple" button available on ALL platforms (iOS, Android, Web)
2. **Auth Service**: Implemented `signInWithApple()` method using AWS Amplify's federated authentication
3. **Federated User Support**: Updated all federated user checks to include Apple accounts

## Required Configuration Steps

### 1. Apple Developer Account Setup

1. **Sign in to Apple Developer**
   - Go to https://developer.apple.com
   - Sign in with your Apple Developer account

2. **Configure App ID**
   - Navigate to Certificates, Identifiers & Profiles
   - Select Identifiers → App IDs
   - Find or create your app ID (com.yourcompany.quoteme or similar)
   - Enable "Sign In with Apple" capability
   - Save the changes

3. **Create Services ID** (for web/redirect support)
   - In Identifiers, click + to add a new identifier
   - Select "Services IDs" and continue
   - Description: "Quote Me Sign In"
   - Identifier: com.yourcompany.quoteme.signin (or similar)
   - Enable "Sign In with Apple"
   - Configure the domain and return URLs:
     - Domain: Your Cognito domain (e.g., `your-domain.auth.us-east-1.amazoncognito.com`)
     - Return URL: `https://your-domain.auth.us-east-1.amazoncognito.com/oauth2/idpresponse`
   - Save

### 2. AWS Cognito Configuration

1. **Sign in to AWS Console**
   - Go to Cognito User Pools
   - Select your user pool (should be something like `dcc-user-pool`)

2. **Add Apple as Identity Provider**
   - Go to "Sign-in experience" → "Federated identity provider sign-in"
   - Click "Add identity provider"
   - Select "Sign in with Apple"
   - Configure:
     - **Services ID**: The Services ID you created above
     - **Team ID**: Your Apple Developer Team ID (found in Apple Developer account)
     - **Key ID**: You'll need to create a Sign in with Apple key
     - **Private Key**: The private key content
   
3. **Create Apple Sign In Key** (if not already done)
   - In Apple Developer → Keys
   - Create a new key
   - Enable "Sign In with Apple"
   - Download the .p8 file (save it securely, you can only download once!)
   - Note the Key ID

4. **Update App Client Settings**
   - In Cognito, go to "App integration" → "App clients"
   - Select your app client
   - Under "Hosted UI settings":
     - Add Apple to the enabled identity providers
     - Ensure callback URLs include your app URLs
   - Save changes

### 3. iOS Project Configuration (Xcode)

1. **Open iOS project in Xcode**
   ```bash
   cd dcc_mobile/ios
   open Runner.xcworkspace
   ```

2. **Add Sign In with Apple Capability**
   - Select the Runner target
   - Go to "Signing & Capabilities" tab
   - Click "+ Capability"
   - Add "Sign In with Apple"
   - Xcode will automatically create/update the entitlements file

3. **Verify Bundle Identifier**
   - Ensure it matches what you configured in Apple Developer portal

### 4. Update AWS Infrastructure (if using SAM/CloudFormation)

If your AWS infrastructure is managed via SAM template, you may need to update it:

1. **Check aws/template.yaml**
   - Ensure Apple is listed as a supported identity provider
   - The Cognito User Pool should have Apple configuration

2. **Deploy changes**
   ```bash
   cd aws
   ./deploy.sh
   ```

### 5. Testing

1. **Run the app on iOS device/simulator**
   ```bash
   flutter run
   ```

2. **Test Sign in with Apple**
   - The button now appears on ALL platforms
   - On iOS/macOS: Native authentication flow
   - On Android/Web: Browser-based authentication via Cognito hosted UI
   - After authentication, user should be logged into the app

## Important Notes

- **Cross-Platform Support**: Sign in with Apple works on ALL platforms (iOS, Android, Web) through AWS Cognito's hosted UI
- **Web/Android Flow**: On non-Apple platforms, users are redirected to Apple's web-based authentication
- **Real Device Testing**: For best results on iOS, test on a real device with an Apple ID
- **Simulator Testing**: You can test on iOS simulator but need to be signed into iCloud
- **Email Privacy**: Apple allows users to hide their email - your app will receive a proxy email
- **First Time Only**: Apple only provides user name/email on first sign-in
- **Android/Web Experience**: Uses browser-based authentication flow, seamlessly handled by AWS Amplify

## Troubleshooting

### Button Not Appearing
- Check that the login screen is loading correctly
- Verify no build errors in Flutter

### Authentication Fails
- Verify all Apple Developer configurations
- Check Cognito identity provider settings
- Ensure Services ID and Team ID are correct
- Verify the private key is correctly configured in Cognito

### Callback Issues
- Ensure your app's URL schemes are configured correctly
- Verify Cognito callback URLs match your app configuration

## Security Considerations

- Never commit the Apple private key (.p8 file) to source control
- Store the private key securely in AWS Secrets Manager or Parameter Store
- Regularly rotate your Apple Sign In keys

## Additional Resources

- [Apple: Sign In with Apple](https://developer.apple.com/sign-in-with-apple/)
- [AWS: Cognito Apple Identity Provider](https://docs.aws.amazon.com/cognito/latest/developerguide/apple.html)
- [Flutter: Platform-specific code](https://docs.flutter.dev/development/platform-integration/platform-channels)
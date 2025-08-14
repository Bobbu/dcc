# Environment Setup Guide

This project uses environment variables to securely manage API credentials. Here's how to set up and maintain your environment configuration.

## Quick Setup

### Option 1: Automatic Setup (Recommended)
If you have AWS CLI configured and the stack is deployed:

```bash
./update_env.sh
```

This script will:
- Query your AWS CloudFormation stack for current API values
- Show you the values it found
- Ask for confirmation before updating
- Update all `.env` files with current values
- Optionally run tests to verify the setup

### Option 2: Manual Setup
1. Copy the sample files:
   ```bash
   cp tests/.env.sample tests/.env
   cp dcc_mobile/.env.sample dcc_mobile/.env
   ```

2. Edit each `.env` file with your API values:
   ```
   # tests/.env
   API_ENDPOINT=https://your-api-id.execute-api.region.amazonaws.com/prod/quote
   API_KEY=your-api-key-here
   
   # dcc_mobile/.env  
   API_ENDPOINT=https://your-api-id.execute-api.region.amazonaws.com/prod/quote
   API_KEY=your-api-key-here
   ```

## File Structure

```
dcc/
├── update_env.sh           # Automatic environment updater
├── .env.sample             # Project-wide template
├── tests/
│   ├── .env                # Test script environment (gitignored)
│   ├── .env.sample         # Template for tests
│   └── test_api.sh         # Loads from .env
└── dcc_mobile/
    ├── .env                # Flutter app environment (gitignored)
    ├── .env.sample         # Template for Flutter
    └── lib/screens/quote_screen.dart  # Uses dotenv
```

## Security Features

✅ **Git Protection**: All `.env` files are in `.gitignore`  
✅ **Sample Files**: Templates provided for easy setup  
✅ **No Hardcoded Secrets**: API keys only in environment files  
✅ **Single Source**: Update credentials in one place  
✅ **AWS Integration**: Auto-sync with deployed infrastructure  

## Usage

### Running Tests
```bash
cd tests
./test_api.sh  # Automatically loads from .env
```

### Running Flutter App
```bash
cd dcc_mobile
flutter pub get  # Install dependencies including flutter_dotenv
flutter run      # App loads API values from .env
```

### Updating Credentials

**When AWS stack is redeployed:**
```bash
./update_env.sh  # Automatically syncs with AWS
```

**When credentials change manually:**
```bash
# Edit the .env files directly
vim tests/.env
vim dcc_mobile/.env
```

## Troubleshooting

**"AWS CLI not found"**
- Install AWS CLI: `brew install awscli` (macOS) or follow [AWS docs](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

**"AWS credentials not configured"**
- Run: `aws configure`
- Enter your AWS access key, secret key, and region

**"CloudFormation stack not found"**
- Verify stack name in `update_env.sh` (default: `dcc-demo-sam-app`)
- Check if stack is deployed: `aws cloudformation list-stacks`

**".env file not found" errors**
- Run manual setup (Option 2 above)
- Or run `./update_env.sh` to create files automatically

## Benefits for Other Projects

The `update_env.sh` script is designed to be reusable across projects:

1. **Modify the configuration section** for different stack names/regions
2. **Update the ENV_FILES array** for different .env file locations  
3. **Adjust the variable names** in the update functions as needed

This approach provides a secure, maintainable way to manage API credentials across development, testing, and deployment environments.
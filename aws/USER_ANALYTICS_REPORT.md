# User Analytics Report Feature

## Overview

Automated weekly analytics reports that provide comprehensive insights into your Quote Me app's health and growth.

## What's Included

### 📊 Report Metrics

**User Metrics:**
- Total registered users
- New users this week (week-over-week)
- Confirmed vs. unconfirmed users
- Users by authentication method (Email, Google, Apple)
- User growth percentage

**Subscription Metrics:**
- Active Daily Nuggets subscribers
- New subscribers this week (week-over-week)

**Quote Metrics:**
- Total quotes in database
- Quotes added/removed this week (week-over-week)

**Tag Metrics:**
- Total tags in database
- Tags added/removed this week (week-over-week)

### 📧 Delivery

- **Schedule**: Every Monday at 8 AM UTC
- **Recipients**: All users in the "Admins" Cognito group
- **Format**: Beautiful HTML email with color-coded metrics
- **Historical**: Snapshots stored in DynamoDB for trend analysis

## Infrastructure Components

### New Resources Added:

1. **DynamoDB Table**: `quote-me-analytics-reports`
   - Stores weekly snapshots for historical comparison
   - Enables week-over-week change calculations

2. **Lambda Function**: `quote-me-user-analytics-report`
   - Queries Cognito, DynamoDB, and other services
   - Generates comprehensive metrics
   - Sends HTML email reports
   - Stores snapshots

3. **EventBridge Rule**: `user-analytics-report-weekly`
   - Triggers Lambda every Monday at 8 AM UTC
   - Can be modified for different schedules

4. **IAM Permissions**:
   - Cognito read access (list users, groups)
   - DynamoDB read access (quotes, tags, subscriptions)
   - DynamoDB write access (analytics reports table)
   - SES send email permissions

## Testing

### Manual Test (Before Weekly Schedule)

Run the test script to trigger a report immediately:

```bash
cd aws/tests
./test_user_analytics_report.sh
```

This will:
- Invoke the Lambda function manually
- Display the response
- Send the report email to admin users
- Create a snapshot in DynamoDB

### Verify SES Email Configuration

Make sure `noreply@anystupididea.com` is verified in AWS SES:

```bash
aws ses list-verified-email-addresses
```

If not verified, verify it:

```bash
aws ses verify-email-identity --email-address noreply@anystupididea.com
```

## Deployment

Deploy the updated infrastructure:

```bash
cd aws
./deploy.sh
```

This will:
- Create the new DynamoDB table
- Deploy the Lambda function
- Set up the EventBridge schedule
- Configure all permissions

## Customization Options

### Change Schedule

Edit the cron expression in `template-quote-me.yaml`:

```yaml
# Current: Every Monday at 8 AM UTC
ScheduleExpression: "cron(0 8 ? * MON *)"

# Examples:
# Daily at 8 AM:  "cron(0 8 * * ? *)"
# Every Friday:   "cron(0 8 ? * FRI *)"
# Bi-weekly:      "cron(0 8 ? * MON/2 *)"
```

### Change Recipients

By default, all users in the "Admins" Cognito group receive the report.

To add specific email addresses, modify the `FROM_EMAIL` environment variable or update the `get_admin_emails()` function in `user_analytics_report_handler.py`.

### Add More Metrics

The Lambda function is designed to be extensible. Add new metrics by:

1. Creating a new `get_*_metrics()` function
2. Adding the metrics to `current_data` dictionary
3. Updating the HTML template in `generate_html_report()`

## Monitoring

### Check Report History

View all generated reports in DynamoDB:

```bash
aws dynamodb scan --table-name quote-me-analytics-reports
```

### Check Lambda Logs

View function logs in CloudWatch:

```bash
aws logs tail /aws/lambda/quote-me-user-analytics-report --follow
```

### Verify Email Delivery

Check SES sending statistics:

```bash
aws ses get-send-statistics
```

## Email Report Preview

The email report includes:
- 📊 **Header**: Week ending date, Quote Me branding
- 👥 **User Metrics**: Total, new, confirmed/unconfirmed, auth methods
- 📬 **Subscriptions**: Active Daily Nuggets subscribers
- 💬 **Quotes**: Total count with week-over-week changes
- 🏷️ **Tags**: Total count with week-over-week changes
- **Change Indicators**:
  - ▲ Green arrow for increases
  - ▼ Red arrow for decreases
  - — Gray for no change

## Troubleshooting

### Report Not Received

1. **Check Lambda execution**: Look for errors in CloudWatch Logs
2. **Verify SES**: Ensure `noreply@anystupididea.com` is verified
3. **Check admin emails**: Verify users are in "Admins" Cognito group
4. **Manual test**: Run `./test_user_analytics_report.sh` to debug

### Week-over-Week Changes Not Showing

This is normal for the first report. After the second week, changes will appear as the system compares against the previous week's snapshot.

### Permission Errors

Re-deploy the stack to ensure all IAM permissions are correctly configured:

```bash
cd aws
./deploy.sh
```

## Future Enhancements

Potential additions:
- In-app dashboard view of reports
- Downloadable CSV exports
- Customizable alert thresholds (e.g., "notify if users decrease by 10%")
- Longer-term trend analysis (monthly, quarterly)
- User engagement metrics (quotes viewed, favorites added, etc.)

## Cost Estimate

**AWS Costs (estimated monthly):**
- Lambda: ~$0.01 (4 invocations/month, 300s timeout)
- DynamoDB: ~$0.01 (minimal storage for snapshots)
- SES: $0.10 per 1,000 emails (depends on admin count)
- EventBridge: Free

**Total: ~$0.15/month** (assuming 5 admin users)

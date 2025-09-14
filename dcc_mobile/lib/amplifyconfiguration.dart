const amplifyconfig = '''{
  "UserAgent": "aws-amplify-cli/2.0",
  "Version": "1.0",
  "auth": {
    "plugins": {
      "awsCognitoAuthPlugin": {
        "UserAgent": "aws-amplify-cli/0.1.0",
        "Version": "0.1.0",
        "IdentityManager": {
          "Default": {}
        },
        "CognitoUserPool": {
          "Default": {
            "PoolId": "us-east-1_WCJMgcwll",
            "AppClientId": "308apko2vm7tphi0c74ec209cc",
            "Region": "us-east-1"
          }
        },
        "OAuth": {
          "WebDomain": "quote-me-auth-1757704767.auth.us-east-1.amazoncognito.com",
          "AppClientId": "308apko2vm7tphi0c74ec209cc",
          "SignInRedirectURI": "https://quote-me.anystupididea.com/auth/callback,quoteme://auth-success",
          "SignOutRedirectURI": "https://quote-me.anystupididea.com/",
          "Scopes": [
            "email",
            "openid", 
            "profile"
          ]
        },
        "Auth": {
          "Default": {
            "authenticationFlowType": "USER_SRP_AUTH",
            "socialProviders": [
              "GOOGLE"
            ],
            "usernameAttributes": [
              "email"
            ],
            "signupAttributes": [
              "email"
            ],
            "passwordProtectionSettings": {
              "passwordPolicyMinLength": 8,
              "passwordPolicyCharacters": []
            },
            "mfaConfiguration": "OFF",
            "mfaTypes": [
              "SMS"
            ],
            "verificationMechanisms": [
              "email"
            ]
          }
        }
      }
    }
  }
}''';
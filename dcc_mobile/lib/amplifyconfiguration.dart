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
            "PoolId": "us-east-1_ecyuILBAu",
            "AppClientId": "2idvhvlhgbheglr0hptel5j55",
            "Region": "us-east-1"
          }
        },
        "OAuth": {
          "WebDomain": "dcc-demo-sam-app-auth.auth.us-east-1.amazoncognito.com",
          "AppClientId": "2idvhvlhgbheglr0hptel5j55",
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
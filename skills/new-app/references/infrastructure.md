# Infrastructure (AWS CloudFormation) and CI (Azure DevOps)

There is one CloudFormation template per concern, in folders by region. Most stacks live in `<region>`. CloudFront's certificate,
the web distribution and the budget live in `us-east-1`. Secrets live in SSM Parameter Store and are read with
`{{resolve:ssm:...}}` at deploy time. A changed parameter takes effect only on the next deploy of the stack that reads it.

## Contents
- [Naming rule](#naming-rule)
- [Templates and deploy order](#templates-and-deploy-order)
- [dns, params, container-images](#dns-params-container-images)
- [authentication](#authentication)
- [api](#api)
- [web](#web)
- [budget](#budget)
- [CI pipelines](#ci-pipelines)
- [Done criteria](#done-criteria)

## Naming rule

Several apps may share one AWS account. So prefix **every** account-wide name with the app:
- Stack names: `<app>-<part>`
- Export names: `<App><Thing>` (for example `<App>UserPoolId`, `<App>HostedZoneId`)
- SSM parameters: `/<app>/...`
- Lambda functions, ECR repositories, S3 buckets, the Cognito pool name and its domain prefix: `<app>-...` or `<app>`

An unprefixed export such as `UserPoolId` makes the second app's stack fail to deploy, and an unprefixed SSM path quietly
shares secrets between apps.

## Templates and deploy order

```
infrastructure/
  README.md                         # deploy commands, in order
  aws/<region>/
    <app>-dns.yml                   # hosted zone
    <app>-params.yml                # SSM parameters with placeholder values, overwritten by hand
    <app>-container-images.yml      # ECR repositories
    <app>-email.yml                 # SES identity + DNS records (required)
    <app>-storage.yml               # images bucket (required)
    <app>-authentication.yml        # Cognito
    <app>-api.yml                   # SAM: HTTP API + Lambda (container image)
    (optional modules: <app>-queue.yml, <app>-worker.yml)
  aws/us-east-1/
    <app>-web.yml                   # S3 + CloudFront + certificate
    <app>-budget.yml
```

Deploy in this order, and write it in `infrastructure/README.md` as `aws cloudformation deploy` commands
(`--capabilities CAPABILITY_IAM CAPABILITY_AUTO_EXPAND` for templates that use `Transform: AWS::Serverless-2016-10-31`):
1. `dns`. Then point the registrar's name servers at the zone, because certificates can't validate until that's done.
2. `params`. Then overwrite the placeholder values: `aws ssm put-parameter --name ... --value ... --overwrite`.
3. `container-images`. Then push a first API image. The pipeline's build stage does this, or push it by hand, because the api stack needs an `ImageUri`.
4. `email`. Wait until the SES identity shows as verified, because Cognito sends its mail through it.
5. `storage`.
6. `authentication`. Then copy the client IDs into the `/<app>/auth/*-client-id` parameters.
   If the Worker & queue module was chosen, deploy `queue` next.
7. `api` with `--parameter-overrides ImageUri=<uri>`, then `worker` if the Worker module was chosen.
8. `web` in us-east-1 with `HostedZoneId=<id>`. Exports can't be imported across regions, so it's passed as a parameter.
9. `budget`.

## dns, params, container-images

`<app>-dns.yml` contains an `AWS::Route53::HostedZone` for `<domain>` with `DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain`, and exports `<App>HostedZoneId`.

`<app>-params.yml` has one `AWS::SSM::Parameter` (`Type: String`, `Tier: Standard`) per value, each with a placeholder value that names
itself (for example `"auth.client-id"`), so a missed overwrite is obvious. Above each parameter, a comment says where its real value
comes from. Core parameters:
- `/<app>/auth/authority`: `https://cognito-idp.<region>.amazonaws.com/<userPoolId>`
- `/<app>/auth/client-id`, `/<app>/auth/android-client-id`, `/<app>/auth/ios-client-id`
- `/<app>/auth/google/client-id`, `/<app>/auth/google/client-secret`. These come from the Google Cloud "Web application" OAuth client, whose redirect URI is
  `https://<app>.auth.<region>.amazoncognito.com/oauth2/idpresponse`.
- `/<app>/auth/apple/services-id`, `/<app>/auth/apple/team-id`, `/<app>/auth/apple/key-id`, `/<app>/auth/apple/private-key`. Set the private
  key from the .p8 file with `--value file://AuthKey_<key id>.p8` so its line breaks are kept.
- `/<app>/database/connection-string`

`<app>-container-images.yml` has an `AWS::ECR::Repository` named `<app>-api` (plus `<app>-worker` with the Worker module). Give each one a repository
policy that allows `lambda.amazonaws.com` to `ecr:BatchGetImage` and `ecr:GetDownloadUrlForLayer`, and a lifecycle policy that keeps one untagged image and the
last 10 tagged images. Export `<App>ApiRepositoryUri`.

## authentication

Copy this template, substituting the placeholders. Every client needs managed login branding, because managed login v2 serves only
app clients that have a branding style.

```yaml
AWSTemplateFormatVersion: 2010-09-09
Resources:
  UserPool:
    Type: AWS::Cognito::UserPool
    Properties:
      AccountRecoverySetting:
        RecoveryMechanisms:
          - Name: verified_email
            Priority: 1
      AdminCreateUserConfig:
        AllowAdminCreateUserOnly: false
      AutoVerifiedAttributes:
        - email
      DeletionProtection: ACTIVE
      # Sent through the app's own SES identity (<app>-email.yml); Cognito's default sender is capped at 50 emails a day.
      EmailConfiguration:
        EmailSendingAccount: DEVELOPER
        From: no-reply@<domain>
        SourceArn: !Sub arn:aws:ses:${AWS::Region}:${AWS::AccountId}:identity/<domain>
      LambdaConfig:
        PreSignUp: !GetAtt FederatedSignUpFunction.Arn
      Policies:
        PasswordPolicy:
          MinimumLength: 8
          RequireLowercase: true
          RequireNumbers: true
          RequireSymbols: true
          RequireUppercase: true
      UsernameAttributes:
        - email
      UsernameConfiguration:
        CaseSensitive: false
      UserPoolName: <app>
      UserPoolTier: ESSENTIALS # required for managed login
      VerificationMessageTemplate:
        DefaultEmailOption: CONFIRM_WITH_LINK

  UserPoolDomain:
    Type: AWS::Cognito::UserPoolDomain
    Properties:
      Domain: <app>
      ManagedLoginVersion: 2 # managed login instead of classic hosted UI
      UserPoolId: !Ref UserPool

  GoogleIdentityProvider:
    Type: AWS::Cognito::UserPoolIdentityProvider
    Properties:
      AttributeMapping:
        email: email
        email_verified: email_verified
        name: name
      ProviderDetails:
        authorize_scopes: openid email profile
        client_id: '{{resolve:ssm:/<app>/auth/google/client-id}}'
        client_secret: '{{resolve:ssm:/<app>/auth/google/client-secret}}'
      ProviderName: Google
      ProviderType: Google
      UserPoolId: !Ref UserPool

  # The email may be a private relay address, so register <domain> with Apple's private email relay service.
  AppleIdentityProvider:
    Type: AWS::Cognito::UserPoolIdentityProvider
    Properties:
      AttributeMapping:
        email: email
        email_verified: email_verified
      ProviderDetails:
        authorize_scopes: email name
        client_id: '{{resolve:ssm:/<app>/auth/apple/services-id}}'
        key_id: '{{resolve:ssm:/<app>/auth/apple/key-id}}'
        private_key: '{{resolve:ssm:/<app>/auth/apple/private-key}}'
        team_id: '{{resolve:ssm:/<app>/auth/apple/team-id}}'
      ProviderName: SignInWithApple
      ProviderType: SignInWithApple
      UserPoolId: !Ref UserPool

  # Pre sign-up trigger: links a Google or Apple sign-in to the native user with the same verified email, creating
  # that native user first if there isn't one, so every sign-in method for an email shares one account and sub.
  FederatedSignUpFunction:
    Type: AWS::Lambda::Function
    Properties:
      Code:
        ZipFile: |
          const crypto = require('crypto');
          const {
            CognitoIdentityProviderClient, ListUsersCommand, AdminDeleteUserCommand, AdminCreateUserCommand,
            AdminSetUserPasswordCommand, AdminLinkProviderForUserCommand,
          } = require('@aws-sdk/client-cognito-identity-provider');

          const cognito = new CognitoIdentityProviderClient();
          // The federated username's prefix mapped to the identity provider's name.
          const providers = { google: 'Google', signinwithapple: 'SignInWithApple' };

          exports.handler = async (event) => {
            if (event.triggerSource !== 'PreSignUp_ExternalProvider') return event;

            const { email, email_verified: emailVerified } = event.request.userAttributes;
            // Only link on an email the provider has verified, or anyone could claim someone else's account.
            if (!email || String(emailVerified) !== 'true') return event;

            const separator = event.userName.indexOf('_');
            const providerName = providers[event.userName.slice(0, separator).toLowerCase()];
            if (!providerName) return event;

            const UserPoolId = event.userPoolId;
            const { Users } = await cognito.send(new ListUsersCommand({
              UserPoolId,
              Filter: `email = "${email.replace(/["\\]/g, '\\$&')}"`,
            }));
            const native = Users.find((user) => user.UserStatus !== 'EXTERNAL_PROVIDER');
            let username = native?.Username;

            if (native?.UserStatus === 'UNCONFIRMED') {
              // Never confirmed, so whoever made it may not own the email: replace it rather than link to it.
              await cognito.send(new AdminDeleteUserCommand({ UserPoolId, Username: username }));
              username = undefined;
            } else if (native && !native.Attributes.some((a) => a.Name === 'email_verified' && a.Value === 'true')) {
              return event;
            }

            if (!username) {
              const { User } = await cognito.send(new AdminCreateUserCommand({
                UserPoolId,
                Username: email,
                MessageAction: 'SUPPRESS',
                UserAttributes: [{ Name: 'email', Value: email }, { Name: 'email_verified', Value: 'true' }],
              }));
              username = User.Username;
              // A random password nobody knows; "Forgot password" can set a real one later.
              await cognito.send(new AdminSetUserPasswordCommand({
                UserPoolId,
                Username: username,
                Password: `${crypto.randomBytes(24).toString('base64')}aA1!`,
                Permanent: true,
              }));
            }

            await cognito.send(new AdminLinkProviderForUserCommand({
              UserPoolId,
              DestinationUser: { ProviderName: 'Cognito', ProviderAttributeValue: username },
              SourceUser: {
                ProviderName: providerName,
                ProviderAttributeName: 'Cognito_Subject',
                ProviderAttributeValue: event.userName.slice(separator + 1),
              },
            }));
            return event;
          };
      FunctionName: <app>-federated-sign-up
      Handler: index.handler
      MemorySize: 256
      Role: !GetAtt FederatedSignUpRole.Arn
      Runtime: nodejs24.x
      Timeout: 5 # Cognito waits at most 5 seconds for a trigger

  FederatedSignUpRole:
    Type: AWS::IAM::Role
    Properties:
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              Service: lambda.amazonaws.com
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
      Policies:
        - PolicyName: LinkFederatedUsers
          PolicyDocument:
            Version: '2012-10-17'
            Statement:
              - Effect: Allow
                Action:
                  - cognito-idp:ListUsers
                  - cognito-idp:AdminDeleteUser
                  - cognito-idp:AdminCreateUser
                  - cognito-idp:AdminSetUserPassword
                  - cognito-idp:AdminLinkProviderForUser
                # Not !GetAtt UserPool.Arn: the pool references this function, so that would be a circular dependency.
                Resource: !Sub arn:aws:cognito-idp:${AWS::Region}:${AWS::AccountId}:userpool/*

  FederatedSignUpPermission:
    Type: AWS::Lambda::Permission
    Properties:
      Action: lambda:InvokeFunction
      FunctionName: !GetAtt FederatedSignUpFunction.Arn
      Principal: cognito-idp.amazonaws.com
      SourceArn: !GetAtt UserPool.Arn
```

Then add three app clients. Each one is an `AWS::Cognito::UserPoolClient` with `DependsOn: [GoogleIdentityProvider, AppleIdentityProvider]`,
`AllowedOAuthFlows: [code]`, `AllowedOAuthFlowsUserPoolClient: true`, `AllowedOAuthScopes: [phone, email, openid, profile, aws.cognito.signin.user.admin]`,
`SupportedIdentityProviders: [COGNITO, Google, SignInWithApple]`, `RefreshTokenValidity: 30` and `GenerateSecret: false`, and each gets an
`AWS::Cognito::ManagedLoginBranding` with `UseCognitoProvidedValues: true`.

| Client | ClientName | AccessTokenValidity (hours) | CallbackURLs | LogoutURLs | Extra |
| --- | --- | --- | --- | --- | --- |
| Web | `<app>` | 1 | `http://localhost:5173/manage`, `https://<domain>/manage` | `http://localhost:5173`, `https://<domain>` | `DefaultRedirectURI: https://<domain>/manage` |
| Android | `<app>-android` | 12 | `com.<company>.<app>://callback` | `com.<company>.<app>://signout` | `EnableTokenRevocation: true` |
| iOS | `<app>-ios` | 12 | `com.<company>.<app>://callback` | `com.<company>.<app>://signout` | `EnableTokenRevocation: true` |

Export `<App>UserPoolId`, `<App>UserPoolClientId`, `<App>AndroidUserPoolClientId` and `<App>IosUserPoolClientId`.

## api

```yaml
AWSTemplateFormatVersion: 2010-09-09
Transform: AWS::Serverless-2016-10-31
Parameters:
  ImageUri:
    Type: String
    Description: ECR image URI (including tag) to deploy for the API Lambda function

Resources:
  ApiCertificate:
    Type: AWS::CertificateManager::Certificate
    Properties:
      DomainName: 'api.<domain>'
      DomainValidationOptions:
        - DomainName: 'api.<domain>'
          HostedZoneId: !ImportValue <App>HostedZoneId
      ValidationMethod: DNS

  ApiHttpApi:
    Type: AWS::Serverless::HttpApi
    Properties:
      Auth:
        Authorizers:
          OAuth2Authorizer:
            IdentitySource: $request.header.Authorization
            JwtConfiguration:
              issuer: '{{resolve:ssm:/<app>/auth/authority}}'
              # For access tokens without "aud", API Gateway checks client_id against this list.
              audience:
                - '{{resolve:ssm:/<app>/auth/client-id}}'
                - '{{resolve:ssm:/<app>/auth/android-client-id}}'
                - '{{resolve:ssm:/<app>/auth/ios-client-id}}'
        DefaultAuthorizer: OAuth2Authorizer
      CorsConfiguration:
        AllowCredentials: true
        AllowHeaders:
          - '*'
        AllowMethods: [DELETE, GET, OPTIONS, POST, PUT]
        AllowOrigins:
          - http://localhost:5173
          - https://<domain>
      Domain:
        CertificateArn: !Ref ApiCertificate
        DomainName: api.<domain>
        Route53:
          HostedZoneId: !ImportValue <App>HostedZoneId

  ApiFunction:
    Type: AWS::Serverless::Function
    Properties:
      Architectures:
        - x86_64
      Environment:
        Variables:
          Auth__Authority: '{{resolve:ssm:/<app>/auth/authority}}'
          Auth__ClientIds__0: '{{resolve:ssm:/<app>/auth/client-id}}'
          Auth__ClientIds__1: '{{resolve:ssm:/<app>/auth/android-client-id}}'
          Auth__ClientIds__2: '{{resolve:ssm:/<app>/auth/ios-client-id}}'
          Database__ConnectionString: '{{resolve:ssm:/<app>/database/connection-string}}'
          Image__Storage: 'S3'
          Image__S3BucketName: '<app>-images'
          Email__Enabled: 'true'
          Email__FromAddress: 'no-reply@<domain>'
          # Optional modules add their settings here.
      Events:
        # One event per method on /{proxy+}. A route that must work without a user token (a webhook, a link in an
        # email) gets its own, more specific event with Auth: { Authorizer: NONE }, which takes precedence.
        RootGet:
          Type: HttpApi
          Properties: { ApiId: !Ref ApiHttpApi, Method: GET, Path: '/{proxy+}' }
        RootPost:
          Type: HttpApi
          Properties: { ApiId: !Ref ApiHttpApi, Method: POST, Path: '/{proxy+}' }
        RootPut:
          Type: HttpApi
          Properties: { ApiId: !Ref ApiHttpApi, Method: PUT, Path: '/{proxy+}' }
        RootDelete:
          Type: HttpApi
          Properties: { ApiId: !Ref ApiHttpApi, Method: DELETE, Path: '/{proxy+}' }
      FunctionName: <app>-api
      ImageUri: !Ref ImageUri
      MemorySize: 512
      PackageType: Image
      Policies:
        - AWSLambdaBasicExecutionRole
        - S3CrudPolicy:
            BucketName: '<app>-images'
        - SESCrudPolicy:
            IdentityName: '<domain>'
        - Version: '2012-10-17'
          Statement:
            - Sid: CognitoUserSelfService
              Effect: Allow
              Action:
                - cognito-idp:GetUser
                # Account deletion removes the user's own sign-in with their access token.
                - cognito-idp:DeleteUser
              Resource: !Sub
                - 'arn:aws:cognito-idp:${AWS::Region}:${AWS::AccountId}:userpool/${UserPoolId}'
                - UserPoolId: !ImportValue <App>UserPoolId
      Timeout: 30
```

## web

The template lives in us-east-1 and takes a `HostedZoneId` parameter of type `AWS::Route53::HostedZone::Id`. It contains:
- an S3 bucket `<app>-web-app` with all four public access blocks enabled, and a bucket policy that allows `s3:GetObject` only to `cloudfront.amazonaws.com`, with the condition `AWS:SourceArn` = this distribution
- an `AWS::CloudFront::OriginAccessControl` (`<app>-web-oac`, s3, `SigningBehavior: always`, sigv4)
- an `AWS::CloudFront::CachePolicy` `<app>-web-cache-policy` with MinTTL 300, DefaultTTL 300 and MaxTTL 900, no cookies, headers or query strings, so deploys show up within minutes without an invalidation
- a certificate for `<domain>` with DNS validation in the hosted zone
- a distribution with alias `<domain>`, `DefaultRootObject: index.html`, `ViewerProtocolPolicy: redirect-to-https`, `TLSv1.2_2021`, `sni-only`, and the S3 origin
  using the OAC (`S3OriginConfig.OriginAccessIdentity: ''`)
- an A alias record for `<domain>` → the distribution (`HostedZoneId: Z2FDTNDATAQYW2`, which is CloudFront's fixed zone)

Add this to the distribution exactly as written:

```yaml
        # The app is a SPA, so only index.html exists in S3. Serve it with a 200 for client routes like /privacy,
        # which Google Play and App Store review fetch directly. Without s3:ListBucket, S3 answers missing keys
        # with 403 rather than 404, so both are mapped.
        CustomErrorResponses:
          - ErrorCode: 403
            ResponseCode: 200
            ResponsePagePath: /index.html
          - ErrorCode: 404
            ResponseCode: 200
            ResponsePagePath: /index.html
```

## budget

`<app>-budget.yml` (us-east-1) defines an `AWS::Budgets::Budget` with a monthly COST budget, a `BudgetLimitAmount` parameter (default 20 USD), and an
`AlertEmail` parameter. It sends an email notification when ACTUAL spend passes 80% and when FORECASTED spend passes 100%.

## CI pipelines

There are three Azure DevOps YAML files at the repo root. They're kept separate so a slow or failing mobile build never holds up the API or web deploy.
Service connections and variable groups are named `aws-<app>`, `<app>-web` and `<app>-ios`. List them in SETUP.md.

**`azure-pipelines.yaml`** triggers on `main` for the paths `api` and `web`, runs on `ubuntu-latest`, and uses the variables `configuration: Release` and `runtimeId: linux-x64`.
- `build_api`: `UseDotNet@2` (10.x), then:
  ```bash
  sln_path=$(System.DefaultWorkingDirectory)/api
  api_project=$sln_path/<Company>.<App>.Api/<Company>.<App>.Api.csproj
  artifact_path=$(Build.ArtifactStagingDirectory)/api/
  dotnet publish $api_project -c $(configuration) -r $(runtimeId) --self-contained false -p:PublishReadyToRun=true -o $artifact_path
  cd $(Build.ArtifactStagingDirectory)
  docker build --platform linux/amd64 --provenance=false --sbom=false -f $sln_path/<Company>.<App>.Api/Dockerfile -t <app>-api:$(Build.BuildNumber) --build-arg COPY_FROM=./api .
  mkdir -p $(Build.ArtifactStagingDirectory)/docker-image
  docker save <app>-api:$(Build.BuildNumber) -o $(Build.ArtifactStagingDirectory)/docker-image/<app>-api.tar
  ```
  `--provenance=false --sbom=false` matters: Lambda rejects the multi-manifest images that BuildKit makes by default. Publish the docker-image folder as artifact `<app>-api-image`.
- `deploy_api` (a deployment job, environment `production`): download the artifact, run `DockerInstaller@0`, then `docker load`, then `ECRPushImage@1` (`awsCredentials: aws-<app>`,
  repository `<app>-api`, tag `$(Build.BuildNumber)`, `outputVariable: LatestImage`), then `AWSCLI@1`:
  `lambda update-function-code --function-name <app>-api --image-uri $(LatestImage)`.
- `build_web` (depends on `build_api`, variable group `<app>-web`): `UseNode@1` (24.x), then `npm install -g corepack@latest && corepack enable`, then
  `cd web && corepack prepare --activate && yarn && yarn build`, with `env:` mapping each `VITE_*` var from the group. Copy `build/client/.` to the artifact `<app>-web`.
- `deploy_web`: `S3Upload@1` of the artifact to bucket `<app>-web-app` in us-east-1.
- With the Worker module, add `build_worker` and `deploy_worker` stages that mirror the API stages with `<app>-worker`.

**`azure-pipelines-mobile.yaml`** (Android) triggers on the path `android`. It downloads the upload keystore with `DownloadSecureFile@1`, sets
`<APP>_KEYSTORE_FILE`, `_KEYSTORE_PASSWORD`, `_KEY_ALIAS` and `_KEY_PASSWORD` from secret variables, and runs
`./gradlew --no-daemon testDebugUnitTest bundleRelease -P<app>.versionCode=$(Build.BuildId)`. It publishes the AAB, then a deployment stage runs
`GooglePlayRelease@4` to the `internal` track. The header comment lists the one-time setup: create the Play Console app, give the Google Play
service account "Release apps to testing tracks" for `com.<company>.<app>`, upload the keystore secure file, and add the variables.

**`azure-pipelines-ios.yaml`** triggers on the path `ios` with `pr: none` and runs on `macos-15`. It uses cloud-managed automatic signing with an
App Store Connect API key, so no .p12 or .mobileprovision is stored in Azure DevOps. The steps are:
1. Download the `.p8` key with `DownloadSecureFile@1` (`name: appStoreConnectKey`).
2. `brew install xcodegen && xcodegen generate`
3. `xcodebuild test -project <App>.xcodeproj -scheme <App> -destination 'platform=iOS Simulator,name=iPhone 17'`
4. `xcodebuild archive` (Release, `generic/platform=iOS`) with `-allowProvisioningUpdates -authenticationKeyPath ... -authenticationKeyID ... -authenticationKeyIssuerID ...`,
   `DEVELOPMENT_TEAM=$(appleTeamId)` and `CURRENT_PROJECT_VERSION=$(Build.BuildId)`. Then `xcodebuild -exportArchive -exportOptionsPlist ExportOptions.plist` with the same auth arguments.
5. Publish the `.ipa` and the zipped dSYMs.
6. A deployment stage copies the key to `~/.appstoreconnect/private_keys/AuthKey_<id>.p8` and runs `xcrun altool --upload-app --type ios --file ... --apiKey ... --apiIssuer ...`.

The header comment lists the one-time setup: create the App Store Connect app (TestFlight can't create it); create a team API key with the Admin role
(cloud-managed distribution certificates need Admin); upload the .p8 as a secure file; create a variable group `<app>-ios` with `appStoreConnectKeyId`; and set
`appStoreConnectIssuerId` and `appleTeamId`.

```xml
<!-- ios/ExportOptions.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- Used by azure-pipelines-ios.yaml to export the App Store Connect .ipa. The team comes from the archive. -->
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<!-- The pipeline sets the build number to the Azure DevOps build ID; don't let Xcode change it. -->
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
```

## Done criteria

- Every template is valid YAML. If the AWS CLI is available and configured, run `aws cloudformation validate-template --template-body file://...` on each one.
  Don't deploy anything.
- Every `!ImportValue` matches an export defined in a template in the same region, and every `{{resolve:ssm:...}}` path is declared in `<app>-params.yml`.
- `grep` finds no unprefixed export names or SSM paths.
- The pipeline YAML refers only to project paths, Dockerfiles and bucket and function names that exist.

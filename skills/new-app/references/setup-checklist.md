# SETUP.md template

These are the steps that need accounts, consoles, money or secrets. The agent never does them. Fill in the real names, keep only the
chosen layers and modules, and keep the order, because later steps depend on earlier ones.

## 1. Accounts and domain
- [ ] Register `<domain>`. CloudFormation can't register domains, so use Route 53 Domains or another registrar.
- [ ] Get AWS account access in `<region>` and us-east-1 (for the CloudFront certificate and the budget).
- [ ] Create a MongoDB cluster (Atlas or self-hosted) and connection strings for each environment.

## 2. Infrastructure
Follow the order in `infrastructure/README.md`. The steps that need you:
- [ ] After `<app>-dns`: point the registrar's name servers at the hosted zone.
- [ ] After `<app>-params`: overwrite every placeholder parameter under `/<app>/`.
- [ ] Push a first API image before deploying `<app>-api`.
- [ ] After `<app>-authentication`: copy the three client IDs into `/<app>/auth/*-client-id` and the authority into `/<app>/auth/authority`, then redeploy `<app>-api`.

## 3. Sign-in providers
- [ ] **Google:** in a Google Cloud project, configure the OAuth consent screen and create a "Web application" OAuth client with the redirect URI
      `https://<app>.auth.<region>.amazoncognito.com/oauth2/idpresponse`. Store its ID and secret in `/<app>/auth/google/*`.
- [ ] **Apple:** create an App ID with Sign in with Apple, a Services ID (with the domain `<app>.auth.<region>.amazoncognito.com` and the return URL `.../oauth2/idpresponse`)
      and a Sign in with Apple key. Store the services ID, team ID, key ID and the .p8 (as `file://`) in `/<app>/auth/apple/*`.

## 4. Local development
- [ ] API: `dotnet user-secrets` for `Auth:Authority`, `Auth:ClientIds:0..2`, `Auth:SecureAllEndpoints=true`, `Cors:Origins:0=http://localhost:5173`, and
      `Database:ConnectionString` (the Aspire Mongo container's connection string, from the dashboard).
- [ ] Web: copy `.env.example` to `.env.local` and fill it in.
- [ ] Android: set the `<app>.*` values in `~/.gradle/gradle.properties`, and run `adb reverse tcp:5142 tcp:5142` to reach the local API from a device or emulator.
- [ ] iOS: copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEVELOPMENT_TEAM`.

## 5. Email (required)
- [ ] After `<app>-email`: wait for the SES identity to verify. This needs the DNS delegation from step 2.
- [ ] Request SES production access. Until it's granted, the sandbox only delivers to verified addresses, and that includes Cognito's sign-up emails.
- [ ] Register `<domain>` with Apple's private email relay, so mail reaches users who hide their email with Sign in with Apple.

## 6. Optional modules (only those chosen)
- [ ] Payments: create the Stripe products and prices, add a webhook endpoint at `https://api.<domain>/stripe/webhook` with the subscription events, store the keys and price IDs in SSM,
      and configure the Billing Portal.
- [ ] AI: enable access to each Bedrock model the config names.
- [ ] Maps: create Mapbox and/or Google Places keys in SSM, and a Google Maps Android key restricted to `com.<company>.<app>` and its signing certificates.
- [ ] Report & block: set the admin email and the action secret in SSM.

## 7. Mobile stores
- [ ] Android: generate an upload keystore (keep it out of git), create the Play Console app `com.<company>.<app>`, and complete Data safety and the content rating.
- [ ] iOS: create the App Store Connect app `com.<company>.<app>`, the App Privacy answers, and an App Store Connect API key (Admin role) for CI.
- [ ] Replace the placeholder app icons and the brand color.

## 8. CI/CD (Azure DevOps)
- [ ] Create the pipelines from the three YAML files.
- [ ] Create the service connections `aws-<app>` (AWS) and the Google Play connection.
- [ ] Create the variable groups `<app>-web` (`region`, `userPoolId`, `domain`, `clientId`, `redirectUri`, `logoutUri`, `apiUrl`) and `<app>-ios` (`appStoreConnectKeyId`).
- [ ] Upload the secure files: the Android keystore and the App Store Connect .p8.

## 9. Before launch
- [ ] Have the privacy policy and terms of use reviewed and written properly. The generated ones are placeholders.
- [ ] Set the budget alert email.

# Feature checks

For each feature: where it lives, what to search for, and what counts as **present**. Search patterns are
case-insensitive regexes for ripgrep. They're starting points: read the hits, follow the calls, and search for the repo's
own names once you've found them.

- [Authentication](#authentication)
- [Account deletion](#account-deletion)
- [Block user](#block-user)
- [Report user](#report-user)
- [Terms and conditions](#terms-and-conditions)
- [Privacy policy](#privacy-policy)
- [Budget alert](#budget-alert)
- [Login with Google](#login-with-google)
- [Login with Apple](#login-with-apple)
- [Change password](#change-password)
- [Feedback](#feedback)
- [Analytics](#analytics)
- [Store rules](#store-rules)

## Authentication

**Search:**
- Providers and SDKs: `cognito|amplify|oidc|openid|oauth|AppAuth|firebase.?auth|auth0|clerk|supabase|msal|entra|next-auth|authjs|passport|IdentityUser|AddIdentity`
- API protection: `AddAuthentication|AddJwtBearer|RequireAuthorization|\[Authorize\]|Authorizer|JwtAuthorizer|authMiddleware|verifyToken|jwt\.verify`
- Clients: `signIn|sign_in|login|logIn|signOut|logout|refreshToken|accessToken|ASWebAuthenticationSession|CustomTabs`
- Infra: `AWS::Cognito::UserPool|aws_cognito_user_pool|Microsoft.AzureActiveDirectory|identity_platform`

**Present when:** users can sign up (or are provisioned), sign in and sign out on each client; the API rejects requests
without a valid token on non-public routes; tokens are refreshed or the session is renewed. Check that protection is the
default (a global policy or authorizer), not opt-in per route with routes forgotten.

**Partial examples:** sign-in exists but no sign-out; the API validates tokens but some data routes are anonymous; one
client has no sign-in at all.

## Account deletion

**Search:**
- API: `DELETE.*(users?/me|account|profile)|MapDelete.*(user|account)|deleteAccount|DeleteUser|delete_user|AdminDeleteUser|deleteUser\(`
- Clients: `delete.?account|delete my account|close account|remove account|deleteAccount|DeleteAccount`
- Web page for Play: routes or pages named `delete-account|account-deletion|data-deletion`

**Present when:**
- each client with sign-in has an in-app control to delete the account (usually under Account or Settings), with a
  confirmation step;
- the API deletes or anonymizes the user's data, **and** deletes the user from the identity provider (for example Cognito
  `AdminDeleteUser`, Firebase `deleteUser`, Auth0 Management API), so the account can't sign in again;
- with Apple login, the Apple token is revoked (`appleid.apple.com/auth/revoke`) or the user is told how to revoke it;
- the client signs out and clears local state afterwards.

Also check for a public web page or URL that explains how to request deletion without the app. Google Play requires one.

**Partial examples:** only the database row is deleted; only the identity user is deleted; deactivation without deletion;
"email us to delete" with no in-app option.

## Block user

**Applies when** users can see or interact with other users' content, profiles or messages. If they can't, mark it n/a.

**Search:**
- API: `block(ed)?.?users?|BlockedUsers|blocked_user|/blocks|blockUser|unblock`
- Clients: `Block user|Unblock|Blocked users|blockUser|onBlock`

**Present when:** a user can block another user from their content, profile or messages; blocked users' content is
filtered out of every list and feed query (not just hidden in one screen); the user can see and undo blocks; deleting an
account removes it from others' block lists.

## Report user

**Applies when** users can see other users' content, profiles or messages. Reporting content counts as long as the
report identifies the author. If no user content exists, mark it n/a.

**Search:**
- API: `/reports?|ReportRequest|reportUser|reportContent|flag(ged)?|abuse|moderation|ContentReport`
- Clients: `Report( user| post| content)?|reportReason|Flag|abuse`

**Present when:** every piece of user content (and profiles, if public) has a Report action with a reason; reports are
stored and someone is notified or has a queue to review them; there's a way to act on a report (hide or remove content,
ban the user). Automated moderation alone doesn't count, but it's worth noting.

## Terms and conditions

**Search:**
- Pages and routes: `terms|tos|terms-of-service|terms-of-use|eula|legal`
- Acceptance: `acceptTerms|TermsAcceptance|termsAccepted|termsVersion|agree to|I agree`
- Files: `TERMS*.md`, `terms.*` in web `public/` or routes, store metadata (`fastlane/metadata/**/terms*`)

**Present when:** a terms page is published (a web route or hosted URL) and every client links to it, at least from sign-up
or the account screen. Note whether users must accept the terms (and whether acceptance is versioned), but a visible link
is enough for present. A route with placeholder text like "Lorem ipsum" or "TBD" is partial.

## Privacy policy

**Search:**
- Pages and routes: `privacy|privacy-policy|data-policy`
- iOS: `PrivacyInfo.xcprivacy`, `NSPrivacy`, usage strings `NS.*UsageDescription`
- Android: Play data safety notes, `privacy` links in Compose or XML
- Consent: `cookie.?consent|consentManager|gdpr|ccpa|trackingAuthorization|ATTrackingManager`

**Present when:** a privacy policy page is published and linked from every client (sign-up or account screen) and from the
web footer. On iOS, also check that `PrivacyInfo.xcprivacy` exists and declares the data the app collects, and that
`ATTrackingManager` is used if the app tracks across apps. Placeholder text is partial.

## Budget alert

**Applies when** the repo deploys cloud resources. If there's no infrastructure and no cloud deployment, mark it n/a and
note that a budget may exist in the console (unknown).

**Search:**
- AWS: `AWS::Budgets::Budget|aws_budgets_budget|budgets\.CfnBudget|AWS/Billing|EstimatedCharges|CostAnomalyDetection|AWS::CE::AnomalyMonitor`
- Azure: `Microsoft.Consumption/budgets|azurerm_consumption_budget|costmanagement`
- GCP: `google_billing_budget|billingbudgets`
- Other: `budget|cost.?alert|spend.?alert|billing.?alarm`

**Present when:** a budget or billing alarm is defined in infrastructure as code, deployed by the pipeline, with at least one
notification (email or SNS topic with a subscriber) at a threshold below 100% or on forecast. A budget with no subscriber
is partial. If none is in code, mark it **unknown** rather than missing when the cloud account could have one set up in
the console, and tell the user where to check.

## Login with Google

**Search:**
- Identity provider config: `Google|accounts\.google\.com|SupportedIdentityProviders|identity_provider.*google|AWS::Cognito::UserPoolIdentityProvider`
- SDKs: `GoogleSignIn|google-signin|@react-oauth/google|play-services-auth|credentials-play-services|GetGoogleIdOption|GIDSignIn|signInWithPopup.*Google|GoogleAuthProvider`
- Hosted UI: `identity_provider=Google|identityProvider.*Google`
- Secrets: `GOOGLE_CLIENT_ID|GoogleClientId|google.*client.?id`

**Present when:** Google is configured as an identity provider (or the app integrates Google Sign-In directly) and each
client that has sign-in offers it, either through its own button or through the hosted sign-in page it opens. The client
ID and secret come from configuration or a secret store, not hard-coded. Mark a client partial if it can't reach Google
sign-in.

## Login with Apple

**Search:**
- Identity provider config: `SignInWithApple|appleid\.apple\.com|AWS::Cognito::UserPoolIdentityProvider.*Apple|ProviderName:\s*SignInWithApple`
- iOS: `AuthenticationServices|ASAuthorizationAppleIDProvider|SignInWithAppleButton|com\.apple\.developer\.applesignin`
- Other clients: `apple.?sign.?in|signInWithApple|AppleAuthProvider|identity_provider=SignInWithApple`

**Present when:** Apple is configured as an identity provider (or integrated directly) and offered on iOS, plus any other
client that offers Google login. On iOS, check that the entitlement `com.apple.developer.applesignin` is set if the app
uses the native `AuthenticationServices` flow. Through a hosted web page it isn't needed.

## Change password

**Applies when** users can sign in with a password. If sign-in is only social or passwordless, mark it n/a.

**Search:**
- `changePassword|ChangePassword|change_password|updatePassword|ChangePasswordCommand|currentPassword|oldPassword|newPassword`
- Reset (separate, still note it): `forgotPassword|ForgotPassword|resetPassword|ConfirmForgotPassword|sendPasswordResetEmail`

**Present when:** a signed-in user can change their password from the account or settings screen (by entering the current
and new password, or by a provider flow that does the same), on each client or through a shared web page the clients open.
Forgot-password alone is partial: note it, because it's how users of hosted sign-in pages usually change passwords, and say
whether the clients link to it.

## Feedback

**Search:**
- API: `/feedback|FeedbackRequest|SubmitFeedback|feedback_submissions?`
- Clients: `Send feedback|Give feedback|Contact (us|support)|feedback|mailto:|SKStoreReviewController|requestReview|ReviewManager|in-app review`
- SDKs: `instabug|sentry.*(feedback|userFeedback)|zendesk|intercom|crisp|canny|userback|hotjar`

**Present when:** users can send feedback from inside each client: a form that reaches the team (API, email, or a support
tool), or a support SDK. A `mailto:` link counts. App-store review prompts alone are partial: they collect ratings, not
feedback the team can act on.

## Analytics

**Search:**
- SDKs: `firebase.?analytics|FirebaseAnalytics|logEvent|amplitude|mixpanel|segment|posthog|plausible|umami|gtag|google-analytics|googletagmanager|@vercel/analytics|appcenter|aws-amplify.*analytics|pinpoint|clarity|datadogRum|newrelic|heap`
- Event helpers: `trackEvent|track\(|analytics\.(track|log|capture)|logScreenView`
- Server side: `ApplicationInsights|TelemetryClient|CloudWatch.*Metric|PutMetricData|EmbeddedMetricFormat`

**Present when:** a product analytics tool is initialized on each client and records at least screen views or key events.
Server metrics and crash reporting alone are partial: they show health, not product usage. Note whether analytics waits
for consent where needed (web cookie consent, iOS App Tracking Transparency), and whether the privacy policy and
`PrivacyInfo.xcprivacy` mention it.

## Store rules

Apply these after the checks. A rule that fails is a **store blocker** in the report. Only apply rules for the stores the
repo ships to: an iOS app means the App Store, an Android app means Google Play.

| Rule | Store | Blocker when |
| --- | --- | --- |
| Account deletion in the app (guideline 5.1.1(v)) | App Store | The iOS app has account creation but no in-app deletion that deletes the account, not just deactivates it |
| Account deletion in the app and on the web | Google Play | The Android app has account creation but no in-app deletion, or there's no web URL where users can request deletion |
| Sign in with Apple, or an equivalent privacy-focused login (guideline 4.8) | App Store | The iOS app offers Google or another third-party login but no Apple login or equivalent |
| Report and block for user content (guideline 1.2) | App Store, Google Play | Users see each other's content and there's no way to report it or block the user |
| Privacy policy link in the app and the store listing | App Store, Google Play | Either app has no privacy policy link. The store listing itself is unknown: tell the user to check it |
| Privacy manifest | App Store | The iOS app has no `PrivacyInfo.xcprivacy`, or uses required-reason APIs without declaring them |

Store rules change. If you can check the current App Store Review Guidelines or Play policy, do; otherwise say the rules
are as of the skill's writing.

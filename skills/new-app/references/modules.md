# Modules

Each module touches several layers. Add its parts while you build each layer, not at the end. Each section below lists what the
module adds per layer and the specific details that have caused real failures. Write ordinary code following the
conventions in the layer references. Exact snippets appear only where getting a detail wrong breaks something.

Every module that stores user data also adds a step to `AccountDeletionService` (see `api.md`).

| Module | Kind | Notes |
| --- | --- | --- |
| [Email (SES)](#email-ses) | **Required** | Always built. Cognito also sends its mail through it |
| [Images (S3)](#images-s3) | **Required** | Always built. The profile feature uses it for a profile photo |
| [AI (Bedrock)](#ai-bedrock) | Optional | Builds on Images for image analysis and moderation |
| [Maps & geocoding](#maps--geocoding) | Optional | |
| [Worker & queue (SQS)](#worker--queue-sqs) | Optional | |
| [Payments (Stripe)](#payments-stripe) | Optional | |
| [Report & block](#report--block) | Optional | Builds on Email for the admin notices. Recommend it when users see each other's content |

Build an optional module only if the user picked it in the module question (see `SKILL.md`).

# Required modules

## Email (SES)

- **API:** `IEmailNotificationService` in Domain, implemented as `SesEmailNotificationService` (`AWSSDK.SimpleEmailV2 4.0.105.1`). Register it with
  `AddAWSService<IAmazonSimpleEmailServiceV2>()` and `AddEmailNotificationService(configuration)`. `EmailConfig` (section `Email`) has `FromAddress`
  (`no-reply@<domain>`) and `Enabled`. With `Enabled = false`, the service only logs messages, which keeps local dev free of SES.
- **Core usage:** `UserService.LogUserAsync` sends a short welcome email the first time a user signs up, if the email is known. Wrap it in a try/catch
  that only logs, so an email outage never blocks sign-in. This is transactional, so it carries no unsubscribe link. Write tests for both the sent and the failed case.
- **Unsubscribe (build it with the first non-transactional email, such as a digest or alert, not before):** every non-transactional email carries a signed link (`HmacUnsubscribeTokenProvider`, HMAC-SHA256 over the user's PublicId, with the secret in
  `/<app>/email/unsubscribe-secret`). `GET /notifications/unsubscribe` shows a confirmation page, and `POST` to the same URL unsubscribes,
  which is what mail clients' one-click unsubscribe sends. Both routes need `Auth: { Authorizer: NONE }` events in `<app>-api.yml`,
  because the token identifies the user, not a sign-in.
- **Infra:** `<app>-email.yml` contains an `AWS::SES::EmailIdentity` for `<domain>` with `MailFromDomain: mail.<domain>`, so bounces come back to your domain and SPF passes.
  Add a `RecordSetGroup` with the three DKIM CNAMEs (`DkimDNSTokenName1..3` / `Value1..3`), an apex TXT `"v=spf1 include:amazonses.com ~all"`
  (Apple's private relay checks it, and Route 53 allows one TXT set per name, so any other apex TXT goes in the same set), an MX record for `mail.<domain>`
  pointing to `10 feedback-smtp.<region>.amazonses.com`, a TXT SPF record for `mail.<domain>`, and `_dmarc.<domain>` with `"v=DMARC1; p=none"`.
  Switch the Cognito user pool to `EmailSendingAccount: DEVELOPER` (see `infrastructure.md`). Give the API the `SESCrudPolicy` for the identity.
- **Setup:** request SES production access to leave the sandbox, and register `<domain>` with Apple's private email relay, since Sign in with Apple is always on.

## Images (S3)

- **API:** `IImageFileRepository` with two implementations: `S3ImageFileRepository` and `FileSystemImageFileRepository` (for local dev). `ImageConfig` (section `Image`)
  has `Storage` (an `ImageStorage` enum: `S3` or `FileSystem`), `S3BucketName` and `FileSystemPath`. `AddImageService` picks the implementation from config.
  An `Image` entity records owner, content type and `StoredFilepath`. Uploads are multipart (`IFormFile`). Validate the content type and size, and resize on the client.
  Downloads go through the API, which checks access, so the bucket stays private. `FileSystem` is the Development default, so local dev needs no AWS.
- **Core usage, a profile photo:** `User` gets `PhotoImageId`. `PUT /users/me/photo` (multipart) stores a new image and deletes the previous one.
  `DELETE /users/me/photo` removes it. `GET /images/{publicId}` streams an image the caller may see. `UserResponse` gets `PhotoUrl` (null when there's no photo).
  Every client's profile screen shows the photo with Change and Remove actions, and the web layout's account menu shows it as the avatar.
  This is the pattern for every later feature that stores images.
- **Uploads in minimal APIs:** an endpoint that binds `IFormFile` gets antiforgery validation by default, which fails for bearer-token
  clients. End the mapping with `.DisableAntiforgery()` and add a comment saying why. Endpoints catch `ArgumentException` from the
  image validation and return `BadRequest(message)`.
- **Clients can't use a plain image URL**, because the bearer token is required. The web fetches a blob and uses an object URL
  (see `web.md`). Android uses a Coil `ImageLoader` built on the authenticated `OkHttpClient`. iOS uses an `APIClient` method that
  returns a `UIImage`.
- **Web:** resize to a maximum edge and re-encode as JPEG in the browser before upload (`utils/resize-image.ts`).
- **Android:** a camera capture through `FileProvider` (`${applicationId}.fileprovider`, `res/xml/file_paths.xml`), plus the photo picker.
  Read EXIF orientation (`androidx.exifinterface`) before resizing. Use Coil 3 (`coil-compose` and `coil-network-okhttp`, sharing the authenticated `OkHttpClient`) to load images.
- **iOS:** `PhotosPicker` and a camera sheet, a `MultipartForm` builder for uploads, and an `ImageLoader` that adds the bearer token. Add `NSCameraUsageDescription`.
- **Infra:** `<app>-storage.yml` contains a private bucket `<app>-images` with all public access blocks and SSE AES256. Give the API `S3CrudPolicy`, and set `Image__Storage: S3` and `Image__S3BucketName`.
- **Deletion:** delete the files, then the image records.

# Optional modules

Build each of these only if the user picked it.

## AI (Bedrock)

- **API:** `AWSSDK.BedrockRuntime 4.0.0.11`, registered with `AddAWSService<IAmazonBedrockRuntime>()`. `BedrockConfig` has `ModelId`, `PaidModelId` and `MaxTokens`.
  Use the Converse API with an image content block for image analysis. Moderation services (`IImageModerationService` and `ITextModerationService`) return
  allow or block with a reason. `ModerationConfig` has `Enabled` and `ModelId`, and `Enabled = false` skips moderation entirely in local dev.
- Use the cross-region inference profile IDs (for example `us.amazon.nova-lite-v1:0`). **IAM:** the `us.*` profiles route to other regions, so allow the foundation model
  ARN in any region, and allow the profile ARN in your region:
  ```yaml
  Resource:
    - 'arn:aws:bedrock:*::foundation-model/amazon.nova-lite-v1:0'
    - !Sub 'arn:aws:bedrock:${AWS::Region}:${AWS::AccountId}:inference-profile/us.amazon.nova-lite-v1:0'
  ```
  The actions are `bedrock:InvokeModel` and `bedrock:InvokeModelWithResponseStream`.
- **Setup:** enable model access for each model in the Bedrock console.

## Maps & geocoding

- **API:** a `GeoPoint` value type (latitude and longitude, validated to ±90 and ±180) with a custom BSON serializer to GeoJSON, plus a `2dsphere` index for each geo-queried
  collection. Store user locations **coarsely** (`GeoPoint.CreateCoarse` rounds them) and never return another user's exact location.
  `IGeocodingService` has `MapboxGeocodingService` and `GooglePlacesGeocodingService` implementations, selected by `Geocoding:Provider`. Keys live in SSM.
  `GET /geocoding/search` and `GET /geocoding/places/{placeId}` proxy the provider, so keys never reach the clients.
- **Web:** Leaflet (`leaflet ^1.9.4`, `react-leaflet ^5.0.0`, `@types/leaflet`). Import `leaflet/dist/leaflet.css` in `root.tsx`, and render maps only on the client.
- **Android:** `maps-compose 9.0.1`. In `build.gradle.kts`, set `manifestPlaceholders["mapsApiKey"] = <app>Property("mapsApiKey")`, and add
  `<meta-data android:name="com.google.android.geo.API_KEY" android:value="${mapsApiKey}" />` to the manifest.
  Leave `<app>.mapsApiKey=` empty in `gradle.properties`, with a comment telling people to set it in `~/.gradle/gradle.properties`, restricted to the package and signing certificates.
  Add the `ACCESS_COARSE_LOCATION` and `ACCESS_FINE_LOCATION` permissions and `uses-feature android.hardware.location required=false`.
- **iOS:** MapKit and Core Location, through a `LocationProvider` that wraps `CLLocationManager`, plus `NSLocationWhenInUseUsageDescription`.

## Worker & queue (SQS)

- **API:** `AWSSDK.SQS 4.0.100.14`. Producers implement a Domain interface (`I<Thing>Queue`). For local dev, Program.cs swaps in an emulator:
  ```csharp
  // Local dev (AppHost) points this at a local SQS-compatible emulator; everything else still uses real AWS.
  var localSqsServiceUrl = builder.Configuration["Sqs:LocalServiceUrl"];
  if (builder.Environment.IsDevelopment() && !string.IsNullOrWhiteSpace(localSqsServiceUrl))
  {
      builder.Services.AddSingleton<IAmazonSQS>(new AmazonSQSClient(new AmazonSQSConfig { ServiceURL = localSqsServiceUrl }));
  }
  else
  {
      builder.Services.AddAWSService<IAmazonSQS>();
  }
  ```
- **Worker project** (`<Company>.<App>.Worker`, an Exe with `PublishReadyToRun`): `Amazon.Lambda.Core 3.3.0`, `Amazon.Lambda.RuntimeSupport 2.2.2`,
  `Amazon.Lambda.Serialization.SystemTextJson 3.0.1`, `Amazon.Lambda.SQSEvents 3.0.1`, and Microsoft.Extensions Configuration.EnvironmentVariables, Configuration.UserSecrets,
  DependencyInjection and Logging.Console `10.0.12`. It's a top-level program with no host builder, so configure it by hand: add user secrets only in Development, then environment
  variables, then build a `ServiceCollection` with the same `AddDatabaseService`, repositories and services the API uses, then `EnsureDatabaseIndexes()`.
  - The handler returns `SQSBatchResponse` and adds each failed record to `BatchItemFailures`, so only failures are retried. Messages are delivered at least once,
    so make processing idempotent. A unique index on whatever the message creates is the simplest way.
  - `Amazon.Lambda.RuntimeSupport` only works inside Lambda. When `DOTNET_ENVIRONMENT=Development`, skip it and long-poll the queue directly, running the same
    per-message function. Otherwise call `LambdaBootstrapBuilder.Create(HandlerAsync, new DefaultLambdaJsonSerializer()).Build().RunAsync()`.
  - Dockerfile: the same as the API's, with `CMD ["<Company>.<App>.Worker.dll"]`.
- **AppHost:** add an ElasticMQ container with `elasticmq.conf` bind-mounted read-only and an endpoint on 9324, then pass `Sqs__LocalServiceUrl` and the queue URL to the API and the worker:
  ```csharp
  var elasticMq = builder.AddContainer("sqs", "softwaremill/elasticmq-native")
      .WithBindMount("elasticmq.conf", "/opt/elasticmq.conf", isReadOnly: true)
      .WithHttpEndpoint(port: 9324, targetPort: 9324, name: "sqs")
      .WithLifetime(ContainerLifetime.Persistent);
  ```
  `elasticmq.conf` sets `node-address` to http on `*:9324`, `rest-sqs` to enabled on `0.0.0.0:9324` with `sqs-limits = strict`, and predefines `<app>-<name>-queue`
  (visibility 60 seconds, with `deadLettersQueue { name = "<app>-<name>-dlq", maxReceiveCount = 3 }`) and the DLQ.
- **Infra:** `<app>-queue.yml` contains the queue (`VisibilityTimeout` ≥ the worker's Lambda timeout, and a redrive policy with `maxReceiveCount: 3`) and a DLQ with 14 days of retention.
  It exports `<App><Name>QueueUrl` and `<App><Name>QueueArn`. `<app>-worker.yml` (SAM) contains the image function `<app>-worker` with an SQS event
  (`FunctionResponseTypes: [ReportBatchItemFailures]`). Give the API `sqs:SendMessage` on the queue ARN. Add a worker ECR repository and pipeline stages.
- **Scheduled jobs:** build a second function from the same image, select it with a `Worker:Mode` env var, and trigger it on a `Schedule` event. Locally, run it on a `PeriodicTimer`.
  **Account quota:** new accounts have a low Lambda concurrency limit, so don't set `ReservedConcurrentExecutions` without first checking that the quota allows it.

## Payments (Stripe)

- **API:** `Stripe.net 53.0.0`. `IPaymentGatewayService` is implemented by `StripePaymentGatewayService`. `StripeConfig` has `SecretKey`, `WebhookSecret`, one price ID per paid plan, and `AppBaseUrl`.
  `User` gets `Plan` (a `PlanType` enum, default `Free`), `PaymentCustomerId` and `Subscription`, written only through a dedicated `UpdateBillingAsync` repository method.
  - Create the Stripe customer in `POST /users` inside a try/catch that only logs. A payment outage shouldn't block sign-in, and the customer gets created on a later login or at checkout.
  - Index: a unique index on `PaymentCustomerId` with a **partial** filter (`Filter.Type(d => d.PaymentCustomerId, BsonType.String)`), because users without a customer store an explicit
    null, and a sparse unique index would still treat those as duplicates.
  - `POST /subscriptions/checkout?plan=` and `POST /subscriptions/portal` return `RedirectResponse { Url }` for Stripe Checkout and the Billing Portal.
  - `POST /stripe/webhook` reads the raw body, verifies the `Stripe-Signature` header with `EventUtility.ConstructEvent`, and returns 400 on an `InvalidWebhookSignatureException`.
    It updates the plan from subscription events. It needs its own event with `Auth: { Authorizer: NONE }` in `<app>-api.yml`.
  - Plan limits throw `PlanLimitExceededException`, which endpoints turn into a 403 with a message that tells the user to upgrade.
  - Account deletion deletes the Stripe customer **first**, so a deleted account can never be charged again.
- **Web:** a public `/plans` page comparing plans, and `/manage/billing` showing the current plan with Upgrade (Checkout) and Manage (Portal) buttons that redirect to the returned URL.
- **Mobile:** a Billing screen that opens the web billing page in a Custom Tab or Safari. The apps never sell anything in-app. Note in SETUP.md that App Store review may require the
  external-purchase link entitlement or StoreKit instead.

## Report & block

App stores require this for apps where users see each other's content.
- **API:** `POST /reports` (`ReportRequest { ContentKind, ContentId, Reason, Details? }`) stores a `Report`. A unique index on (ContentKind, ContentId, ReporterUserId) means reporting again
  updates the existing report. The API emails the admin (`Reports:AdminEmail`) with signed **Hide** / **Keep visible** links (`HmacReportActionTokenProvider`, secret in SSM).
  `GET /reports/action` shows a confirmation page and `POST` applies the action, and both routes need `Authorizer: NONE` events. Content is hidden automatically once
  `Reports:AutoHideThreshold` distinct reporters have reported it. `IContentLookup` resolves a ContentKind and ID to the content and its author. Each feature registers its kinds there.
- **Block:** `PUT /users/me/blocks/{userPublicId}` and `DELETE` on the same route, plus `GET /users/me/blocks`. `User.BlockedUsers` is a list of user IDs and dates, and every list query
  filters out blocked authors. Return null instead of an empty list when nobody is blocked, so queries skip the filter.
- **Clients:** an overflow menu on every piece of user content, with Report (a reason picker) and Block user (with a confirmation), plus a Blocked users list in Account where users can unblock.
- **Deletion:** delete the user's reports and remove them from everyone's block lists.

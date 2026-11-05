# Manual review checklists

Use these when no scanner covers an area, and to verify scanner findings and cover what scanners miss. Grep finds
candidates. Reading the surrounding code decides whether they're findings.

Contents:
- [Severity](#severity)
- [Secrets](#secrets)
- [Dockerfiles](#dockerfiles)
- [Infrastructure as code](#infrastructure-as-code)
- [CI/CD](#cicd)
- [Code: server and API](#code-server-and-api)
- [Code: web clients](#code-web-clients)
- [Code: mobile clients](#code-mobile-clients)

## Severity

| Severity | Typical examples |
| --- | --- |
| critical | A live production credential in the repo or its history. Remote code execution or SQL/NoSQL injection reachable without auth. An auth bypass. A publicly readable or writable data store holding user data. |
| high | IDOR or missing authorization on user data. A high/critical CVE in a runtime dependency on a reachable path. A CI path that lets a fork PR run with secrets. Wildcard IAM on a production role. Disabled TLS certificate validation. |
| medium | A CVE with mitigating context. A missing rate limit on auth endpoints. Over-broad CORS. Containers running as root. Unpinned third-party CI actions. Unencrypted data at rest. Tokens stored without platform protection on mobile. |
| low | Defense-in-depth gaps: missing security headers, verbose errors, `latest` image tags, a dev-only dependency CVE. |
| info | Hardening suggestions with no current exposure. |

Move a finding **down** when it isn't reachable: dev or test-only code, a function that's never called, an input that isn't
attacker-controlled, or a control in front of it that you've verified. Move it **up** when it's internet-facing,
unauthenticated, touches user data or money, or is easy to exploit. Say why when you change a scanner's severity.

## Secrets

Grep these patterns (case-sensitive unless noted), skipping lock files and vendored folders:

| Kind | Pattern |
| --- | --- |
| Private keys | `-----BEGIN [A-Z ]*PRIVATE KEY-----` |
| AWS | `AKIA[0-9A-Z]{16}`, `ASIA[0-9A-Z]{16}`, `aws_secret_access_key` |
| GitHub | `ghp_`, `gho_`, `ghs_`, `ghu_`, `github_pat_` |
| Azure | `AccountKey=`, `SharedAccessSignature=`, `sig=` in URLs, `DefaultEndpointsProtocol=` |
| Google | `AIza[0-9A-Za-z_-]{35}`, `"type": "service_account"` |
| Slack / Stripe / Twilio / SendGrid | `xox[baprs]-`, `sk_live_`, `rk_live_`, `SK[0-9a-f]{32}`, `SG\.` |
| Azure DevOps / npm / NuGet tokens | `_authToken=`, `//registry.*:_auth`, `<add key="ClearTextPassword"` |
| JWTs | `eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.` |
| Connection strings | `mongodb(\+srv)?://[^:/\s]+:[^@\s]+@`, `postgres(ql)?://[^:]+:[^@]+@`, `Password=` / `Pwd=` in `*.json`, `*.config`, `*.yml`, `*.env` (case-insensitive) |
| Generic | `(secret|token|password|passwd|api[_-]?key|client[_-]?secret)\s*[:=]\s*["'][^"'\s]{8,}` (case-insensitive) |

Then check:
- Committed files that should never be in git: `.env` (except `.env.example` with placeholder values), `*.pem`, `*.key`,
  `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `*.mobileprovision`, `local.properties`, `appsettings.*.json` with real values,
  `terraform.tfstate` (contains secrets in plain text), `*.tfvars` with credentials, `kubeconfig`, `.npmrc`/`nuget.config`
  with tokens.
- `.gitignore` covers these patterns, so the problem doesn't come back.
- With `--history`: `git log --all --diff-filter=D --name-only --format=` lists deleted files. Look for the names above. For
  a specific known secret, `git log --all -S '<first 8 chars>' --oneline` shows when it was introduced. Don't print the
  matching lines.

Not secrets, so don't report these as leaks: Firebase/Google API keys in `google-services.json` or
`GoogleService-Info.plist` (they identify the project, so check that their API restrictions are set instead), Cognito user
pool IDs and app client IDs without a secret, publishable Stripe keys (`pk_`), and obvious placeholders (`changeme`,
`xxx`, `<your-key>`, test fixtures).

## Dockerfiles

- Runs as root: no `USER` instruction, or `USER root` at the end.
- Secrets in `ARG`/`ENV`, or copied in and deleted in a later layer (they're still in the image). Use `RUN --mount=type=secret`.
- `ADD <url>` or `curl … | sh` without a checksum check.
- `COPY . .` without a `.dockerignore` that excludes `.git`, `.env*`, keys and `node_modules`.
- Base image with no tag or with `latest`. Base image whose OS or runtime is end of life.
- Build tools, package caches or SDKs left in the final stage, where a multi-stage build would leave them out.
- `EXPOSE` of admin or debug ports, and debug flags enabled (`ASPNETCORE_ENVIRONMENT=Development`, `NODE_ENV` unset).

## Infrastructure as code

The checks below are written for CloudFormation and SAM. Map them to the equivalent resources in Terraform, Bicep or
Kubernetes.

- **Storage:** S3 buckets without `PublicAccessBlockConfiguration` (all four true), bucket policies with `"Principal": "*"`
  and no condition, no encryption, no `aws:SecureTransport` deny. CloudFront origins that reach S3 without OAC.
- **Network:** security group ingress `0.0.0.0/0` or `::/0` on anything but 80/443 (especially 22, 3389, database ports).
  `PubliclyAccessible: true` on RDS or DocumentDB. Databases in public subnets.
- **IAM:** `Action: "*"`, `Resource: "*"` with write actions, `iam:PassRole` on `*`, trust policies open to any principal or
  any account, long-lived IAM users with access keys created in the template.
- **Compute and endpoints:** Lambda function URLs with `AuthType: NONE`. API Gateway routes without an authorizer that aren't
  meant to be public. Lambda environment variables holding secrets in plain text (they should be Secrets Manager or SSM
  references).
- **Identity:** Cognito with a weak password policy, self sign-up where it isn't wanted, `PreventUserExistenceErrors`
  not `ENABLED`, OAuth callback URLs with `http://` (other than localhost) or wildcards, and refresh tokens that are very
  long-lived.
- **Web edge:** CloudFront `ViewerProtocolPolicy: allow-all`, `MinimumProtocolVersion` below TLSv1.2, no response-headers
  policy (HSTS, CSP, X-Content-Type-Options), CORS `AllowOrigins: '*'` together with credentials.
- **Data:** encryption at rest off for RDS, DynamoDB, EBS, SQS, SNS and logs. KMS key rotation off. Backups or PITR off for
  user data. `DeletionPolicy` missing on data stores (an availability risk, so `low`).
- **Parameters:** secrets as `Default:` values, or parameters without `NoEcho: true`. Outputs that export secrets.
- **Logging:** CloudTrail, access logs and API Gateway logs off. Log groups without retention (cost, so `info`).
- **Kubernetes:** `privileged: true`, `allowPrivilegeEscalation` not false, `runAsNonRoot` not true, `hostPath`,
  `hostNetwork`, no resource limits, `Secret` manifests with real values in git, and `ClusterRoleBinding` to `cluster-admin`.

## CI/CD

GitHub Actions:
- `pull_request_target` or `workflow_run` workflows that check out or run PR code (`ref: ${{ github.event.pull_request.head.sha }}`)
  with secrets or write tokens available.
- Script injection: `${{ github.event.* }}` (titles, bodies, branch names, commit messages), `${{ github.head_ref }}` or
  step outputs derived from them, used directly inside `run:` or `script:`. Pass them through `env:` instead.
- No top-level `permissions:`, or `write-all`. Each job should have the least it needs.
- Third-party actions pinned to a tag or branch rather than a full commit SHA. First-party `actions/*` on a major tag is
  usually acceptable, so report it as `low`.
- `actions/checkout` without `persist-credentials: false` in jobs that later run untrusted code or upload the workspace.
- Secrets echoed or passed as command-line arguments. `ACTIONS_STEP_DEBUG` left on.
- Self-hosted runners used by a public repo.

Azure Pipelines:
- Secrets defined as plain `variables:` in YAML instead of secret variables, a variable group or Key Vault.
- PR validation for forks with **Make secrets available to builds of forks** on (check the pipeline settings; note it as
  `needs review` because it isn't in the YAML).
- `$(…)` macros of user-controlled values such as `Build.SourceBranchName`, `System.PullRequest.SourceBranch` or commit
  messages inside `script:`/`bash:`/`powershell:` bodies. Map them to `env:` and quote them.
- `checkout: self` with `persistCredentials: true` in jobs that run untrusted code.
- Templates or `resources.repositories` referenced by branch rather than a protected ref or tag.
- Service connections with subscription-wide or admin scope used by PR builds. Deployments to production without an
  environment approval check (note as `needs review`).

All systems: build or deploy scripts that download and execute remote code without verifying it, and artifacts or caches
shared between untrusted and trusted jobs.

## Code: server and API

Start from the entry points found in the inventory, then follow the data.

- **Access control (always review by hand):** every route has authentication unless it's meant to be public (ASP.NET:
  `RequireAuthorization()`, a fallback policy, or `[Authorize]`; look for `AllowAnonymous`). Every read, update or delete
  of a user-owned record is filtered by the caller's identity from the validated token, never by a user ID from the
  request body, query or route (IDOR). Admin operations check a role or claim.
- **Token validation:** JWT issuer, audience, lifetime and signature are validated (`ValidateIssuer = false`,
  `ValidateAudience = false`, `RequireHttpsMetadata = false` outside development, `alg: none` accepted, `jwt.decode`
  without verify). Cognito: the token's `token_use` and `client_id`/`aud` are checked.
- **Injection:**
  - SQL built by string concatenation or interpolation (`FromSqlRaw($"…")`, `"SELECT … " + x`).
  - MongoDB filters built from raw request JSON (`BsonDocument.Parse(userInput)`, `$where`, `$regex` from input without
    escaping, and operator injection when a field can be an object such as `{"$ne": null}`).
  - Shell commands (`Process.Start` with concatenated args, `child_process.exec`, `subprocess(..., shell=True)`).
  - Template rendering of user input. LDAP and XPath queries.
- **Server-side request forgery:** the server fetches user-supplied URLs (webhooks, image URLs, imports) without an
  allowlist and without blocking private, link-local and metadata addresses (`169.254.169.254`).
- **Files:** path traversal (user input in a file path without normalizing it and checking the base directory). Uploads
  without size, type and content checks. Pre-signed S3 URLs with user-chosen keys, long expiry or no content-type limit.
- **Deserialization:** `BinaryFormatter`, `TypeNameHandling` other than `None`, `pickle`/`yaml.load` (not `safe_load`) on
  untrusted data, Java `ObjectInputStream`.
- **Crypto:** MD5 or SHA-1 for passwords or signatures, password hashing other than bcrypt/scrypt/Argon2/PBKDF2 with a high
  iteration count, ECB mode, static or reused IVs, hard-coded keys, `Random`/`Math.random` for tokens or codes.
- **TLS:** certificate validation turned off (`ServerCertificateCustomValidationCallback` returning `true`,
  `rejectUnauthorized: false`, `NODE_TLS_REJECT_UNAUTHORIZED=0`, `verify=False`, `InsecureSkipVerify: true`).
- **CORS and headers:** `AllowAnyOrigin` or reflected origins together with `AllowCredentials`. No HSTS in production.
- **Abuse:** no rate limiting on sign-in, sign-up, password reset, code verification or expensive endpoints. Unbounded
  page sizes or query limits.
- **Errors and logs:** stack traces or exception messages returned to clients in production. Tokens, passwords or full
  personal data written to logs.
- **Redirects:** `returnUrl`/`redirect_uri` used without checking it against an allowlist (open redirect).
- **Account lifecycle:** account deletion that leaves the user's data in other stores. Email change without
  re-verification.

## Code: web clients

- `dangerouslySetInnerHTML`, `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `document.write`, `v-html`, `bypassSecurityTrust*`
  with data that isn't sanitized (DOMPurify or similar).
- `eval`, `new Function`, `setTimeout(string)` with dynamic input.
- `href`/`src` built from user input without blocking `javascript:` URLs.
- Tokens: access or refresh tokens in `localStorage` are readable by any XSS. Note it as `medium` unless the app has a strong
  CSP. OAuth without PKCE or `state`. Implicit flow.
- Secrets in client bundles: anything in `VITE_*`, `NEXT_PUBLIC_*` or `REACT_APP_*` environment variables, or in the
  shipped config, is public. Report a real secret there as `high`.
- No Content-Security-Policy, or one with `unsafe-inline`/`unsafe-eval` for scripts. Missing `frame-ancestors`
  (clickjacking).
- `postMessage` listeners that don't check `event.origin`.
- Source maps published to production (`low`).

## Code: mobile clients

Android:
- `AndroidManifest.xml`: `android:debuggable="true"`, `android:usesCleartextTraffic="true"`, `android:allowBackup="true"`
  without backup rules that exclude tokens, and components with `android:exported="true"` and no permission that handle
  sensitive actions or deep links without validation.
- A network security config that trusts user certificates in release builds, or has cleartext exceptions.
- Tokens or personal data in plain `SharedPreferences` or files. Use Keystore-backed encryption (for example DataStore
  encrypted with a Keystore key).
- WebView with `setJavaScriptEnabled(true)` plus `addJavascriptInterface`, `setAllowFileAccess(true)`, or loading
  untrusted URLs.
- OkHttp or `HostnameVerifier`/`TrustManager` implementations that accept everything.
- Release builds without R8/minification (`low`). Signing keys or passwords in `gradle.properties` in the repo.
- OAuth redirect handling (AppAuth): PKCE on, `state` checked, and a redirect scheme that's specific to the app.

iOS:
- `Info.plist`: `NSAllowsArbitraryLoads` or broad `NSExceptionDomains`. Custom URL schemes handling auth callbacks without
  checking `state`.
- Tokens in `UserDefaults` or files instead of the Keychain. Keychain items with `kSecAttrAccessibleAlways`.
- `URLSessionDelegate` that accepts any server trust.
- `WKWebView` with JavaScript message handlers exposed to untrusted content.
- Sensitive data in logs (`print`/`NSLog`/`os_log` with `%{public}`).

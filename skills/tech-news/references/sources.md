# Sources

Contents:
- [Detection](#detection)
- [Finding a technology's home](#finding-a-technologys-home)
- [Security advisories](#security-advisories)
- [End of life](#end-of-life)
- [Releases](#releases)
- [Official feeds](#official-feeds)
- [Ecosystem news](#ecosystem-news)
- [Fetching tips](#fetching-tips)

Feed and API URLs change over time. If one fails, run one web search for the vendor's current blog or changelog and use
that instead. Mention the new URL in the report so this file can be updated.

## Detection

| Files found | Technologies to pull from them |
| --- | --- |
| `package.json` + lock file (`package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lock(b)`) | Node.js (from `engines`), frameworks and libraries in `dependencies` / `devDependencies`, the build tool (Vite, Next, webpack), TypeScript |
| `*.csproj`, `*.fsproj`, `Directory.Packages.props`, `Directory.Build.props`, `global.json` | .NET (`TargetFramework`, SDK pin), ASP.NET Core, EF Core, database drivers, AWS/Azure SDKs, test frameworks |
| `gradle/libs.versions.toml`, `build.gradle(.kts)`, `gradle-wrapper.properties` | Kotlin, AGP, Gradle, Jetpack Compose (BOM), AndroidX, `compileSdk` / `targetSdk` |
| `pom.xml` | Java/JDK level, Spring Boot and other frameworks |
| `Package.swift`, `Package.resolved`, XcodeGen `project.yml`, `*.xcodeproj`, `Podfile` | Swift, SwiftUI, iOS deployment target, Xcode version (CI), Swift packages |
| `requirements*.txt`, `pyproject.toml`, `poetry.lock`, `uv.lock`, `.python-version` | Python, Django / FastAPI / Flask and other major libraries |
| `go.mod` · `Cargo.toml` · `Gemfile` · `composer.json` · `pubspec.yaml` | Go · Rust · Ruby/Rails · PHP/Laravel · Dart/Flutter |
| `.nvmrc`, `.node-version`, `.tool-versions`, `mise.toml`, `rust-toolchain(.toml)`, `.java-version` | Runtime versions |
| `Dockerfile*`, `compose*.y(a)ml`, `.devcontainer/devcontainer.json` | Base images (`FROM node:22-alpine` → Node 22 and Alpine), databases and services in compose |
| CloudFormation / SAM templates, `*.tf`, `*.bicep`, `cdk.json`, `Pulumi.yaml` | Cloud services by resource type (`AWS::Lambda::Function` + `Runtime`, `AWS::Cognito::UserPool`, `AWS::ApiGatewayV2::Api`), Terraform and its providers |
| `azure-pipelines*.yml`, `.github/workflows/*.yml`, `.gitlab-ci.yml` | CI system, hosted agent images (`ubuntu-latest`, `macos-15`), key tasks and actions |
| `.vscode/extensions.json` | Leave out unless asked |

## Finding a technology's home

To look up releases you need each technology's source repository and, for advisories, its package coordinates.

| Ecosystem | Repository URL from | Release dates from |
| --- | --- | --- |
| npm | `npm view <pkg> repository.url homepage --json`, or `https://registry.npmjs.org/<pkg>` (`repository.url`) | `npm view <pkg> time --json` |
| NuGet | `https://api.nuget.org/v3/registration5-gz-semver2/<id-lowercase>/index.json` (`projectUrl`, `repository` in the catalog entry) | `published` in the same response |
| PyPI | `https://pypi.org/pypi/<pkg>/json` (`info.project_urls`) | `releases[<ver>][0].upload_time` |
| Maven | `https://search.maven.org/solrsearch/select?q=g:<group>+AND+a:<artifact>&core=gav&rows=20&wt=json`, then the POM's `<scm>` | `timestamp` in the search response |
| Go | Module path (`github.com/owner/repo`) | `https://proxy.golang.org/<module>/@v/<ver>.info` |
| crates.io | `https://crates.io/api/v1/crates/<crate>` (`crate.repository`) | `versions[].created_at` |
| Swift PM | URL in `Package.resolved` / `project.yml` | GitHub releases or tags |

## Security advisories

**OSV** (covers npm, NuGet, PyPI, Maven, Go, crates.io, RubyGems, Packagist, Pub, Hex and others). Query every package in
one batch:

```sh
curl -s https://api.osv.dev/v1/querybatch -d '{"queries":[
  {"package":{"ecosystem":"npm","name":"axios"},"version":"1.6.0"},
  {"package":{"ecosystem":"NuGet","name":"MongoDB.Driver"},"version":"3.1.0"}
]}'
```

The batch response only returns vulnerability IDs. Fetch details with `https://api.osv.dev/v1/vulns/<id>` (summary,
severity, `affected[].ranges` with the fixed version, `published`, references). Ecosystem names are case-sensitive:
`npm`, `NuGet`, `PyPI`, `Maven` (`group:artifact`), `Go`, `crates.io`, `RubyGems`, `Packagist`, `Pub`.

**GitHub Advisory Database** is useful for severity and a readable summary:
`gh api "/advisories?ecosystem=npm&affects=axios@1.6.0"`, or the same path on `https://api.github.com` without `gh`.
Ecosystem values are `npm`, `nuget`, `pip`, `maven`, `go`, `rust`, `rubygems`, `composer`, `pub`, `swift`.

Runtimes and platforms that aren't packages (Node.js, .NET runtime, Python, OpenSSL in base images) have advisories in
their vendors' security pages and release notes. Check those through the feeds below.

## End of life

**endoflife.date** covers runtimes, frameworks, databases, OS images and many cloud runtimes:

- `https://endoflife.date/api/<product>.json`: every release cycle with `eol`, `support`, `latest`, `lts`
- `https://endoflife.date/api/<product>/<cycle>.json`: one cycle

Common product IDs: `nodejs`, `dotnet`, `python`, `java` / `eclipse-temurin`, `go`, `kotlin`, `react`, `angular`,
`django`, `spring-boot`, `mongodb`, `postgresql`, `redis`, `alpine`, `ubuntu`, `debian`, `aws-lambda`, `android`, `ios`,
`xcode`, `terraform`, `azure-devops-server`. If you're not sure of an ID, fetch `https://endoflife.date/api/all.json`.

Vendor-specific deprecations that endoflife.date doesn't fully cover:

| Area | Source |
| --- | --- |
| AWS Lambda runtimes | `https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html` (deprecation and block dates) |
| Azure Pipelines / GitHub Actions hosted images | `https://github.com/actions/runner-images/issues` (announcements label) and the README image table |
| Google Play target API level | `https://developer.android.com/google/play/requirements/target-sdk` |
| App Store SDK minimum | Apple developer news (below), search for "SDK minimum requirements" |
| .NET support policy | `https://dotnet.microsoft.com/platform/support/policy/dotnet-core` |

## Releases

GitHub is the best source for libraries and frameworks:

```sh
gh api "repos/<owner>/<repo>/releases?per_page=30" --jq '.[] | {tag_name, published_at, prerelease, html_url, body}'
```

Without `gh`, use `https://api.github.com/repos/<owner>/<repo>/releases?per_page=30` (60 requests per hour without
authentication) or the Atom feed `https://github.com/<owner>/<repo>/releases.atom`, which doesn't count against the API
limit. If a repo publishes no releases, use `CHANGELOG.md` from the default branch, or tags plus registry dates.

Monorepos publish many packages from one repository (React Router, Mantine, Jetpack libraries). Filter release tags to
the packages the repo uses.

Read the body of every major and minor release in the window. Look for "Breaking", "Removed", "Deprecated", "Migration"
and "Security".

## Official feeds

RSS/Atom feeds for vendor announcements. Filter entries by date to the window, then by relevance to the technology and
version.

| Technology | Feed |
| --- | --- |
| .NET, ASP.NET Core, EF Core | `https://devblogs.microsoft.com/dotnet/feed/` |
| TypeScript | `https://devblogs.microsoft.com/typescript/feed/` |
| Azure DevOps / Azure Pipelines | `https://devblogs.microsoft.com/devops/feed/` |
| GitHub, GitHub Actions | `https://github.blog/changelog/feed/` |
| AWS (all services) | `https://aws.amazon.com/about-aws/whats-new/recent/feed/`. Filter titles by the services the IaC uses |
| AWS Lambda, API Gateway | `https://aws.amazon.com/blogs/compute/feed/` |
| Node.js | `https://nodejs.org/en/feed/blog.xml` |
| React | `https://react.dev/rss.xml` |
| React Router / Remix | `https://remix.run/blog/rss.xml`, plus GitHub releases for `remix-run/react-router` |
| Mantine | GitHub releases for `mantinedev/mantine`, and `https://mantine.dev/changelog/previous-versions/` |
| Vite | GitHub releases for `vitejs/vite`, and `https://vite.dev/blog` |
| MongoDB | `https://www.mongodb.com/blog/rss`, and driver release notes on GitHub (`mongodb/mongo-csharp-driver`, etc.) |
| Kotlin | `https://blog.jetbrains.com/kotlin/feed/` |
| Android, Jetpack Compose | `https://android-developers.googleblog.com/feeds/posts/default`, and `https://developer.android.com/jetpack/androidx/versions` |
| Swift | `https://www.swift.org/atom.xml` |
| Apple platforms, Xcode, App Store | `https://developer.apple.com/news/rss/news.rss` |
| Python | `https://blog.python.org/feeds/posts/default` |
| Go | `https://go.dev/blog/feed.atom` |
| Rust | `https://blog.rust-lang.org/feed.xml` |
| Docker | `https://www.docker.com/blog/feed/` |
| Terraform | `https://www.hashicorp.com/blog/feed.xml`, and GitHub releases for `hashicorp/terraform` and each provider |

For a technology with no feed listed, look for one in this order: the project's GitHub releases, a `/blog` or `/changelog`
page on its website (check for an RSS link in the page head), then one web search such as
`<technology> release announcement <month year>`.

## Ecosystem news

Use these sparingly, for central technologies only:

- **Hacker News** (Algolia API, free, no key):
  `https://hn.algolia.com/api/v1/search_by_date?query=<tech>&tags=story&numericFilters=created_at_i><unix start>,points>100`.
  The points threshold filters out noise. Raise it for popular names like "React" and lower it for niche ones.
- **Web search**: one query per technology, naming the version and period, for example
  `"MongoDB" license OR acquisition OR deprecation 2026`. Only report a result if you can find a dated primary source
  for it.

## Fetching tips

- Prefer `gh api` and `curl` through the shell for JSON APIs. They return raw data and are faster than a page fetch. Use
  page fetching for HTML pages and when the shell has no network.
- Pass a generic `User-Agent`. Don't include the user's name, email or repo name in any request.
- To stay under GitHub's unauthenticated limit, use `gh` (authenticated) when it's installed. Otherwise use the
  `releases.atom` feeds.
- Save raw responses to the session scratchpad if you need them more than once in a run. Don't write them into the repo.

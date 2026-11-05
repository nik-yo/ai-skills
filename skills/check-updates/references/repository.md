# Repository checks

Contents:
- [Detection](#detection)
- [Packages](#packages)
- [SDK and runtime pins](#sdk-and-runtime-pins)
- [CI/CD](#cicd)
- [Container images](#container-images)
- [Infrastructure as code](#infrastructure-as-code)
- [Mobile platform requirements](#mobile-platform-requirements)
- [Versions in docs and templates](#versions-in-docs-and-templates)
- [Registry and vendor endpoints](#registry-and-vendor-endpoints)

## Detection

| Files found | Check |
| --- | --- |
| `package.json` + `package-lock.json` / `pnpm-lock.yaml` / `yarn.lock` / `bun.lock(b)` | npm / pnpm / yarn / bun |
| `*.csproj`, `*.fsproj`, `Directory.Packages.props`, `packages.config`, `.config/dotnet-tools.json` | NuGet, .NET local tools |
| `gradle/libs.versions.toml`, `build.gradle(.kts)`, `gradle-wrapper.properties` | Gradle, Android |
| `pom.xml` | Maven |
| `Package.swift`, `Package.resolved`, XcodeGen `project.yml`, `Podfile` | Swift PM, CocoaPods |
| `requirements*.txt`, `pyproject.toml`, `poetry.lock`, `uv.lock`, `Pipfile` | Python |
| `go.mod` | Go |
| `Cargo.toml` | Rust |
| `Gemfile` · `composer.json` · `pubspec.yaml` | Ruby · PHP · Dart/Flutter |
| `global.json`, `.nvmrc`, `.node-version`, `.python-version`, `.tool-versions`, `mise.toml`, `rust-toolchain(.toml)`, `.java-version`, `.sdkmanrc` | SDK pins |
| `azure-pipelines*.yml`, `.azuredevops/`, `.github/workflows/*.yml`, `.gitlab-ci.yml`, `bitbucket-pipelines.yml`, `.circleci/config.yml` | CI/CD |
| `Dockerfile*`, `*.dockerfile`, `compose*.y(a)ml`, `docker-compose*.y(a)ml`, `.devcontainer/devcontainer.json`, Kubernetes manifests, Helm `Chart.yaml` / `values.yaml` | Images |
| CloudFormation/SAM templates (`AWSTemplateFormatVersion` or `Transform: AWS::Serverless`), `*.tf`, `.terraform.lock.hcl`, `*.bicep`, ARM JSON, `cdk.json`, `Pulumi.yaml` | IaC |
| `.pre-commit-config.yaml`, `.husky/`, `lefthook.yml` | Hooks |
| `renovate.json`, `.github/dependabot.yml` | Bot config: note whether the bot covers each ecosystem found |

Monorepos: run each check once per workspace or solution root, not once per file. npm, pnpm and yarn workspaces are handled
by running from the root. For .NET, run against the `.sln`/`.slnx`.

## Packages

For each ecosystem, check outdated packages and known vulnerabilities, then (when applying) use the update command.

| Ecosystem | Outdated | Vulnerabilities | Apply |
| --- | --- | --- | --- |
| npm | `npm outdated --json` (`--all` for transitive; `-ws` in workspaces) | `npm audit --json` | `npm install <pkg>@<ver>`; `npm update` stays within ranges |
| pnpm | `pnpm outdated --format json -r` | `pnpm audit --json` | `pnpm up <pkg>@<ver> -r` |
| yarn 1 | `yarn outdated --json` | `yarn audit --json` | `yarn upgrade <pkg>@<ver>` |
| yarn 2+ | no non-interactive outdated; use `npm view <pkg> version` per direct dep | `yarn npm audit --json` | `yarn up <pkg>@<ver>` |
| bun | `bun outdated` | `bun audit` (newer bun) or `npm audit` against `package.json` | `bun update <pkg>` |
| NuGet | `dotnet list package --outdated --format json` (add `--include-transitive` for transitive; `--highest-minor` to see non-breaking targets) | `dotnet list package --vulnerable --include-transitive --format json` | `dotnet add <proj> package <id> --version <ver>`, or edit `Directory.Packages.props` for central package management |
| .NET local tools | `dotnet tool list` + NuGet API | n/a | `dotnet tool update <id>` |
| Gradle | `./gradlew dependencyUpdates` only if the `com.github.ben-manes.versions` plugin is applied. Otherwise read `libs.versions.toml` and the build files and query Maven metadata (below) | `./gradlew dependencyCheckAnalyze` only if OWASP plugin present; otherwise OSV (below) | Edit `libs.versions.toml` / build files |
| Maven | `mvn -q versions:display-dependency-updates versions:display-plugin-updates` | OSV | `mvn versions:use-latest-releases` or edit `pom.xml` |
| Swift PM | `swift package show-dependencies --format json` (macOS) or read `Package.resolved`, then `git ls-remote --tags --refs <url>` | OSV / GitHub advisories | Edit requirement, then `swift package update` / `xcodebuild -resolvePackageDependencies` |
| XcodeGen | `packages:` in `project.yml` (`from:`, `exactVersion:`, `minorVersion:`) + `git ls-remote --tags` | same | Edit `project.yml`, regenerate with `xcodegen` |
| CocoaPods | `pod outdated` | n/a | `pod update <name>` |
| pip / venv | `pip list --outdated --format json` (inside the project venv) or PyPI per requirement | `pip-audit` if installed | Edit requirements, reinstall |
| uv | `uv pip list --outdated` (or `uv tree --outdated`) | `pip-audit` / OSV | `uv lock --upgrade-package <pkg>` |
| Poetry | `poetry show --outdated --top-level` | `pip-audit` / OSV | `poetry update <pkg>` / `poetry add <pkg>@^<ver>` |
| Go | `go list -m -u -json all` (direct deps: no `"Indirect": true`) | `govulncheck ./...` if installed | `go get <mod>@<ver> && go mod tidy` |
| Rust | `cargo outdated` if installed, else `cargo update --dry-run` (in-range only) + crates.io | `cargo audit` if installed | `cargo update -p <crate>` / edit `Cargo.toml` |
| Ruby | `bundle outdated --parseable` | `bundle audit` if installed | `bundle update <gem>` |
| PHP | `composer outdated --direct --format json` | `composer audit --format json` | `composer require <pkg>:^<ver>` |
| Dart/Flutter | `dart pub outdated --json` / `flutter pub outdated --json` | n/a | `dart pub upgrade --major-versions <pkg>` |
| pre-commit | `rev:` per repo vs `git ls-remote --tags --refs <repo>` | n/a | `pre-commit autoupdate` |

When an ecosystem has no audit tool installed, query OSV in batch: `POST https://api.osv.dev/v1/querybatch` with
`{"queries":[{"package":{"ecosystem":"Maven","name":"group:artifact"},"version":"1.2.3"}, ...]}`. Ecosystem names include
`npm`, `NuGet`, `Maven`, `PyPI`, `Go`, `crates.io`, `RubyGems`, `Packagist`, `Pub`, `SwiftURL`.

Notes:
- `dotnet list package` needs a restore. It runs one implicitly, which only writes `obj/`. Newer SDKs also accept the
  noun-first form `dotnet package list`.
- `npm outdated` reports `wanted` (newest version in range) and `latest`. If `current` < `wanted`, the lock file is stale
  within the range. That's a `patch`/`minor` that `npm update` fixes.
- Group framework families so they move together: `@angular/*`, `@mantine/*`, `react` + `react-dom` + `@types/react*`,
  `react-router` + `@react-router/*`, `Microsoft.AspNetCore.*` / `Microsoft.Extensions.*` (match the target framework's
  major), `androidx.compose` BOM members, `kotlinx-*`, AWS SDK modules.
- Pre-releases are never "latest" unless the repo already uses a pre-release of that package.

## SDK and runtime pins

Find every place each runtime is pinned and compare them with each other (`drift`) and with the current supported release.

| Runtime | Where it's pinned | Latest / support source |
| --- | --- | --- |
| Node.js | `.nvmrc`, `.node-version`, `engines.node`, `packageManager` (for pnpm/yarn via corepack), `@types/node` major, CI `node-version` / `NodeTool@0` / `UseNode@1`, Dockerfile `FROM node:*`, Lambda `Runtime: nodejsNN.x` | `https://nodejs.org/dist/index.json` (`lts` field) + endoflife.date `nodejs` |
| .NET | `global.json` (`sdk.version`, `rollForward`), `<TargetFramework(s)>`, CI `UseDotNet@2` / `actions/setup-dotnet`, Docker `mcr.microsoft.com/dotnet/*` tags, Lambda `dotnetN` / base image | `https://builds.dotnet.microsoft.com/dotnet/release-metadata/releases-index.json` (`latest-sdk`, `support-phase`, `eol-date`; skip channels whose `support-phase` is `preview` or `go-live`; per channel `.../<major.minor>/releases.json` lists `security: true` releases) |
| Java / JDK | `jvmToolchain(N)`, `JavaVersion.VERSION_N`, `jvmTarget`, `.java-version`, `.sdkmanrc`, CI `JavaToolInstaller` / `setup-java` | endoflife.date `eclipse-temurin` / `java` |
| Gradle | `gradle/wrapper/gradle-wrapper.properties` `distributionUrl` | `https://services.gradle.org/versions/current`. Apply with `./gradlew wrapper --gradle-version <ver>` (run it twice so the wrapper jar updates too) |
| Kotlin / AGP | version catalog `kotlin`, `agp` | Maven metadata (below). Check AGP ↔ Gradle ↔ JDK compatibility at `https://developer.android.com/build/releases/gradle-plugin` before recommending |
| Python | `.python-version`, `requires-python`, `python_requires`, CI `UsePythonVersion@0` / `setup-python`, Docker `python:*`, Lambda `pythonX.Y` | endoflife.date `python` |
| Go | `go` and `toolchain` lines in `go.mod`, CI `setup-go` | `https://go.dev/dl/?mode=json` |
| Rust | `rust-toolchain(.toml)`, `rust-version` in `Cargo.toml` | `https://static.rust-lang.org/dist/channel-rust-stable.toml` (`[pkg.rust] version`) |
| Xcode / Swift | XcodeGen `options.xcodeVersion`, `deploymentTarget`, `swift-tools-version`, CI `Xcode@5` / `xcode-select` paths / `macos-*` image | Apple developer releases page + the hosted image's installed software list |
| asdf / mise | `.tool-versions`, `mise.toml` | the source for each tool listed |

endoflife.date: `https://endoflife.date/api/v1/products/<product>/` (falls back to `https://endoflife.date/api/<product>.json`).
The product list is at `https://endoflife.date/api/v1/products/`. Use it for runtimes, OS base images (`ubuntu`, `debian`,
`alpine`, `amazon-linux`), databases (`mongodb`, `postgresql`, `redis`), `kubernetes`, `terraform` and frameworks.
Report `eol` when the support end date has passed, and add a note when it's within 6 months.

## CI/CD

| System | Check |
| --- | --- |
| Azure Pipelines | Each `task: Name@N`. Compare N with the task reference at `https://learn.microsoft.com/azure/devops/pipelines/tasks/reference/`, which lists every major version and marks deprecated ones. Each `vmImage:`: compare with `https://learn.microsoft.com/azure/devops/pipelines/agents/hosted` (available images and retirement dates). Check version inputs of tool tasks (`UseDotNet@2 version`, `NodeTool@0 versionSpec`, `UsePythonVersion@0`, `JavaToolInstaller@0 versionSpec`, `Xcode@5 xcodeVersion`) against the SDK pins. Check `resources.repositories` refs and template refs pinned to tags. |
| GitHub Actions | Each `uses: owner/repo[/path]@ref`: latest release via `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name` (or `git ls-remote --tags --refs https://github.com/<owner>/<repo>`). If the ref is a commit SHA, keep SHA pinning: find the SHA of the latest tag and keep the `# vX.Y.Z` comment. Each `runs-on:`: compare with `https://github.com/actions/runner-images` (available labels and deprecation notices). Also check `setup-*` version inputs against the SDK pins. Reusable workflow refs `owner/repo/.github/workflows/x.yml@ref` count too. |
| GitLab CI | `image:` and `services:` (see images), `include: component: ...@<ver>` and `include: project ... ref:` |
| Others | Bitbucket `image:`, CircleCI `orbs:` versions and `image:` / `machine.image`, Jenkins agent images |

`-latest` image labels (`ubuntu-latest`, `macos-latest`, `windows-latest`) aren't outdated, but they change underneath you.
Mention it only if the pipeline also pins tool versions that the label's next image may drop (for example an Xcode version).

## Container images

Collect every image reference: `FROM` lines (resolve `ARG` defaults, skip stage aliases), compose `image:`, Kubernetes and Helm
`image:` / `repository` + `tag`, devcontainer `image` and `features` (`ghcr.io/devcontainers/features/x:1`), CI `image:` /
`services:` / `container:`, CloudFormation `ImageUri` and Lambda base images, `Dockerfile` `COPY --from=<image>`.

For each one:
- **Tag scheme:** compare only within the same scheme and variant. `node:22-alpine` → newest `NN-alpine`. `8.0-noble` stays
  `-noble` unless the OS is EOL. `python:3.12-slim-bookworm` → check both the Python and Debian parts.
- **Latest:** list tags from the registry (below) and pick the highest version with the same suffix.
- **Digest pins (`@sha256:`):** check whether the tag's digest has moved (`docker buildx imagetools inspect <image>:<tag>`,
  `crane digest`, or a manifest HEAD request) and report it as `patch` (rebuilt base, usually security fixes).
- **Floating tags** (`latest`, `lts`, a bare major): not outdated, but note that builds aren't reproducible if the repo
  otherwise pins exact versions.
- **OS/runtime EOL** for the tag's distro and runtime (endoflife.date).

Registry tag lists (OCI distribution API `GET /v2/<repo>/tags/list`; on 401, request an anonymous token from the `realm` in
the `WWW-Authenticate` header and retry with `Authorization: Bearer <token>`):
- Docker Hub: `https://hub.docker.com/v2/namespaces/<ns>/repositories/<repo>/tags?page_size=100&ordering=last_updated` (`library` for official images)
- MCR: `https://mcr.microsoft.com/v2/<repo>/tags/list`
- Amazon ECR Public: `https://public.ecr.aws/v2/<repo>/tags/list` (anonymous token from `https://public.ecr.aws/token/`)
- GHCR, Quay, GCR: OCI API as above
- If installed, `crane ls <image>` or `skopeo list-tags docker://<image>` do all of this.

## Infrastructure as code

| Tool | Check |
| --- | --- |
| CloudFormation / SAM | Lambda `Runtime:` against `https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html` (supported and deprecated runtimes with block dates). Engine versions: `EngineVersion` for RDS/DocumentDB/ElastiCache/OpenSearch, EKS `Version`, MSK `KafkaVersion` against endoflife.date or the `aws <service> describe-*-versions` commands if the CLI is configured. Container images in `ImageUri`. `cfn-lint` (if installed) flags deprecated runtimes too. |
| CDK / Pulumi | Packages are covered by the package manager. Also check the `aws-cdk` CLI version against `aws-cdk-lib`. |
| Terraform / OpenTofu | `required_version` against the latest release. Each `required_providers` entry against `https://registry.terraform.io/v1/providers/<ns>/<name>` (`version` field). Modules against `https://registry.terraform.io/v1/modules/<ns>/<name>/<provider>`. `.terraform.lock.hcl` shows the locked versions. Apply with `terraform init -upgrade`. |
| Bicep / ARM | Resource `apiVersion`s: `bicep lint` with the `use-recent-api-versions` rule enabled, or `az provider show -n <namespace> --query "resourceTypes[?resourceType=='<type>'].apiVersions"`. Module refs `br:<registry>/<path>:<tag>`. |
| Kubernetes | Deprecated or removed `apiVersion`s: `pluto detect-files -d <dir>` if installed, else compare with `https://kubernetes.io/docs/reference/using-api/deprecation-guide/`. Helm chart `dependencies:` versions via `helm search repo <chart> --versions` or Artifact Hub. |

## Mobile platform requirements

- **Android:** `compileSdk` and `targetSdk` against Google Play's target API requirement at
  `https://developer.android.com/google/play/requirements/target-sdk`. If the next deadline is within 6 months and the
  app is below it, report `eol` with the date. Check `minSdk` against what the repo's AndroidX versions still support. That
  is a note, not an update.
- **iOS:** the Xcode/SDK version used in CI against Apple's upcoming requirements at
  `https://developer.apple.com/news/upcoming-requirements/` (minimum Xcode/SDK for App Store uploads). `deploymentTarget` is
  a product decision. Mention it only if dependencies now require a higher one.

## Versions in docs and templates

Repos that generate other projects, such as scaffolding skills, templates and cookiecutters, and README install snippets
often pin versions in Markdown or template files that no package manager sees. If the repo is mainly docs or templates,
search the text for version pins: package tables, `Version="x"`, `"pkg": "^x"`, `libs.versions.toml` blocks, `FROM` lines,
`task: X@N`, `vmImage`, `distributionUrl`, `TargetFramework`. Check each pin like the real thing, and report it with the
file and line. Keep pins that describe the same thing consistent across files.

## Registry and vendor endpoints

Send a generic `User-Agent` such as `check-updates-skill` (crates.io requires one). Never put the user's identity in it.

| Registry | Latest version |
| --- | --- |
| npm | `https://registry.npmjs.org/<pkg>/latest` (scoped: `@scope%2Fname`) or `npm view <pkg> version` |
| NuGet | `https://api.nuget.org/v3-flatcontainer/<id-lowercase>/index.json` (last stable entry) |
| Maven Central | `https://repo1.maven.org/maven2/<group/as/path>/<artifact>/maven-metadata.xml` (`<release>`) |
| Google Maven | `https://dl.google.com/android/maven2/<group/as/path>/<artifact>/maven-metadata.xml` (androidx, AGP, Firebase, Play services) |
| Gradle Plugin Portal | `https://plugins.gradle.org/m2/<plugin/id/as/path>/<plugin.id>.gradle.plugin/maven-metadata.xml` |
| PyPI | `https://pypi.org/pypi/<pkg>/json` (`info.version`) |
| Go | `https://proxy.golang.org/<module>/@latest` |
| crates.io | `https://crates.io/api/v1/crates/<name>` (`crate.max_stable_version`) |
| RubyGems | `https://rubygems.org/api/v1/versions/<gem>/latest.json` |
| Packagist | `https://repo.packagist.org/p2/<vendor>/<pkg>.json` |
| pub.dev | `https://pub.dev/api/packages/<name>` (`latest.version`) |
| GitHub releases/tags | `gh api repos/<o>/<r>/releases/latest --jq .tag_name` or `git ls-remote --tags --refs https://github.com/<o>/<r>` |
| Terraform | `https://registry.terraform.io/v1/providers/<ns>/<name>` |

Ignore pre-release versions (`-alpha`, `-beta`, `-rc`, `-preview`, `-SNAPSHOT`, `-dev`) unless the current version is a
pre-release.

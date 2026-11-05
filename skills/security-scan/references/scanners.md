# Scanner commands

Use the first option that's available for each area. Write raw output to the session scratchpad (`$OUT` below), never into
the repo, and parse the JSON there.

Contents:
- [Running scanners without installing them](#running-scanners-without-installing-them)
- [Dependencies](#dependencies)
- [Secrets](#secrets)
- [Container images](#container-images)
- [Infrastructure as code](#infrastructure-as-code)
- [CI/CD](#cicd)
- [Code (SAST)](#code-sast)

## Running scanners without installing them

Only after the user has agreed (SKILL.md step 2).

| Runner | Pattern |
| --- | --- |
| Docker (bash) | `docker run --rm -v "$PWD:/src" -w /src <image> <args>` |
| Docker (Git Bash on Windows) | `MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W):/src" -w /src <image> <args>` |
| Docker (PowerShell) | `docker run --rm -v "${PWD}:/src" -w /src <image> <args>` |
| Python tools | `uvx <tool> <args>` or `pipx run <tool> <args>` |

Pin a version tag rather than `latest`, and use the publisher's official image. Scanners are themselves a supply-chain
target.

| Scanner | Docker image | Python |
| --- | --- | --- |
| Trivy | `aquasec/trivy:<ver>` | |
| OSV-Scanner | `ghcr.io/google/osv-scanner:<ver>` | |
| Grype | `anchore/grype:<ver>` | |
| gitleaks | `ghcr.io/gitleaks/gitleaks:<ver>` | |
| TruffleHog | `trufflesecurity/trufflehog:<ver>` | |
| Semgrep | `semgrep/semgrep:<ver>` | `uvx semgrep` |
| Checkov | `bridgecrew/checkov:<ver>` | `uvx checkov` |
| hadolint | `hadolint/hadolint:<ver>` | |
| zizmor | | `uvx zizmor` |
| bandit | | `uvx bandit` |

To find a current version, ask the GitHub releases API: `gh api repos/<owner>/<repo>/releases/latest --jq .tag_name`.

## Dependencies

Run the ecosystem's own audit when it's present, because it reads the lock file exactly. Add a cross-ecosystem scanner if
one is available.

| Ecosystem | Command |
| --- | --- |
| npm | `npm audit --json` (prod only: `--omit=dev`; run once with it and once without, to tell runtime from dev exposure) |
| pnpm / yarn 1 / yarn 2+ | `pnpm audit --json` / `yarn audit --json` / `yarn npm audit --all --recursive --json` |
| bun | `bun audit` (newer bun) |
| .NET | `dotnet list package --vulnerable --include-transitive --format json` (runs a restore that writes only `obj/`) |
| Python | `pip-audit -r requirements.txt -f json` or `pip-audit` inside the venv; Poetry/uv: export the lock to requirements first |
| Go | `govulncheck -json ./...`. It reports only vulnerabilities in code the module actually calls, so trust its reachability |
| Rust | `cargo audit --json` |
| Ruby / PHP | `bundle audit check --update` / `composer audit --format json` |
| Gradle / Maven / Swift / others | no built-in audit. Use OSV-Scanner or Trivy below |

Cross-ecosystem:
- **OSV-Scanner:** `osv-scanner scan source -r --format json . > $OUT/osv.json` (v2; v1 is `osv-scanner -r --format json .`).
  It reads lock files for npm, NuGet, Maven/Gradle (`gradle.lockfile`, `buildscript-gradle.lockfile`), PyPI, Go, Cargo,
  Pub, Composer, RubyGems, Swift `Package.resolved` and more.
- **Trivy:** `trivy fs --scanners vuln --format json --output $OUT/trivy-vuln.json .`
- **Grype:** `grype dir:. -o json > $OUT/grype.json`

**Without any scanner:** take the resolved versions from the lock files (or from `libs.versions.toml` and the build files for
Gradle, which has no lock file by default; say that transitive versions weren't covered), and send them in batches to OSV:

```
POST https://api.osv.dev/v1/querybatch
{"queries":[{"package":{"ecosystem":"npm","name":"axios"},"version":"1.6.0"}, ...]}
```

The batch returns vulnerability IDs only. Get details per ID from `GET https://api.osv.dev/v1/vulns/<id>` (severity, the
`affected[].ranges` fixed versions, and aliases such as CVE and GHSA IDs). Ecosystem names: `npm`, `NuGet`, `Maven`, `PyPI`,
`Go`, `crates.io`, `RubyGems`, `Packagist`, `Pub`, `SwiftURL`. For Maven, the package name is `group:artifact`. Only public
package names go to OSV. Packages from private feeds are reported as "not checked".

## Secrets

| Scanner | Working tree | Git history (`--history`) |
| --- | --- | --- |
| gitleaks ≥ 8.19 | `gitleaks dir . --redact --report-format json --report-path $OUT/gitleaks.json` | `gitleaks git . --redact --report-format json --report-path $OUT/gitleaks-history.json` |
| gitleaks < 8.19 | `gitleaks detect --no-git --redact ...` | `gitleaks detect --redact ...` |
| Trivy | `trivy fs --scanners secret --format json --output $OUT/trivy-secret.json .` | (working tree only) |
| TruffleHog | `trufflehog filesystem . --json --no-verification --no-update` | `trufflehog git file://. --json --no-verification --no-update` |

Always pass `--no-verification` to TruffleHog. Verification logs in to the provider with the found credential, and that
decision belongs to the credential's owner.

Exit code 1 from gitleaks means it found leaks. That's a result, not an error.

The manual patterns in [manual-review.md](manual-review.md#secrets) apply when none of these is available. Also check
files that scanners treat as binary or skip: `*.jks`, `*.keystore`, `*.p12`, `*.pfx`, `*.mobileprovision`, `*.pem`,
`*.key`, `.env*`, `local.properties`.

## Container images

1. **Collect image references:** Dockerfile `FROM` lines (resolve `ARG` defaults and skip stage aliases), compose and
   Kubernetes `image:` fields, CI `image:`/`container:`, CloudFormation `ImageUri` and Lambda base images.
2. **Scan each distinct image.** Locally built images (`docker images`) are the most accurate. Otherwise scan the base
   images, which pulls them, so tell the user about large pulls.
   - Trivy: `trivy image --scanners vuln --format json --output $OUT/img-<name>.json <image>` (add `--ignore-unfixed` for a
     second, actionable view)
   - Grype: `grype <image> -o json`
   - Docker Scout: `docker scout cves --format sarif <image>`
3. **Lint Dockerfiles:** `hadolint --format json Dockerfile`, or `trivy config` (below), which includes Dockerfile checks.
   Then do the manual Dockerfile checklist.

Report OS-package CVEs per image, grouped by fix: most are fixed by moving to a newer tag or rebuilding with the latest
patch. Name the target tag.

## Infrastructure as code

| Scanner | Command | Covers |
| --- | --- | --- |
| Checkov | `checkov -d . -o json --quiet --compact > $OUT/checkov.json` | CloudFormation, SAM, Terraform, Bicep, ARM, Kubernetes, Helm, Dockerfile, GitHub Actions, Azure Pipelines (some), serverless |
| Trivy | `trivy config --format json --output $OUT/trivy-config.json .` | CloudFormation, Terraform, Kubernetes, Helm, Dockerfile, ARM (compile Bicep first: `az bicep build -f main.bicep --stdout`) |
| cfn-nag | `cfn_nag_scan --input-path <templates dir> --output-format json` | CloudFormation |
| kube-linter / kubescape | `kube-linter lint . --format json` / `kubescape scan .` | Kubernetes, Helm |
| tflint | `tflint --recursive -f json` | Terraform (mostly correctness, with some security rules) |

CloudFormation templates that use intrinsic functions or `Transform` may show findings that resolve differently at deploy
time, so verify each one against the template's parameters and conditions.

## CI/CD

| System | Scanner |
| --- | --- |
| GitHub Actions | `zizmor --format json .` (injection, `pull_request_target`, excessive permissions, unpinned actions, credential persistence, cache poisoning) and `actionlint -format '{{json .}}'` (includes shellcheck on `run:` scripts) |
| Azure Pipelines, GitLab, Bitbucket, CircleCI, Jenkins | no dedicated scanner. Use the manual checklist; Checkov covers a few Azure Pipelines and GitLab rules |

## Code (SAST)

| Scanner | Command | Notes |
| --- | --- | --- |
| Semgrep | `semgrep scan --config p/default --config p/secrets --metrics=off --json --output $OUT/semgrep.json` | Add language packs as relevant: `p/csharp`, `p/typescript`, `p/react`, `p/kotlin`, `p/swift`, `p/python`, `p/golang`, `p/java`, `p/dockerfile`. `--config auto` doesn't work with metrics off |
| CodeQL | `codeql database create $OUT/db --language=<lang> --source-root .` then `codeql database analyze $OUT/db --format=sarif-latest --output=$OUT/codeql.sarif <lang>-security-extended.qls` | Only if already installed. Compiled languages need a build command (`--command`) |
| .NET analyzers | `dotnet build -p:AnalysisModeSecurity=All -p:TreatWarningsAsErrors=false` and collect `CA2xxx`/`CA3xxx`/`CA5xxx` warnings | Built into the SDK, so nothing to install |
| Android lint | `./gradlew lint` → `app/build/reports/lint-results-*.xml`, security category | Needs the Android SDK |
| bandit (Python) | `bandit -r . -f json -q -x ./.venv,./tests` | |
| gosec (Go) | `gosec -fmt json ./...` | |
| Brakeman (Rails) | `brakeman -f json` | |
| ESLint security | only if the repo already configures `eslint-plugin-security` or similar: `npx eslint -f json .` | |

SAST output is noisy. Verify every finding by reading the flow from the source (user input) to the sink, and dismiss the ones
where input is constant, validated or not attacker-controlled.

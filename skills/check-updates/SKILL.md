---
name: check-updates
description: Audit what is out of date and report it before changing anything - a repository's packages and lock files, SDK and runtime pins (Node, .NET, JDK, Python, Go, Rust, Gradle, Xcode), CI/CD tasks, actions and hosted agent images, Docker and other container base images, infrastructure-as-code runtimes and providers, and mobile store SDK requirements; plus the developer tools installed on this machine (winget, Homebrew, choco, scoop, apt, SDKs, global CLIs and tools) and VS Code with its extensions. Flags security advisories, end-of-life and deprecated versions first, then major, minor and patch updates, and can apply the ones the user picks. Use it whenever the user asks what needs updating, whether dependencies, packages, images, pipelines, tools or extensions are outdated, stale, deprecated or end-of-life, wants a dependency or toolchain health check, or asks to upgrade or bump versions, even if they only name one of these areas.
argument-hint: "[all|repo|machine|vscode] [path]"
---

# Check updates

Find everything that is out of date in three areas, report it in one ranked list, and then apply the updates the user picks:

| Area | What it covers | Reference |
| --- | --- | --- |
| **repo** | Packages, SDK and runtime pins, CI/CD tasks and agent images, container images, infrastructure as code, mobile platform requirements, versions written in docs and templates | [references/repository.md](references/repository.md) |
| **machine** | OS package managers, language toolchains and SDKs, global packages and tools, cloud and dev CLIs | [references/machine.md](references/machine.md) |
| **vscode** | VS Code itself, installed extensions, and the workspace's recommended extensions | [references/vscode.md](references/vscode.md) |

Arguments given: `$ARGUMENTS`

## Ground rules

- **Read-only until the user approves.** Checking must not change the repo or the machine. Don't install, upgrade, edit
  manifests, or run commands that rewrite lock files (`npm install`, `pre-commit autoupdate`, `brew upgrade`) during the check.
  Commands that only refresh caches or metadata (`dotnet restore` into `obj/`, `brew update`, `winget source update`) are fine.
  Say that you ran them.
- **Prefer the ecosystem's own tool.** `npm outdated`, `dotnet list package --outdated` and `brew outdated` understand version
  ranges, lock files and private feeds. Query a registry or web page directly only when no such tool exists or it isn't installed.
- **Never guess a version.** Every "latest" in the report comes from a command or a registry or vendor response in this
  session. If you can't reach a source, mark the item `unknown` and say why. Don't fill it in from memory: your knowledge of
  release numbers is out of date.
- **Respect private feeds and secrets.** Use the registries configured in `.npmrc`, `nuget.config`, `pip.conf`,
  `settings.gradle(.kts)` and similar files. Don't send private package names to public registries. Report them as
  "private feed" if the configured tool can't check them. Never print tokens from those files.
- **Respect intentional pins.** A comment next to a version, Renovate or Dependabot `ignore` rules, or `overrides`/`resolutions`
  usually means the pin was deliberate. Report the update and quote the reason. Don't recommend it blindly.
- Some tools exit non-zero when they find updates (`npm outdated`, `pnpm outdated`, `dnf check-update`). That's a result, not
  a failure.
- If a tool is missing, skip its check and list it under **Not checked** in the report. Don't install anything to make a
  check work unless the user agrees.

## 1. Scope

Parse `$ARGUMENTS`: an optional scope (`all`, `repo`, `machine`, `vscode`, or a comma-separated mix) and an optional repo path.

- The default scope is `all`. The default path is the current working directory.
- If the scope includes `repo` and the path isn't inside a git repository or a project folder, ask for the path.
- If the user named narrower targets ("just the Docker images", "only npm"), check only those.

Don't ask about anything that has a default. Say which scope and path you're using in your first message.

## 2. Inventory

Find out what exists before checking anything. List the files once, skipping `node_modules`, `bin`, `obj`, `build`, `dist`,
`.gradle`, `Pods`, `vendor`, `.venv`, `target` and `.git`, and match against the detection table at the top of each reference
file. Read only the references for the areas in scope. For the machine and VS Code, detect which tools are installed and
where they came from (see the top of [references/machine.md](references/machine.md)). A tool installed by winget or Homebrew
is checked there, not again on its own.

Tell the user what you found in one line per area, for example "repo: npm (2 workspaces), .NET (4 projects), Gradle version
catalog, Dockerfile, Azure Pipelines, CloudFormation".

## 3. Check

Run the checks in the references for everything the inventory found. Run independent commands and lookups in parallel.
Gather these details for every item that is behind:

- **Where:** the file and line, or the machine tool and how it was installed.
- **Current** and **latest** versions. For packages with version ranges, also give the newest version the range allows.
- **Kind of update:**
  - `security`: a known advisory affects the current version.
  - `eol`: the current version is end of life, deprecated, retired, or below a store or platform minimum.
  - `major`, `minor` or `patch`.
  - `drift`: the same tool is pinned to different versions in different places.
- **Notes:** breaking changes for majors (link the release notes or migration guide), and deadlines such as an EOL date or a
  store requirement date.

Updates that must move together go into one item: a framework and its companion packages, a BOM and its members, AGP with
Gradle, and an SDK pin with its CI task and Docker image. Don't list them separately.

### Compatibility

A newer version isn't worth recommending if it can't install or run here. Before reporting, check every `major` and
`minor` item, and every `security` or `eol` item whose fix crosses a minor version, with the rules in
[references/repository.md](references/repository.md#compatibility). Patch updates are only checked when a scanner or the
release notes say they change requirements.

Check both directions:
- **Requirements of the new version:** the runtime or SDK it needs (Node `engines`, .NET target framework, `requires_python`,
  Go `go` directive, Rust MSRV, JDK level), its peer dependencies, its platform minimums (Android `compileSdk`/`minSdk`, iOS
  deployment target, Swift tools version), and the toolchain combinations it belongs to (AGP ↔ Gradle ↔ JDK, Kotlin ↔ AGP,
  Xcode ↔ Swift ↔ macOS).
- **Packages that depend on it:** installed packages whose peer or dependency ranges exclude the new version.

Give every checked item one status:
- `compatible`: all requirements are met by the repo as it is, or by other updates in the same group.
- `needs <X> first`: a prerequisite update is required, for example "needs Node 22" or "needs net10.0". If that
  prerequisite is also in the report, link the two and order the dependent item after it.
- `conflicts with <pkg>`: something installed excludes it, and no released version of that package accepts it yet.
- `unverified`: the metadata couldn't be read. Say which part.

When the latest version is blocked, also report the **latest compatible** version, the newest one that passes today. That
version is often the practical update.

For machine tools, check them against the repo when both are in scope. A new JDK major has to be supported by the repo's
Gradle and AGP. A new .NET SDK has to satisfy `global.json` and its `rollForward` policy. A new Node major has to satisfy
`engines` and `.nvmrc`. Otherwise, note what to recheck later.

## 4. Report

Lead with the totals and the top things to act on, then give one table per area, sorted `security` → `eol` → `drift` →
`major` → `minor` → `patch`:

```markdown
## Update check: <repo name> · <machine name> · <date>

**12 updates:** 1 security, 2 end of life, 1 drift, 3 major, 5 minor/patch. 2 items not checked.

Act on first:
1. `axios` 1.6.0 → 1.13.2: security, GHSA-xxxx (SSRF). Compatible.
2. Lambda runtime `nodejs18.x`: deprecated; function updates are blocked after <date>. Do this before #4.

### Repository
| Item | Where | Current | Latest | Kind | Compatibility | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `eslint` | `web/package.json` | 8.57.0 | 9.x | major | conflicts with `eslint-plugin-foo` (peer `eslint ^8`) · latest compatible: 8.57.1 | flat config migration |
| `vite` | `web/package.json` | 5.4.0 | 7.x | major | needs Node 20.19+ (repo pins 18 in `.nvmrc`, CI, Dockerfile) → after #2 | |

### Machine
| Tool | Installed via | Current | Latest | Kind | Notes |

### VS Code
| Extension / app | Current | Latest | Kind | Notes |

### Not checked
- Swift packages: `swift` isn't installed. Checked `Package.resolved` against GitHub tags instead.
```

Use the `Compatibility` column only in the repository table. For machine tools and extensions, put compatibility
problems in `Notes`. Keep notes to one line. Put long migration notes after the tables, only for the majors. If nothing is behind in an area,
write one line saying so. Don't include an empty table. If the user asks for a file, save the report as
`UPDATE-REPORT.md` in the repo root (or the path they give). Otherwise, the report stays in the chat.

## 5. Apply (only on request)

After the report, ask in one AskUserQuestion call (multi-select) which groups to apply. Offer only the groups that have
items, with the count in each label:
- Security fixes
- Patch and minor updates (repo)
- Major updates (repo), as one option per major item if there are four or fewer
- End-of-life, drift and CI/image changes
- Machine tools
- VS Code and extensions

Then apply the chosen groups:

- **Repo:** update one group or one ecosystem at a time, using the package manager's own commands so lock files stay
  consistent (each reference lists them). Apply prerequisites before the items that need them. Don't apply an item marked
  `conflicts with` unless the user picked it knowing that. Offer its latest compatible version instead. For npm, do a dry
  run first (`npm install <pkg>@<ver> … --dry-run --ignore-scripts`). An `ERESOLVE` error there means a peer conflict
  the check missed: fix the report rather than forcing it with `--force` or `--legacy-peer-deps`. After each step, run the repo's build and tests (from the README, CLAUDE.md, the CI
  pipeline, or the conventional command). If something breaks, fix it if the fix is small and clearly part of the upgrade.
  Otherwise revert that step and report it. Don't commit unless the user asks. If they do, make one commit per group.
- **Machine:** upgrade the named packages, never `--all`, unless the user picked everything. Commands that need admin or
  sudo, or that restart a running app (Docker Desktop, VS Code), should be listed for the user to run rather than run by
  you. Ask them to run anything interactive with `! <command>`.
- **VS Code:** see the apply section of [references/vscode.md](references/vscode.md). Extension updates take effect after a
  window reload.

Finish with what you changed, the build and test results, and what's still outstanding and why.

# Machine checks

Check the developer tools installed on this machine. Use the OS package managers first, because they cover most tools in one
call. Then check what they don't manage.

## Detection

1. **OS and shell.** On Windows, the Bash tool runs Git Bash and PowerShell is also available. Use whichever the command
   needs. `winget`, `choco` and `scoop` work from both.
2. **Package managers present:** `winget`, `choco`, `scoop` (Windows); `brew`, `mas`, `port` (macOS); `apt`, `dnf`, `pacman`,
   `zypper`, `snap`, `flatpak`, `brew` (Linux).
3. **Where each tool came from.** Find the executable (`Get-Command <tool>` / `where.exe <tool>` on Windows, `command -v` and
   `readlink -f` elsewhere) and read the path. Paths under `WinGet\Packages`, `scoop\apps`, `chocolatey\bin`,
   `/opt/homebrew`, `/usr/local/Cellar`, `~/.nvm`, `~/.volta`, `~/.dotnet`, `~/.cargo`, `~/.local/bin` (pipx/uv) or
   `/usr/bin` (distro) tell you which manager owns it. Report each tool once, under the manager that owns it.

Only check tools that are installed. Missing tools aren't findings.

## OS package managers

| Manager | List updates (read-only) | Apply one |
| --- | --- | --- |
| winget | `winget upgrade --include-unknown --accept-source-agreements` (refresh first with `winget source update`) | `winget upgrade --id <Id> -e --accept-package-agreements --accept-source-agreements` |
| Chocolatey | `choco outdated -r` | `choco upgrade <pkg> -y` (needs an elevated shell) |
| Scoop | `scoop update` (refreshes buckets only), then `scoop status` | `scoop update <app>` |
| Homebrew | `brew update` (metadata only), then `brew outdated --json=v2` (add `--greedy` for self-updating casks) | `brew upgrade <formula>` / `brew upgrade --cask <cask>` |
| Mac App Store | `mas outdated` | `mas upgrade <id>` |
| macOS | `softwareupdate --list` | List for the user. It needs a restart and admin. |
| apt | `apt list --upgradable` (stale unless `apt update` ran recently. That needs sudo, so don't run it; say how old the lists are from `/var/lib/apt/lists` timestamps) | List the `sudo apt install --only-upgrade <pkg>` command for the user |
| dnf | `dnf check-update` (exit code 100 means updates exist) | List for the user (`sudo`) |
| pacman | `checkupdates` (from pacman-contrib) | List for the user (`sudo`) |
| snap / flatpak | `snap refresh --list` / `flatpak remote-ls --updates` | `snap refresh <name>` / `flatpak update <ref>` |

The winget and choco lists include every desktop app on the machine. Report all of them, but put developer tools first
(editors, SDKs, runtimes, CLIs, Git, Docker, terminals, browsers used for testing) and summarize the rest in one line,
unless the user wants the full list.

## Toolchains and SDKs

Check only what the package managers above don't own.

| Tool | Current | Latest / status |
| --- | --- | --- |
| .NET | `dotnet --list-sdks`, `dotnet --list-runtimes` | `dotnet sdk check` reports patched and out-of-support SDKs and runtimes directly. Workloads: `dotnet workload list`, apply with `dotnet workload update` |
| Node.js | `node -v` (and `nvm list` / `fnm list` / `volta list` if a version manager owns it) | `https://nodejs.org/dist/index.json`: latest patch of the installed major, plus the newest LTS. Flag EOL majors (endoflife.date `nodejs`) |
| npm / pnpm / yarn | `npm -v`, `pnpm -v`, `yarn -v`, `corepack --version` | `npm view <name> version` |
| Python | `python --version` / `py --list` (Windows) | endoflife.date `python`, `https://www.python.org/downloads/` |
| Java | `java -version`; list JDKs (`/usr/libexec/java_home -V`, `sdk list java` with SDKMAN, or the Adoptium/Microsoft folders under Program Files) | endoflife.date `eclipse-temurin` / `microsoft-build-of-openjdk`. Report the latest patch of each installed major |
| Go | `go version` | `https://go.dev/dl/?mode=json` |
| Rust | `rustup check` (reports toolchain and rustup updates) | apply with `rustup update` |
| Gradle (global) | `gradle --version` | `https://services.gradle.org/versions/current`. Projects use their wrapper, so this is low priority |
| Android SDK | `sdkmanager --list_installed` (from `$ANDROID_HOME/cmdline-tools/latest/bin`) | `sdkmanager --list` includes an "Available Updates" section. Apply with `sdkmanager --update` |
| Xcode (macOS) | `xcodebuild -version`, `xcode-select -p` | Apple developer releases page. List the update for the user, who installs it from the App Store or with `xcodes` |
| Terraform | `terraform version` (prints an "out of date" notice itself) | `https://checkpoint-api.hashicorp.com/v1/check/terraform` (`current_version`) |

## Global packages and tools

| Kind | List | Latest | Apply |
| --- | --- | --- | --- |
| npm globals | `npm outdated -g --depth=0 --json` | (included) | `npm install -g <pkg>@latest` |
| pnpm globals | `pnpm outdated -g` | (included) | `pnpm add -g <pkg>@latest` |
| .NET global tools | `dotnet tool list -g` | NuGet flatcontainer (see repository.md) | `dotnet tool update -g <id>` |
| pipx | `pipx list --short` | PyPI JSON | `pipx upgrade <pkg>` |
| uv tools | `uv tool list` | PyPI JSON | `uv tool upgrade <pkg>`. uv itself: `uv self update` if it was installed standalone |
| cargo installs | `cargo install --list` (`cargo install-update -l` if cargo-update is installed) | crates.io | `cargo install <crate>` |
| Go binaries | `ls $(go env GOPATH)/bin` + `go version -m <binary>` for the module path | Go proxy | `go install <module>@latest` |
| gem / composer globals | `gem outdated` / `composer global outdated` | (included) | `gem update <gem>` / `composer global update <pkg>` |

## Standalone CLIs

These are often installed with their own installer. If a package manager owns one, it's already covered.

| CLI | Current | Latest |
| --- | --- | --- |
| Git | `git --version` | `https://api.github.com/repos/git-for-windows/git/releases/latest` (Windows) or `https://git-scm.com/` |
| GitHub CLI | `gh --version` | `gh api repos/cli/cli/releases/latest --jq .tag_name` |
| AWS CLI v2 | `aws --version` | `https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst` (first version heading) |
| AWS SAM CLI | `sam --version` | `gh api repos/aws/aws-sam-cli/releases/latest --jq .tag_name` |
| Azure CLI | `az version -o json` (`azure-cli`, plus `extensions`) | `gh api repos/Azure/azure-cli/releases/latest --jq .tag_name`. Extensions: `az extension list-available -o table` (shows `UpdateAvailable`) |
| Azure DevOps CLI | included in `az version` extensions | as above |
| Docker | `docker version --format '{{.Client.Version}}'` | Docker Desktop updates itself (Settings → Software updates). Docker Engine on Linux comes from the distro or Docker repo |
| kubectl / helm | `kubectl version --client -o json` / `helm version --short` | `https://dl.k8s.io/release/stable.txt` / `gh api repos/helm/helm/releases/latest` |
| Claude Code | `claude --version` | `npm view @anthropic-ai/claude-code version`. Apply with `claude update` |
| Firebase / Vercel / Netlify / other npm-installed CLIs | covered by npm globals | |
| XcodeGen / SwiftLint / CocoaPods | `xcodegen --version`, `swiftlint version`, `pod --version` | usually Homebrew-owned; otherwise GitHub releases / `gem` |

## Applying

- Upgrade only the items the user picked, one at a time, and confirm the new version with the tool's own `--version`.
- Don't run anything that needs admin or sudo, closes or restarts a running app, or reboots the machine. List those commands
  for the user. On Windows, an elevated `choco upgrade` and some winget installers prompt for UAC. Tell the user to expect the
  prompt or to run the command in an elevated shell.
- If a version manager (nvm, fnm, volta, asdf, mise, SDKMAN, pyenv, rustup) owns a runtime, install the new version
  next to the old one, and say which project pins (`.nvmrc`, `global.json`) still point at the old one.
- Interactive installers or commands that ask for credentials: ask the user to run them with `! <command>`.

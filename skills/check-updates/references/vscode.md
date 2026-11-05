# VS Code checks

Covers VS Code itself, its installed extensions, and the workspace's recommended extensions. The same steps work for
Insiders (`code-insiders`). VS Code forks (Cursor, Windsurf, VSCodium) use their own CLI name. VSCodium and most forks
use Open VSX rather than the Visual Studio Marketplace (see below).

## Detection

- CLI: `code --version` (line 1 is the version, line 3 the architecture). On Windows the CLI is `code.cmd`. If `code` isn't
  on PATH, try `%LOCALAPPDATA%\Programs\Microsoft VS Code\bin\code.cmd` (user install) or
  `%ProgramFiles%\Microsoft VS Code\bin\code.cmd` (system install). On macOS, try
  `/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code`.
- If the session runs inside VS Code's integrated terminal or the Claude Code extension, `code` usually works already.
- **Remote sessions:** inside WSL, SSH or a dev container, `code --list-extensions` lists the *remote* extensions. Say which
  side you checked. Local UI extensions (themes, keymaps) live on the local host.

## VS Code itself

- Current: `code --version`.
- Latest stable: `https://update.code.visualstudio.com/api/releases/stable` returns a JSON array of versions, newest first.
  Insiders builds update daily, so don't report them as outdated.
- VS Code usually updates itself. If it's behind, check `update.mode` in the user `settings.json` (`none` or `manual` turns
  automatic updates off) and say so.

## Installed extensions

1. List them: `code --list-extensions --show-versions` → `publisher.name@1.2.3` per line.
2. Get the latest versions in **one** Marketplace query for all of them:

   ```
   POST https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery
   Accept: application/json;api-version=3.0-preview.1
   Content-Type: application/json

   {"filters":[{"criteria":[
       {"filterType":8,"value":"Microsoft.VisualStudio.Code"},
       {"filterType":7,"value":"ms-dotnettools.csharp"},
       {"filterType":7,"value":"esbenp.prettier-vscode"}
     ],"pageNumber":1,"pageSize":100}],
    "flags":17}
   ```

   `filterType` 7 is the extension name and 8 the target. `flags` 17 means include versions (1) plus version properties (16).
   For each `results[0].extensions[]` entry, `versions[]` is newest first. Pick the first version that:
   - isn't a pre-release: its `properties` has no `Microsoft.VisualStudio.Code.PreRelease` set to `true`, unless the
     installed version is itself a pre-release,
   - supports the installed VS Code version: `Microsoft.VisualStudio.Code.Engine` (for example `^1.95.0`) allows it,
   - matches the platform if `targetPlatform` is set (`win32-x64`, `darwin-arm64`, `linux-x64`, …). Untargeted versions
     are universal.

   In bash, build the body with a heredoc and send it with `curl -s -X POST ... --data @body.json`. Batches of up to 100
   names per query are fine.
3. Extensions missing from the response were removed from the Marketplace, are private (installed from a VSIX), or come
   from a fork's registry. Report them under **Not checked** with the reason. An extension that was *removed* from the
   Marketplace is worth flagging, because removals are sometimes for security reasons. Tell the user to look at it in the
   Extensions view, which shows the reason and any replacement.
4. Deprecations: the Extensions view marks deprecated extensions and suggests replacements. The Marketplace query doesn't
   reliably expose this, so if an extension has had no release in a long time (`lastUpdated` more than 2 years ago), note
   it as "possibly unmaintained" rather than claiming it's deprecated.

**Open VSX (VSCodium and forks):** `https://open-vsx.org/api/<publisher>/<name>/latest` returns `version` and `engines.vscode`.

If `extensions.autoUpdate` is on (the default) and VS Code is running, most extensions will update on their own. Say so
in the report, and still list them, because extensions that are disabled or awaiting a reload don't update.

## Workspace recommendations

If the repo has `.vscode/extensions.json` (or `extensions.recommendations` in a `*.code-workspace` file):
- **Recommended but not installed:** list them, because the workspace expects them.
- **`unwantedRecommendations` that are installed:** list them as a note.
- **Recommendations that no longer exist** on the Marketplace (absent from the query above): suggest removing or
  replacing them in `extensions.json`. That counts as a repo change.

Also check that tool versions the workspace configures (for example `dotnet.server.path`, `java.jdt.ls.java.home`,
`python.defaultInterpreterPath`, `eslint.nodePath` in `.vscode/settings.json`) point to SDKs that still exist and aren't
EOL, using what the machine check found.

## Applying

- All extensions: `code --update-extensions`. Specific ones: `code --install-extension <publisher.name>@<version> --force`
  or `code --install-extension <publisher.name> --force` for the latest.
- Install missing recommendations with `code --install-extension <publisher.name>` after the user approves.
- New extension versions load after **Developer: Reload Window**. Tell the user. Don't try to restart VS Code yourself.
- VS Code itself: tell the user to use **Help → Check for Updates** (macOS: **Code → Check for Updates**), or run
  `winget upgrade --id Microsoft.VisualStudioCode -e` / `brew upgrade --cask visual-studio-code` if a package manager owns
  it. Updating closes VS Code, which also ends this session if it runs in the extension, so list the command for the
  user rather than running it.

# AI Skills

Skills for [Claude Code](https://claude.com/claude-code). A skill is a folder with a `SKILL.md` file (plus optional
reference files) that teaches Claude how to do a specific task. Claude loads it automatically when your request matches
the skill's description. You can also run it directly as a slash command, such as `/new-app`.

## Skills

| Skill | What it does |
| --- | --- |
| [`new-app`](skills/new-app/SKILL.md) | Scaffolds a new multi-platform product on our standard stack: .NET 10 minimal API on AWS Lambda with MongoDB, a React Router + Mantine web app, a Kotlin/Jetpack Compose Android app, a SwiftUI iOS app (XcodeGen), AWS CloudFormation infrastructure, Azure DevOps pipelines, and Amazon Cognito sign-in (email, Google, Apple). Every layer includes a working registration / profile / account-deletion feature to use as the pattern for new features. The stack is defined in [`skills/new-app/references/`](skills/new-app/references/). Edit those files to change it. |

## Install

### As a plugin (recommended)

This repo is a Claude Code plugin marketplace. In a Claude Code session, run:

```
/plugin marketplace add <repo-url>
/plugin install ai-skills@nik-yo
```

`<repo-url>` is the git URL of this repo, or `owner/repo` if it's on GitHub. A local clone's path also works. If the
repo is private, git on your machine must already be signed in to the host, because Claude Code can't prompt for
credentials.

Plugin skills are namespaced, so run the skill as `/ai-skills:new-app`. Claude also picks it up automatically when your
request matches.

**Updates:** run `/plugin marketplace update nik-yo`, or open `/plugin` → **Marketplaces** → `nik-yo` →
**Enable auto-update** to receive new commits automatically.

**Share with a team:** in a project repo, run `claude plugin marketplace add <repo-url> --scope project` and commit the
`.claude/settings.json` file it writes. Teammates are then offered the marketplace when they open that project.

### With the install script

If you don't want a plugin, clone this repo and run the install script from its root. It copies the skills into
Claude Code's skills folder, where they run without a prefix (`/new-app`).

**Windows (PowerShell)**

```powershell
.\install.ps1
```

**macOS / Linux / Git Bash**

```sh
./install.sh
```

By default, the skills are installed for your user (`~/.claude/skills/`) and are available in every project.

To install the skills into a single project instead (`<project>/.claude/skills/`, which you can commit so your team gets them too):

```powershell
.\install.ps1 -Project C:\code\my-app
```
```sh
./install.sh --project ~/code/my-app
```

To install only some of the skills, list them by name:

```powershell
.\install.ps1 new-app
```
```sh
./install.sh new-app
```

Running the script again overwrites the installed copies with the versions in this repo. To update, `git pull` and run it again.

> If PowerShell blocks the script, run it with
> `powershell -ExecutionPolicy Bypass -File .\install.ps1`.

### Manual install

You can also copy each folder under `skills/` yourself:

| Scope | Location |
| --- | --- |
| You, in all projects | `~/.claude/skills/<skill-name>/` (Windows: `%USERPROFILE%\.claude\skills\<skill-name>\`) |
| One project | `<project>/.claude/skills/<skill-name>/` |

Keep each skill's folder structure as it is. `SKILL.md` must be at the top level of the skill's folder.

## Use

Start a new Claude Code session after you install. Then either:

- describe what you want, e.g. *"Start a new app called Acme with our stack"*, and Claude picks up the skill, or
- invoke it directly: `/ai-skills:new-app Acme C:\code\acme acme.com` (or `/new-app ...` if you used the install script)

To check that Claude found the skills, run `/skills` in Claude Code. The installed skills appear in that list.

## Adding a skill

Create `skills/<skill-name>/SKILL.md` with `name` and `description` frontmatter, and add the skill to the table above.
The plugin and the install scripts both pick up every folder under `skills/` that contains a `SKILL.md`, so no other
change is needed. After editing, run `claude plugin validate .` to check the manifests in
[`.claude-plugin/`](.claude-plugin/).

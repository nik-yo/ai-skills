# AI Skills

Skills for [Claude Code](https://claude.com/claude-code). A skill is a folder with a `SKILL.md` file (plus optional
reference files) that teaches Claude how to do a specific task. Claude loads it automatically when your request matches
the skill's description. You can also run it directly as a slash command, such as `/ai-skills:new-app`.

## Skills

| Skill | What it does |
| --- | --- |
| [`new-app`](skills/new-app/SKILL.md) | Scaffolds a new multi-platform product on our standard stack: .NET 10 minimal API on AWS Lambda with MongoDB, a React Router + Mantine web app, a Kotlin/Jetpack Compose Android app, a SwiftUI iOS app (XcodeGen), AWS CloudFormation infrastructure, Azure DevOps pipelines, and Amazon Cognito sign-in (email, Google, Apple). Every layer includes a working registration / profile / account-deletion feature to use as the pattern for new features. The stack is defined in [`skills/new-app/references/`](skills/new-app/references/). Edit those files to change it. |

## Install

### As a Claude Code plugin (recommended)

This repo is a Claude Code plugin marketplace named `nik-yo`. It contains one plugin, `ai-skills`, which bundles every
skill in [`skills/`](skills/). You don't need to clone the repo. Claude Code fetches it for you.

**1. Add the marketplace.** This tells Claude Code where to find the plugin. You only do this once.

```
/plugin marketplace add nik-yo/ai-skills
```

**2. Install the plugin.**

```
/plugin install ai-skills@nik-yo
```

`ai-skills` is the plugin, and `nik-yo` is the marketplace. Install for **user** scope if you want the skills in every
project.

**3. Start a new session** (or run `/reload-plugins`), then check that the skill loaded by running `/skills`.
`ai-skills:new-app` appears in the list.

You can also do steps 1 and 2 from a terminal instead of a Claude Code session:

```sh
claude plugin marketplace add nik-yo/ai-skills
claude plugin install ai-skills@nik-yo
```

**In the VS Code extension:**

1. Type `/plugins` in the chat box to open **Manage plugins**.
2. On the **Marketplaces** tab, enter `nik-yo/ai-skills`.
3. On the **Plugins** tab, find **ai-skills**, click **Install**, and choose **Install for you**.

The extension and the CLI share plugin settings, so a plugin installed in one is available in the other.

#### Using the skills

Plugin skills get the plugin name as a prefix, so run the skill as `/ai-skills:new-app`. Claude also uses it
automatically when your request matches. You don't have to type the command.

#### Updating

Claude Code doesn't pull new commits until you ask it to. You have two ways to update:

- run `/plugin marketplace update nik-yo`, then restart the session, or
- open `/plugin` → **Marketplaces** → `nik-yo` → **Enable auto-update** to update in the background from then on.

#### Uninstalling

```
/plugin uninstall ai-skills@nik-yo
/plugin marketplace remove nik-yo
```

#### Sharing with a team

To offer the plugin to everyone who works in a project, run this in that project's folder:

```sh
claude plugin marketplace add nik-yo/ai-skills --scope project
```

Then commit the `.claude/settings.json` file it writes. When teammates open the project in Claude Code and trust the
folder, the marketplace is added for them, and they install the plugin with step 2.

### With the install script

If you don't want a plugin, clone this repo and run the install script from its root. It copies the skills into
Claude Code's skills folder, where they run without a prefix (`/new-app`).

```sh
git clone https://github.com/nik-yo/ai-skills.git
cd ai-skills
```

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

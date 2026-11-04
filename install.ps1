<#
.SYNOPSIS
  Installs the skills in this repo into Claude Code.
.EXAMPLE
  .\install.ps1                      # all skills, for your user (~/.claude/skills)
  .\install.ps1 -Project C:\code\app # all skills, for one project (<project>/.claude/skills)
  .\install.ps1 new-app              # only the named skill(s)
#>
param(
    [string]$Project,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Skills
)
$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'skills'
$target = if ($Project) { Join-Path $Project '.claude\skills' } else { Join-Path $HOME '.claude\skills' }

$available = Get-ChildItem $source -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'SKILL.md') }
if ($Skills) {
    $unknown = $Skills | Where-Object { $_ -notin $available.Name }
    if ($unknown) { throw "Unknown skill(s): $($unknown -join ', '). Available: $($available.Name -join ', ')" }
    $available = $available | Where-Object { $_.Name -in $Skills }
}

New-Item -ItemType Directory -Force -Path $target | Out-Null
foreach ($skill in $available) {
    $dest = Join-Path $target $skill.Name
    if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
    Copy-Item -Recurse $skill.FullName $dest
    Write-Host "Installed $($skill.Name) -> $dest"
}
Write-Host "Done. Restart Claude Code (or start a new session) to pick up the skills."

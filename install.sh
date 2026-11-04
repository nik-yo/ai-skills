#!/usr/bin/env sh
# Installs the skills in this repo into Claude Code.
#
#   ./install.sh                         # all skills, for your user (~/.claude/skills)
#   ./install.sh --project ~/code/app    # all skills, for one project (<project>/.claude/skills)
#   ./install.sh new-app                 # only the named skill(s)
set -eu

source_dir="$(cd "$(dirname "$0")" && pwd)/skills"
target="$HOME/.claude/skills"

if [ "${1:-}" = "--project" ]; then
  [ -n "${2:-}" ] || { echo "Usage: $0 --project <path> [skill...]" >&2; exit 1; }
  target="$2/.claude/skills"
  shift 2
fi

if [ "$#" -eq 0 ]; then
  set -- $(for d in "$source_dir"/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done)
fi

mkdir -p "$target"
for skill in "$@"; do
  if [ ! -f "$source_dir/$skill/SKILL.md" ]; then
    echo "Unknown skill: $skill" >&2
    exit 1
  fi
  rm -rf "${target:?}/$skill"
  cp -R "$source_dir/$skill" "$target/$skill"
  echo "Installed $skill -> $target/$skill"
done
echo "Done. Restart Claude Code (or start a new session) to pick up the skills."

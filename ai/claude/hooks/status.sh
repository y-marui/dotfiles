#!/bin/sh
input=$(cat)

PERCENT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')

GIT=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$BRANCH" ]; then
    BRANCH=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  fi

  MODIFIED=$(git --no-optional-locks -C "$cwd" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  UNTRACKED=$(git --no-optional-locks -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  UNPUSHED=$(git --no-optional-locks -C "$cwd" rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')
  UNPULLED=$(git --no-optional-locks -C "$cwd" rev-list 'HEAD..@{u}' 2>/dev/null | wc -l | tr -d ' ')

  GIT=" | ${BRANCH}"
  [ "$UNPULLED" != "0" ] && GIT="${GIT} ↓${UNPULLED}"
  [ "$UNPUSHED" != "0" ] && GIT="${GIT} ↑${UNPUSHED}"
  [ "$MODIFIED"  != "0" ] && GIT="${GIT} !${MODIFIED}"
  [ "$UNTRACKED" != "0" ] && GIT="${GIT} ?${UNTRACKED}"
fi

echo "Ctx: ${PERCENT}%${GIT}"

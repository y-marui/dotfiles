#!/bin/sh
input=$(cat)

PERCENT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')

# ANSI colors matching Powerlevel10k's vcs palette (256-color)
GREEN=$(printf '\033[38;5;76m')
YELLOW=$(printf '\033[38;5;178m')
BLUE=$(printf '\033[38;5;39m')
RED=$(printf '\033[38;5;196m')
RESET=$(printf '\033[0m')

GIT=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$BRANCH" ]; then
    BRANCH=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null | cut -c1-8)
  fi

  STAGED=$(git --no-optional-locks -C "$cwd" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  UNSTAGED=$(git --no-optional-locks -C "$cwd" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
  UNTRACKED=$(git --no-optional-locks -C "$cwd" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  UNPUSHED=$(git --no-optional-locks -C "$cwd" rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')
  UNPULLED=$(git --no-optional-locks -C "$cwd" rev-list 'HEAD..@{u}' 2>/dev/null | wc -l | tr -d ' ')
  STASHES=$(git --no-optional-locks -C "$cwd" stash list 2>/dev/null | wc -l | tr -d ' ')
  CONFLICTS=$(git --no-optional-locks -C "$cwd" diff --name-only --diff-filter=U 2>/dev/null | wc -l | tr -d ' ')
  GIT_DIR=$(git --no-optional-locks -C "$cwd" rev-parse --git-dir 2>/dev/null)

  # Branch name with  icon (Nerd Font \uF126), green
  GIT=" | ${GREEN}git:${BRANCH}${RESET}"
  # ⇣N⇡N — p10k style: no space between them when both present
  if [ "$UNPULLED" != "0" ] && [ "$UNPUSHED" != "0" ]; then
    GIT="${GIT} ${GREEN}⇣${UNPULLED}⇡${UNPUSHED}${RESET}"
  elif [ "$UNPULLED" != "0" ]; then
    GIT="${GIT} ${GREEN}⇣${UNPULLED}${RESET}"
  elif [ "$UNPUSHED" != "0" ]; then
    GIT="${GIT} ${GREEN}⇡${UNPUSHED}${RESET}"
  fi
  # *N stashes — green
  [ "$STASHES"  != "0" ] && GIT="${GIT} ${GREEN}*${STASHES}${RESET}"
  # VCS action (merge/rebase/cherry-pick etc.) — red
  ACTION=""
  if [ -f "${GIT_DIR}/MERGE_HEAD" ];                                    then ACTION="merge"
  elif [ -d "${GIT_DIR}/rebase-merge" ] || [ -d "${GIT_DIR}/rebase-apply" ]; then ACTION="rebase"
  elif [ -f "${GIT_DIR}/CHERRY_PICK_HEAD" ];                            then ACTION="cherry-pick"
  elif [ -f "${GIT_DIR}/REVERT_HEAD" ];                                 then ACTION="revert"
  elif [ -f "${GIT_DIR}/BISECT_LOG" ];                                  then ACTION="bisect"
  fi
  [ -n "$ACTION" ] && GIT="${GIT} ${RED}${ACTION}${RESET}"
  # ~N conflicts — red
  [ "$CONFLICTS" != "0" ] && GIT="${GIT} ${RED}~${CONFLICTS}${RESET}"
  # +N staged — yellow
  [ "$STAGED"   != "0" ] && GIT="${GIT} ${YELLOW}+${STAGED}${RESET}"
  # !N unstaged — yellow
  [ "$UNSTAGED" != "0" ] && GIT="${GIT} ${YELLOW}!${UNSTAGED}${RESET}"
  # ?N untracked — blue
  [ "$UNTRACKED" != "0" ] && GIT="${GIT} ${BLUE}?${UNTRACKED}${RESET}"
fi

printf "Ctx: %s%%%s\n" "${PERCENT}" "${GIT}"

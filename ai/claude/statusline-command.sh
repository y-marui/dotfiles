#!/bin/sh
# Claude Code statusline: ブランチ名、ステージ済み、未コミット、未プッシュコミット数、コンテキスト使用率を表示

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // .workspace.current_dir // ""')

# コンテキスト使用率
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# git 情報
git_part=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # ブランチ名
  branch=$(git --no-optional-locks -C "$cwd" symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git --no-optional-locks -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  fi

  # ステージ済み変更数（インデックスと HEAD の差分ファイル数）
  staged=$(git --no-optional-locks -C "$cwd" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')

  # 未コミット変更数（作業ツリーとインデックスの差分ファイル数）
  unstaged=$(git --no-optional-locks -C "$cwd" diff --numstat 2>/dev/null | wc -l | tr -d ' ')

  # 未プッシュコミット数
  unpushed=$(git --no-optional-locks -C "$cwd" log --oneline "@{u}..HEAD" 2>/dev/null | wc -l | tr -d ' ')

  git_part=$(printf "%s | staged:%s unstaged:%s unpushed:%s" "$branch" "$staged" "$unstaged" "$unpushed")
fi

# 出力の組み立て
if [ -n "$git_part" ] && [ -n "$used" ]; then
  printf " %s | %d%% context" "$git_part" "$used"
elif [ -n "$git_part" ]; then
  printf " %s" "$git_part"
elif [ -n "$used" ]; then
  printf " %d%% context" "$used"
fi

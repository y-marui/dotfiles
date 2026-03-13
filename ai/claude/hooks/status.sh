#!/bin/bash

input=$(cat)

# コンテキスト使用率
PERCENT=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

# Git情報
GIT=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)

    # ブランチ名が取得できた場合のみ表示
    if [ -n "$BRANCH" ]; then
        # 変更されたファイル (modified + deleted)
        MODIFIED=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')

        # 未追跡ファイル
        UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

        # プッシュされていないコミット (ahead)
        UNPUSHED=$(git rev-list '@{u}..HEAD' 2>/dev/null | wc -l | tr -d ' ')

        # プルされていないコミット (behind)
        UNPULLED=$(git rev-list 'HEAD..@{u}' 2>/dev/null | wc -l | tr -d ' ')

        GIT=" | ${BRANCH}"
        [ "$UNPULLED" != "0" ] && GIT="${GIT} ↓${UNPULLED}"
        [ "$UNPUSHED" != "0" ] && GIT="${GIT} ↑${UNPUSHED}"
        [ "$MODIFIED" != "0" ] && GIT="${GIT} !${MODIFIED}"
        [ "$UNTRACKED" != "0" ] && GIT="${GIT} ?${UNTRACKED}"
    fi
fi

# 出力
echo "Ctx: ${PERCENT}%${GIT}"

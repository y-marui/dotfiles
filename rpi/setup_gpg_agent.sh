#!/usr/bin/env bash
# setup_gpg_agent.sh
# SSH切断後もZellij内からGitHubへpull/pushできるよう、gpg-agentのssh-support
# （enable-ssh-support）を固定の永続SSHエージェントとして構成する（冪等）。
#
# 前提: shell/zshrc がSSH_CONNECTION時のみ ~/.ssh/auth_sock を
#       フォワードされたsocket → 生きていなければこのgpg-agentのssh-socket
#       の順でフォールバックする（Pi以外のローカルセッションには影響しない）。
#
# このスクリプトが行うこと:
#   1. gpg-agent.conf に enable-ssh-support と長寿命の cache-ttl-ssh を設定
#   2. loginctl enable-linger で、SSHの最終セッション終了後も
#      systemd --user（= gpg-agent-ssh.socket）を維持する
#
# 行わないこと（手動対応が必要）:
#   - Pi専用SSH鍵の生成・GitHubへの公開鍵登録
#   - 鍵をgpg-agentへ永続化するための最初の `ssh-add`（パスフレーズ入力が必要なため）
#
# 使い方:
#   bash rpi/setup_gpg_agent.sh

set -euo pipefail

conf_dir="$HOME/.gnupg"
conf_file="$conf_dir/gpg-agent.conf"
# 1年（秒）。切断後もパスフレーズ再入力なしで運用し続けられるようにする。
cache_ttl=31536000

mkdir -p "$conf_dir"
chmod 700 "$conf_dir"
touch "$conf_file"

set_conf_line() {
  local key="$1" value="$2"
  if grep -qE "^${key}( |$)" "$conf_file"; then
    sed -i -E "s|^${key}( .*)?$|${key} ${value}|" "$conf_file"
  else
    echo "${key} ${value}" >>"$conf_file"
  fi
}

changed=false

if ! grep -qE "^enable-ssh-support$" "$conf_file"; then
  echo "enable-ssh-support" >>"$conf_file"
  changed=true
fi

for key in default-cache-ttl-ssh max-cache-ttl-ssh; do
  current="$(grep -E "^${key} " "$conf_file" 2>/dev/null | awk '{print $2}')"
  if [[ "$current" != "$cache_ttl" ]]; then
    set_conf_line "$key" "$cache_ttl"
    changed=true
  fi
done

if $changed; then
  gpgconf --kill gpg-agent 2>/dev/null || true
  gpgconf --launch gpg-agent
  echo "  CONF    gpg-agent.conf を更新しました（enable-ssh-support / cache-ttl-ssh=${cache_ttl}）"
else
  echo "  SKIP    gpg-agent.conf (すでに設定済みです)"
fi

if command -v loginctl >/dev/null 2>&1; then
  if [[ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" == "yes" ]]; then
    echo "  SKIP    linger (すでに有効です)"
  else
    sudo loginctl enable-linger "$USER"
    echo "  LINGER  loginctl enable-linger を設定しました（SSHログアウト後もgpg-agentが常駐します）"
  fi
else
  echo "  WARN    loginctl が見つかりません（systemd以外の環境の可能性）"
fi

ssh_key_count="$(find "$HOME/.ssh" -maxdepth 1 -name '*.pub' 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$ssh_key_count" -eq 0 ]]; then
  cat <<'EOS'
  NOTE    Pi専用のSSH鍵が見つかりません。次を1回だけ手動で実行してください:
            ssh-keygen -t ed25519 -C "<コメント>" -f ~/.ssh/<name>
            ssh-add ~/.ssh/<name>   # gpg-agentへの永続保存パスフレーズを設定
          公開鍵をGitHubに登録するのを忘れずに: https://github.com/settings/keys
EOS
fi

echo "  DONE    gpg-agent の SSH support 設定を確認しました"

# shellcheck shell=bash
# bin/unix/_sync-labpc-lib.sh
# sync-labpc から source される共通関数。
#
# ジョブ定義ファイル（HOST/SHARE/SMB_USER/REMOTE_SUBPATH/DEST を定義するシェル
# スニペット）を1件ずつ処理する。SMB共有は既にFinder等でマウント済みならそれを
# 再利用し（macOSのsmbfsは同一サーバー・共有・ユーザーの二重マウントを許可しない
# ため）、未マウントならこの関数が自前でマウントして処理後にアンマウントする。

# _labpc_url_encode <string>
# SMB URLへ埋め込むため、アカウント名中の予約文字（スペース・@ : / % 等）を
# パーセントエンコードする（例: "PPMS-External PC" → "PPMS-External%20PC"）
_labpc_url_encode() {
  local s="$1" out="" c i
  local LC_ALL=C
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    if [[ "$c" =~ [A-Za-z0-9.~_-] ]]; then
      out+="$c"
    else
      printf -v c '%%%02X' "'$c"
      out+="$c"
    fi
  done
  printf '%s' "$out"
}

# _labpc_sync_job <job-conf-file>
_labpc_sync_job() {
  local job_conf="$1"
  local HOST SHARE SMB_USER REMOTE_SUBPATH DEST
  # shellcheck source=/dev/null
  source "$job_conf"

  local own_mount_point="${HOME}/Library/Application Support/labpc-sync-mount-${HOST}-${SHARE}"
  local mount_point did_mount=0

  local existing_mount
  existing_mount=$(mount | grep -F "@${HOST}/${SHARE} on " | sed -E 's/.* on (.*) \(smbfs.*/\1/') || true

  if [[ -n "$existing_mount" ]]; then
    mount_point="$existing_mount"
    echo "  既存のマウントを使用: ${mount_point}"
  else
    mkdir -p "$own_mount_point"
    local encoded_user
    encoded_user="$(_labpc_url_encode "$SMB_USER")"
    echo "  mount_smbfs //${SMB_USER}@${HOST}/${SHARE} ..."
    if ! mount_smbfs "//${encoded_user}@${HOST}/${SHARE}" "$own_mount_point"; then
      echo "  error: マウントに失敗しました" >&2
      return 1
    fi
    mount_point="$own_mount_point"
    did_mount=1
  fi

  mkdir -p "$DEST"
  local status=0
  rsync -avh "${mount_point}/${REMOTE_SUBPATH}/" "${DEST}/" || status=$?

  if [[ "$did_mount" -eq 1 ]]; then
    umount "$mount_point" 2>/dev/null || true
  fi

  return "$status"
}

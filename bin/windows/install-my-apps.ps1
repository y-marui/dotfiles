#!/usr/bin/env pwsh
# install-my-apps: macOS 専用ツール（.app の DMG インストール）の Windows 側スタブ
#
# Windows では何もせず、専用の終了コード 64 で終了する。
# my-hosts が ssh 経由で apps を実行したとき、この終了コードを失敗ではなく skip として扱う。

[Console]::Error.WriteLine('install-my-apps は macOS 専用です（Windows では何もしません）。')
exit 64

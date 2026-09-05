#!/bin/bash
# FiveMエモート太郎 — 同期スクリプト（Mac / Linux）
#
# これ1本で「最新にする」「配ったものを更新する」が済みます。
#
#   ./tools/sync.sh            最新にする（GitHubから取得 → Dropboxの配布用コピーも更新）
#   ./tools/sync.sh --push     自分の変更をGitHubへ送ってから、同じことをする
#
# Dropbox の中は「読むだけの複製」です。あそこで編集しないでください。
# 万一あそこが編集されていたら、このスクリプトは上書きせずに止まります。

set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mirror="$HOME/Dropbox/claude-work/fivem-emote-taro"

push=0
force=0
message=""
while [ $# -gt 0 ]; do
  case "$1" in
    --push)    push=1 ;;
    --force)   force=1 ;;
    -m)        shift; message="$1" ;;
    *)         echo "知らない指定です: $1"; exit 1 ;;
  esac
  shift
done

sha() { shasum -a 256 "$1" | awk '{print toupper($1)}'; }

# ---- 1. 自分の変更を送る（--push のときだけ） --------------------------

if [ "$push" = "1" ]; then
  if [ -n "$(git -C "$repo" status --porcelain)" ]; then
    [ -n "$message" ] || message="更新 $(date '+%Y-%m-%d %H:%M')"
    echo "変更を記録します: $message"
    git -C "$repo" add -A
    git -C "$repo" commit -m "$message" >/dev/null
  fi
  echo 'GitHub へ送ります'
  git -C "$repo" push >/dev/null 2>&1
fi

# ---- 2. GitHub から最新を取る ------------------------------------------

if [ "$push" != "1" ] && [ -n "$(git -C "$repo" status --porcelain)" ]; then
  echo '※ 保存していない変更があります。先に送るなら --push を付けてください:'
  git -C "$repo" status --porcelain | sed 's/^/    /'
  echo ''
fi

echo 'GitHub から取得します'
git -C "$repo" pull --ff-only >/dev/null 2>&1
echo "  いまの版: $(git -C "$repo" rev-parse --short HEAD)  $(git -C "$repo" log -1 --format=%s)"

# ---- 3. 配布用コピー（Dropbox）を更新 ----------------------------------

if [ ! -d "$mirror" ]; then
  echo "配布用コピーが見つからないので飛ばします: $mirror"
  exit 0
fi

stamp="$mirror/.snapshot.json"

# 前回配った内容が書き換えられていないか調べる
if [ -f "$stamp" ] && [ "$force" != "1" ]; then
  edited=""
  while IFS=$'\t' read -r rel want; do
    [ -n "$rel" ] || continue
    f="$mirror/$rel"
    if [ ! -f "$f" ]; then edited="$edited\n    $rel（消えている）"; continue; fi
    [ "$(sha "$f")" = "$want" ] || edited="$edited\n    $rel"
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
for k,v in d["files"].items(): print(k+"\t"+v)
' "$stamp")
  if [ -n "$edited" ]; then
    echo ''
    echo '止めました。Dropbox の複製が編集されています:'
    printf "$edited\n"
    echo ''
    echo 'あそこは読むだけの場所です。その変更を残したいなら、中身を作業用フォルダへ'
    echo '持ってきてコミットしてください。捨ててよいなら --force で上書きします。'
    exit 1
  fi
fi

echo '配布用コピーを更新します'
tmp="$(mktemp)"
n=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  mkdir -p "$mirror/$(dirname "$rel")"
  cp -f "$repo/$rel" "$mirror/$rel"
  printf '%s\t%s\n' "$rel" "$(sha "$mirror/$rel")" >> "$tmp"
  n=$((n+1))
done < <(git -C "$repo" ls-files)

# 前回配ったが今回は無いファイルを片付ける
if [ -f "$stamp" ]; then
  while IFS=$'\t' read -r rel _; do
    [ -n "$rel" ] || continue
    grep -q "^$rel	" "$tmp" || { rm -f "$mirror/$rel" 2>/dev/null && echo "  削除: $rel"; }
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
for k,v in d["files"].items(): print(k+"\t"+v)
' "$stamp")
fi

python3 -c '
import json,sys,datetime,socket
files={}
for line in open(sys.argv[2],encoding="utf-8"):
    line=line.rstrip("\n")
    if not line: continue
    k,v=line.split("\t",1); files[k]=v
json.dump({"commit":sys.argv[3],
           "updated":datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
           "machine":socket.gethostname(),
           "files":files},
          open(sys.argv[1],"w",encoding="utf-8"), ensure_ascii=False, indent=2)
' "$stamp" "$tmp" "$(git -C "$repo" rev-parse HEAD)"
rm -f "$tmp"

echo "  $n ファイル。完了。"

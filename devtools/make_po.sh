#!/usr/bin/env bash
# 由 locale/en.tsv（每行：中文原文<TAB>英文）生成 Godot 使用的 locale/en.po。
# 界面源文本是中文；新增或修改界面文字后，在 en.tsv 里补一行再运行本脚本（Git Bash）。
set -euo pipefail
cd "$(dirname "$0")/.."
{
  cat <<'HEADER'
msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\n"
"Language: en\n"

HEADER
  awk -F'\t' 'NF == 2 && $1 != "" {
    gsub(/"/, "\\\"", $1); gsub(/"/, "\\\"", $2)
    printf "msgid \"%s\"\nmsgstr \"%s\"\n\n", $1, $2
  }' locale/en.tsv
} > locale/en.po
echo "locale/en.po: $(grep -c '^msgid "[^"]' locale/en.po) 条"

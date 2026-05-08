#!/usr/bin/env bash
# PreToolUse: 自動編集で破壊されたら困るファイル/ディレクトリへの Write|Edit を
# 事前ブロックする（exit 2 が PreToolUse のブロック規約）。
#
# 保護対象:
#   - gems.locked        … bundle install で生成。手編集禁止
#   - .ruby-lsp/         … LSP キャッシュ
#   - .git/              … 言うまでもなく
#   - docs/adr/0001-*    … 既決 ADR は手編集せず Superseded で別 ADR を作る
set -euo pipefail

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"

[[ -z "$FILE" ]] && exit 0

# パターンマッチ
case "$FILE" in
  */gems.locked|gems.locked)
    echo "BLOCKED: gems.locked は \`bundle install\` で更新します（CLAUDE.md 禁止事項）" >&2
    exit 2
    ;;
  */.git/*|*/.ruby-lsp/*)
    echo "BLOCKED: ${FILE} はツール管理領域のため直接編集禁止" >&2
    exit 2
    ;;
esac

exit 0

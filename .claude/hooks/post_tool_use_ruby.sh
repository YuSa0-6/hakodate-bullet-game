#!/usr/bin/env bash
# PostToolUse: Ruby ファイルを編集した直後に `ruby -c` で構文を検査し、
# エラーがあれば `additionalContext` 経由でエージェントへ注入する。
#
# Hook 仕様:
#   stdin  : Claude Code が JSON で tool 呼び出し情報を渡す
#   stdout : `hookSpecificOutput.additionalContext` を含む JSON を返すと
#            次のターンのコンテキストへ注入される（ブロックはしない）
#   exit 0 : 通常終了（stdout の JSON が解釈される）
set -euo pipefail

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"

# .rb 以外、空、test/ でないファイルはスキップ
[[ -z "$FILE" ]] && exit 0
[[ "$FILE" != *.rb ]] && exit 0
[[ ! -f "$FILE" ]] && exit 0

# ruby -c で構文チェック（rbenv shim 経由）
if ! ERR_OUTPUT="$(ruby -c "$FILE" 2>&1)"; then
  # JSON エンコードして additionalContext に注入
  CONTEXT="ruby -c failed for ${FILE}:
${ERR_OUTPUT}

FIX: 構文エラーを修正してください。CLAUDE.md の禁止事項を確認すること。"
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
  exit 0
fi

# frozen_string_literal: true マジックコメントの欠落を軽く警告（プロジェクト方針）
if ! head -3 "$FILE" | grep -qE '^# frozen_string_literal: true'; then
  CONTEXT="${FILE}: '# frozen_string_literal: true' が先頭にありません。
プロジェクト全体で magic comment を統一しています（gems.rb, lib/, test/ 参照）。"
  jq -n --arg ctx "$CONTEXT" '{
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $ctx
    }
  }'
fi

exit 0

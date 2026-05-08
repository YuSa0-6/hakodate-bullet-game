#!/usr/bin/env bash
# Stop hook: エージェントがターンを終えるタイミングで sus テストを走らせ、
# 失敗していれば additionalContext として最終ターンへ注入する。
#
# 「テスト通過が完了条件」（記事 MVH Week 2-4）を強制する。
#
# 環境変数:
#   CLAUDE_SKIP_STOP_TESTS=1 … 一時的にスキップ（探索的セッション用）
set -euo pipefail

if [[ "${CLAUDE_SKIP_STOP_TESTS:-0}" == "1" ]]; then
  exit 0
fi

cd "$(dirname "$0")/../.."

# .rb が一切変更されていないなら走らせる必要はない
if ! git diff --name-only HEAD 2>/dev/null | grep -qE '\.rb$' \
   && ! git ls-files --others --exclude-standard | grep -qE '\.rb$'; then
  exit 0
fi

# タイムアウト 60 秒（無限ループするテストの保険）。
# macOS のデフォルトには `timeout` が無いので、gtimeout (coreutils) があれば使う。
TIMEOUT_CMD=""
if command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_CMD="gtimeout 60"
elif command -v timeout >/dev/null 2>&1; then
  TIMEOUT_CMD="timeout 60"
fi

if OUTPUT="$(BUNDLE_GEMFILE=gems.rb BUNDLE_LOCKFILE=gems.locked \
            ${TIMEOUT_CMD} bundle exec sus test/ 2>&1)"; then
  exit 0
fi

# 失敗時のみ最後 40 行を抽出してフィードバック注入
TAIL="$(printf '%s\n' "$OUTPUT" | tail -40)"
CONTEXT="sus テスト失敗（Stop hook 検出）:

${TAIL}

FIX: テストが通る状態にしてからターンを終えてください。
スキップする場合は CLAUDE_SKIP_STOP_TESTS=1 を一時的に設定。"

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: $ctx
  }
}'

exit 0

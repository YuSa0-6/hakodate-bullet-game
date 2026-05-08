# frozen_string_literal: true

# テスト本文に日本語（マルチバイト）を含めるため、
# sus が File.read で読み込む際のデフォルト外部エンコーディングを UTF-8 に固定する。
# ロケール未設定（LANG="") の環境では US-ASCII になるため明示。
Encoding.default_external = Encoding::UTF_8 if Encoding.default_external != Encoding::UTF_8

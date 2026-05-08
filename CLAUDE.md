# async-cafe（ハコダテヴァーサス）

Ruby + Lively + Async ベースの 2 人対戦シューティング。

## コマンド
- 起動: `BUNDLE_GEMFILE=gems.rb BUNDLE_LOCKFILE=gems.locked bundle exec lively application.rb`
- テスト全実行: `bundle exec sus test/`
- 単一テスト: `bundle exec sus test/<file>.rb`
- 構文チェック: `ruby -c <file>.rb`

## ルーティング
- 描画変更 → `lib/views/renderers/{panel,center_gauge,screens}.rb`
- ゲームロジック → `lib/game/{battle,garbage_queue}.rb`
- エンティティ → `lib/entities/{player,boss,bullet,zako,food}.rb`
- 状態機械（:start/:playing/:result）→ `lib/views/battle_view.rb`
- テスト基盤 → `test/helper.rb`（TestBarrier / CaptureBuilder）

## 設計判断（ADR）
- [ADR-0001 固定 tick + 適応 render](docs/adr/0001-fixed-tick-adaptive-render.md)
- [ADR-0002 Producer/Consumer 分離](docs/adr/0002-producer-consumer-inboxes.md)
- [ADR-0003 Async::Barrier 注入必須](docs/adr/0003-barrier-injection.md)
- [ADR-0004 Extra モード（Konami 解放）](docs/adr/0004-extra-mode-and-konami-unlock.md)

## 禁止事項
- `gems.locked` を直接編集しない（`bundle install` で更新）
- リファクタや過剰な防御コードを追加しない（最小差分方針）
- mock を増やさない。Fiber ライフサイクルは実 `Async::Barrier` で検証
- `Battle.new` を `barrier:` なしで呼ばない（ADR-0003）
- 新規ドキュメント（`*.md`）を勝手に作らない（ADR で記録する）

## テスト方針
- 同期処理 → `TestBarrier`（Fiber 起動しない null 実装）
- Fiber ライフサイクル → `Sync { Async::Barrier ... barrier.wait }` で実 Fiber

## 言語
- 応答は日本語。コード識別子は英語のまま。

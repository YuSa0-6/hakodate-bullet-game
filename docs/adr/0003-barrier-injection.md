# ADR-0003: `Async::Barrier` 注入を必須化

- Status: Accepted
- Date: 2026-05-08

## Context
`Battle` / `Player` / `Boss` / `GarbageQueue` はそれぞれ Fiber を起動する。
グローバルな `Async {}` で起動すると teardown 時にリーク Fiber が残り、
次の対戦開始時に古い Fiber が干渉する不具合が出た。

## Decision
- すべての Fiber 起動主体は **コンストラクタで `barrier:` を必須引数として受ける**
- 例: `Battle.new(difficulty:, barrier:)`
- `BattleView#teardown_battle!` で `barrier.stop` を呼ぶことで全 Fiber を一括停止
- テストでも barrier を注入する。同期処理だけ見たい場合は `TestBarrier`（null 実装）

## Consequences
- 良い影響:
  - Fiber リークが構造的に発生しなくなる
  - テストで Fiber ライフサイクルそのものを検証できる
- トレードオフ:
  - barrier をコンストラクタチェーンで引き回す手間
  - グローバル `Async { ... }` ヘルパーが書けない
- 強制方法:
  - `Battle.new` を barrier なしで呼ぶテストは `ArgumentError` で落ちる
  - `test/helper.rb` に `TestBarrier` と実 barrier 用 `Sync { Async::Barrier ... }` の両方を用意
  - PostToolUse hook で `# frozen_string_literal: true` を含むファイル整備を促進

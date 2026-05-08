# ADR-0002: Producer/Consumer 分離（inbox 経由）

- Status: Accepted
- Date: 2026-05-08

## Context
Boss の弾幕パターンや food drop は Fiber から非同期に湧く。
これらが `Battle` の状態を直接書き換えると、
tick と Fiber でレースが発生し、当たり判定が壊れる。

## Decision
- 生成系 Fiber は `@bullet_inbox` / `@food_inbox` に **push のみ**
- `Battle#tick` の **先頭で drain** してから当たり判定・移動を回す
- inbox は thread-unsafe な `Array` で十分（同一 reactor 内で逐次化）

## Consequences
- 良い影響:
  - tick 内のデータ構造が単一スレッド相当として扱える
  - 弾の発生タイミングが決定論的になりテストが書ける
- トレードオフ:
  - 弾発生から判定まで最大 1 tick の遅延（≒ 33ms）
  - inbox を経由しない直接書き換えは禁止（レビューで弾く）
- 強制方法:
  - `test/battle.rb` で drain 順序を検証
  - 生成系コードは `barrier.async { @bullet_inbox << ... }` パターンを踏む

# ADR-0001: 固定 tick (30Hz) と適応 render (24fps)

- Status: Accepted
- Date: 2026-05-08

## Context
Lively (Live::View) は WebSocket 経由で HTML を差し替える方式のため、
描画コストが大きいと game tick まで引きずられる。
弾幕系ゲームの当たり判定は frame rate の揺らぎに敏感で、
tick がジッターするとプレイ体験が壊れる。

## Decision
- ロジック tick は **固定 30Hz**（`@tick_interval = 1.0 / 30`）
- 描画 (`update!`) は重いとき **24fps へ自動降格**する適応レンダリング
- tick と render は別ループ。tick が描画を待つことはない

## Consequences
- 良い影響:
  - 当たり判定・弾幕生成が安定する
  - 描画が重い局面でもゲーム性が劣化しない
- トレードオフ:
  - 描画タイミングと内部状態が必ずしも一致しない
  - render 側で snapshot を取る規律が必要
- 強制方法:
  - `BattleView#run_loop` で tick 周期は定数化済み
  - 適応 render の閾値は `lib/views/battle_view.rb` に集約

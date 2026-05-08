# ADR-0004: Extra モードを `Config::DIFF` の延長で表現し、Konami コードで解放する

- Status: Accepted
- Date: 2026-05-08

## Context
HARD を超える最難関 + 専用ギミック（コンボ閾値撤廃のサイン波弾常時送出、星形バーストの早期発動・二重放出）を持つ
"Extra" モードを追加したい。一方で：

- 既存の難易度は `Config::DIFFICULTIES = %i[easy normal hard]` と `Config::DIFF` の hash で表現され、
  `Battle` / `Boss` / `Player` がここから値を引いている（数値ベースの分岐は無く、パラメータ束として閉じている）
- 「分岐を新規導入する」設計（例えば `Battle#extra?` や `Mode` クラスの導入）は最小差分方針（CLAUDE.md）に反する
- 永続ストアは無い（`Config::TOP_SCORES` も in-memory）。クリア進度に依存した解放は実現難度に対して見返りが薄い

## Decision
1. **Extra は難易度の一種として `Config::DIFF[:extra]` に追加する**
   - `Config::DIFFICULTIES` には含めず、`Config::ALL_DIFFICULTIES` に区別を持たせる
   - 既存パラメータ（`squid` / `boss_hp` / `interval` 等）は HARD × 1.5 を基準に決める。`score_mult: 5`
2. **Extra 専用挙動はパラメータ拡張で表現する**（メソッド分岐を増やさない）
   - `wave_combo_threshold` : `Player#register_zako_kill!` でサイン波弾を送出するコンボ閾値（既存は固定 3 → `@diff[:wave_combo_threshold] || 3`）
   - `starburst_phase` / `starburst_cycle` / `starburst_duo` : `Boss#run_starburst_pattern` の発動タイミングと密度
   - HARD 以下では未指定のままなので既存挙動が保たれる（後方互換）
3. **解放はセッション内のみ（永続化しない）**
   - `BattleView` がタイトル画面で Konami シーケンス（`↑↑↓↓←→←→ b a`）を検出 → `@extra_unlocked = true`
   - 解放後は `available_difficulties` に `:extra` が加わり、`← →` で選択可能になる
   - リロードで揮発する。これで十分とする（隠し要素のシンプル実装）
4. **タイトル UI は表示制御のみで対応**
   - `Renderers::Screens.title` に `extra_unlocked:` キーワード引数を追加し、解放時のみ EXTRA タブと "★ EXTRA UNLOCKED ★" 表示を出す
   - `DIFF_DESC` に `:extra` の説明文を追加

## Consequences
- 良い影響:
  - 既存の `Battle` / `Boss` / `Player` のロジック分岐を増やさず、テーブル駆動で Extra 仕様が表現できる（最小差分方針に整合）
  - 新たな難易度を追加するのも同様にパラメータ追記で済む（HARD2 等の拡張可能性）
  - 解放状態が `BattleView` のインスタンス変数に閉じる → 外部状態が増えない
- 悪い影響 / トレードオフ:
  - パラメータが Extra-only 用に増える（`wave_combo_threshold` 等）。HARD 以下の hash には書かれず、`@diff[:key] || default` でデフォルトに頼る
  - Konami 解放は WebSocket 切断（リロード）で消える。実績/進度を永続化したくなったら別 ADR で再設計
  - キーシーケンス入力が難易度シフト（`← → a`）と競合しうるが、Konami は「現在期待しているキーに一致した入力だけ消費」する作りなので、未進入の矢印キーは通常通り難易度シフトに流れる
- リンタールール / テストでの強制方法:
  - `test/battle.rb` で `:extra` の Battle が起動できることを確認
  - `test/boss_pattern.rb` で `starburst_phase` / `starburst_duo` のパラメータが効くことを確認
  - `test/battle_view.rb` で Konami 受理・未解放時の `:extra` 非選択を確認
  - 設計逸脱（Extra 用に新クラスを作るなど）が起きたらこの ADR を Superseded にする

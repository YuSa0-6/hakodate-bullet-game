# Architecture Decision Records (ADR)

このディレクトリは、コードを読むだけでは復元できない **設計判断の理由** を記録する。

## 一覧
| # | タイトル | Status |
|---|---------|--------|
| [0001](0001-fixed-tick-adaptive-render.md) | 固定 tick (30Hz) と適応 render (24fps) | Accepted |
| [0002](0002-producer-consumer-inboxes.md) | Producer/Consumer 分離（inbox 経由） | Accepted |
| [0003](0003-barrier-injection.md) | `Async::Barrier` 注入を必須化 | Accepted |
| [0004](0004-extra-mode-and-konami-unlock.md) | Extra モードを `Config::DIFF` で表現し Konami で解放 | Accepted |

## ルール
- 既決 ADR は **手編集しない**。覆す場合は新しい ADR を立てて、旧 ADR の Status を `Superseded by ADR-XXXX` に更新する
- ADR は `template.md` をコピーして書く
- ADR を新設したら CLAUDE.md と本 README の一覧表に追加する

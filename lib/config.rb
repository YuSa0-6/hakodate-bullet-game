# frozen_string_literal: true

module Config
  # ── 全体レイアウト ── 16:9 でワイド画面占有率最大 ───────
  W = 1280
  H = 720

  PANEL_W = 500
  PANEL_H = 720               # 画面フル高
  HUD_H   = 36
  FIELD_W = PANEL_W
  FIELD_H = PANEL_H - HUD_H   # = 684

  GAUGE_W = 100               # 中央の送出ゲージ幅
  PANEL_GAP = (W - PANEL_W * 2 - GAUGE_W) / 2  # = 90

  # ── 自機 ───────────────────────────────────────
  P_SIZE  = 20
  P_SPEED = 5

  # ── 弾 ─────────────────────────────────────────
  B_SIZE       = 28
  SHOT_SIZE    = 14
  FOOD_SIZE    = 28
  ZAKO_SIZE    = 32
  BULLET_SPEED = 0.8

  # ── ボス ───────────────────────────────────────
  BOSS_W = 64
  BOSS_H = 48

  # ── フェーズ ──────────────────────────────────
  FPS              = 30
  WAVE_FRAMES      = FPS * 60          # 60秒で Boss フェーズへ
  GARBAGE_WARN_FRAMES = FPS * 2        # お邪魔の警告 → 出現までの猶予

  # ── 食べ物 / 雑魚カタログは Assets に集約 ─────────
  # （`require_relative 'assets'` は使う側で）

  # ── 難易度 ────────────────────────────────────
  DIFFICULTIES = %i[easy normal hard].freeze

  DIFF = {
    easy: {
      label: 'EASY',   color: '#4caf50', score_mult: 1,
      zako_interval: 50,
      squid: 5,  squid_vy: 4.0,
      ramen: 3,  ramen_vy: 2.5,
      sushi: 4,  sushi_sp: 2.8,
      burger_arms: 8,  burger_extra: false,
      bento_vx: 3.0,   bento_interval: 150,
      interval: 130,
      boss_hp: 360,  boss_vx: 2.8,
      food_interval: 100,  score_food: 50
    },
    normal: {
      label: 'NORMAL', color: '#ff9800', score_mult: 2,
      zako_interval: 38,
      squid: 7,  squid_vy: 5.0,
      ramen: 5,  ramen_vy: 3.4,
      sushi: 6,  sushi_sp: 3.8,
      burger_arms: 10, burger_extra: false,
      bento_vx: 4.0,   bento_interval: 110,
      interval: 100,
      boss_hp: 600,  boss_vx: 4.0,
      food_interval: 130, score_food: 40
    },
    hard: {
      label: 'HARD',   color: '#f44336', score_mult: 3,
      zako_interval: 28,
      squid: 10, squid_vy: 6.5,
      ramen: 7,  ramen_vy: 4.5,
      sushi: 9,  sushi_sp: 5.0,
      burger_arms: 12, burger_extra: true,
      bento_vx: 5.5,   bento_interval: 80,
      interval: 75,
      boss_hp: 900, boss_vx: 5.5,
      food_interval: 160, score_food: 30
    }
  }.freeze

  # ── 入力（同一キーボード2人） ───────────────────
  # JS の KeyboardEvent.key と location を Ruby に転送している
  P1_CONTROLS = {
    left:  %w[a A],
    right: %w[d D],
    up:    %w[w W],
    down:  %w[s S],
    focus: 'ShiftLeft'   # event[:loc] == 1 を区別
  }.freeze

  P2_CONTROLS = {
    left:  ['ArrowLeft'],
    right: ['ArrowRight'],
    up:    ['ArrowUp'],
    down:  ['ArrowDown'],
    focus: 'ShiftRight'  # event[:loc] == 2
  }.freeze

  # ── ハイスコア（メモリ保持） ─────────────────────
  TOP_SCORES = {easy: [], normal: [], hard: []}
end

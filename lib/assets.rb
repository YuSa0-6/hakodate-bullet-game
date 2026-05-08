# frozen_string_literal: true

# 画面に出るすべてのアイコン・絵文字・カタログデータの単一集約点。
# 「データはここ／挙動はエンティティ」の分離方針。
module Assets
  # ── 視覚アイコン ──────────────────────────────
  module Icons
    # 自機 / 自弾
    PLAYER     = '⭐'
    SHOT       = '★'
    LIFE_FULL  = '❤️'
    LIFE_EMPTY = '🖤'
    DEAD       = '💀'

    # 雑魚（敵キャラ）
    ZAKO_BASIC = '🐙'   # 基本：縦落下、HP1
    ZAKO_TANK  = '🐡'   # 硬い：HP3、ゆっくり
    ZAKO_AGILE = '🦐'   # 素早い：ジグザグ、HP1

    # ボス
    BOSS_BODY  = '🦑'
    BOSS_CROWN = '👑'

    # 弾
    BULLET_NORMAL  = '🫧'   # ボスから放出される通常弾
    BULLET_GARBAGE = '👻'   # 相手から送られてきたお邪魔弾

    # お邪魔の予告マーカー（受信中表示）
    WARNING = '⚠️'

    # 食べ物（取得で 3-WAY パワーアップ）
    FOOD_SQUID  = '🦑'
    FOOD_RAMEN  = '🍜'
    FOOD_SUSHI  = '🍣'
    FOOD_BURGER = '🍔'
    FOOD_BENTO  = '🍱'

    # UI / 演出
    LANTERN = '🏮'
    TROPHY  = '🏆'
    SCALE   = '⚖'
  end

  # ── カタログ：食べ物 ─────────────────────────────
  FOODS = [
    {emoji: Icons::FOOD_SQUID,  name: 'イカ刺し'},
    {emoji: Icons::FOOD_RAMEN,  name: '塩ラーメン'},
    {emoji: Icons::FOOD_SUSHI,  name: '海鮮丼'},
    {emoji: Icons::FOOD_BURGER, name: 'ラッキーピエロ'},
    {emoji: Icons::FOOD_BENTO,  name: 'やきとり弁当'}
  ].freeze

  # ── カタログ：雑魚（敵） ──────────────────────────
  # attack_type: 撃破時に相手へ送る弾幕パターン (Bullet.attack_pattern が解釈)
  ZAKO_TYPES = [
    {emoji: Icons::ZAKO_BASIC, hp: 1, vy: 1.6, score: 30, garbage: 1, weave: false, attack_type: :spread},
    {emoji: Icons::ZAKO_TANK,  hp: 3, vy: 1.0, score: 80, garbage: 2, weave: false, attack_type: :radial},
    {emoji: Icons::ZAKO_AGILE, hp: 1, vy: 2.4, score: 50, garbage: 1, weave: true,  attack_type: :aimed}
  ].freeze
end

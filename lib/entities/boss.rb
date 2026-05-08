# frozen_string_literal: true

require 'async'
require_relative '../config'
require_relative '../assets'

# ボス（イカ大王）。HPに応じて phase 1/2/3 で弾幕パターンを変える。
# 弾幕は Fiber コルーチンで「直線的な手順」として記述する。
# 移動と被弾フラッシュは描画と同期したいので tick で1フレーム単位に更新。
class Boss
  attr_reader :x, :y, :vx, :hp, :max_hp, :flash

  FRAME_DT = 1.0 / Config::FPS

  def initialize(diff:)
    @diff   = diff
    @x      = Config::FIELD_W / 2.0 - Config::BOSS_W / 2.0
    @y      = 24.0
    @vx     = diff[:boss_vx]
    @hp     = diff[:boss_hp]
    @max_hp = diff[:boss_hp]
    @flash  = 0
  end

  def alive? = @hp > 0
  def dead?  = @hp <= 0

  def damage(d)
    @hp -= d
    @flash = 3
  end

  def cx = @x + Config::BOSS_W / 2.0
  def cy = @y + Config::BOSS_H / 2.0

  def hp_ratio
    (@hp.to_f / @max_hp).clamp(0.0, 1.0)
  end

  def phase
    if    hp_ratio > 0.66 then 1
    elsif hp_ratio > 0.33 then 2
    else                       3
    end
  end

  def tick
    @x += @vx
    if @x < 0
      @x = 0.0
      @vx = @vx.abs
    elsif @x > Config::FIELD_W - Config::BOSS_W
      @x = (Config::FIELD_W - Config::BOSS_W).to_f
      @vx = -@vx.abs
    end
    @flash -= 1 if @flash > 0
  end

  # 弾幕パターン Fiber を起動する。
  #   barrier : 接続スコープの Async::Barrier（close/再戦時に一括停止される）
  #   target  : -> { [px, py] } 自機座標を返す lambda（aimed パターン用）
  #   sink    : ->(bullet_hash) 生成弾を渡すと Player の @bullet_inbox に積まれる
  def start_pattern!(barrier:, target:, sink:)
    barrier.async { |task| run_main_pattern(task, target, sink) }
    barrier.async { |task| run_bento_pattern(task, sink) }
    barrier.async { |task| run_starburst_pattern(task, sink) }
  end

  private

  # 4 拍子の弾幕：イカ墨拡散 → ラーメン乱打(phase>=2) → 寿司狙い → ラッキー放射(phase>=2)
  def run_main_pattern(task, target, sink)
    n    = @diff[:interval]
    q_dt = (n / 4) * FRAME_DT

    while alive?
      fire_squid_spread(sink)
      task.sleep(q_dt); break unless alive?

      fire_ramen_burst(sink) if phase >= 2
      task.sleep(q_dt); break unless alive?

      tx, ty = target.call
      fire_sushi_aim(sink, tx, ty)
      task.sleep(q_dt); break unless alive?

      fire_burger_radial(sink) if phase >= 2
      task.sleep(q_dt)
    end
  end

  # 弁当弾は phase 3 のみ独立サイクルで発射。main pattern と非同期に重なる。
  def run_bento_pattern(task, sink)
    interval = @diff[:bento_interval] * FRAME_DT
    while alive?
      task.sleep(interval)
      next unless alive? && phase >= 3
      fire_bento(sink)
    end
  end

  def fire_squid_spread(sink)
    bx = cx - Config::B_SIZE / 2.0
    by = cy
    count  = @diff[:squid]
    spread = Config::FIELD_W * 0.66
    count.times do |i|
      ox = -spread / 2.0 + spread * i / (count - 1)
      sink.call(bullet(bx + ox, by, 0.0, @diff[:squid_vy]))
    end
  end

  def fire_ramen_burst(sink)
    bx = cx - Config::B_SIZE / 2.0
    by = cy
    @diff[:ramen].times do
      ox = (rand - 0.5) * 220
      sink.call(bullet(bx + ox, by, 0.0, @diff[:ramen_vy],
                       sine: true, phase: rand * Math::PI * 2))
    end
  end

  def fire_sushi_aim(sink, tx, ty)
    bx = cx - Config::B_SIZE / 2.0
    by = cy
    sp = @diff[:sushi_sp]
    @diff[:sushi].times do |i|
      spread_a = (i - @diff[:sushi] / 2.0) * 0.062  # 30% homing 強化（旧 0.088）
      angle = Math.atan2(ty - by, tx - bx) + spread_a
      sink.call(bullet(bx, by, Math.cos(angle) * sp, Math.sin(angle).abs * sp + 1.0))
    end
  end

  def fire_burger_radial(sink)
    bx = cx - Config::B_SIZE / 2.0
    by = cy
    arms = @diff[:burger_arms]
    arms.times do |i|
      a = i * Math::PI * 2 / arms
      sink.call(bullet(bx, by, Math.cos(a) * 2.5, Math.sin(a) * 2.5 + 1.0))
    end
    return unless @diff[:burger_extra] || phase >= 3

    arms.times do |i|
      a = i * Math::PI * 2 / arms + Math::PI / arms
      sink.call(bullet(bx, by, Math.cos(a) * 3.0, Math.sin(a) * 3.0 + 1.0))
    end
  end

  def fire_bento(sink)
    sx = rand(2) == 0 ? 0.0 : (Config::FIELD_W - Config::B_SIZE).to_f
    vx = sx == 0 ? @diff[:bento_vx] : -@diff[:bento_vx]
    sink.call(bullet(sx, rand(Config::FIELD_H / 2).to_f, vx, 2.0, bounce: true))
  end

  # ── 星形バースト ──
  # phase >= 2 で 7 秒ごと：星形フォーメーション → 0.6 秒静止 → 散開 → 0.8 秒後ホーミング。
  # 弾の hash を Fiber が保持し続け、フェーズ移行のたびに直接書き換える（Fiber ならではの書き方）。
  STARBURST_CYCLE       = 7.0
  STARBURST_HOLD        = 0.6
  STARBURST_BURST       = 0.8
  STARBURST_R_OUTER     = 90.0
  STARBURST_R_INNER     = 40.0
  STARBURST_BURST_SPEED = 3.5
  STARBURST_TURN_RATE   = 0.045  # rad/frame（30fps で約 2.6°/frame ≒ 1 周 4.7秒）

  def run_starburst_pattern(task, sink)
    while alive?
      task.sleep(STARBURST_CYCLE)
      next unless alive? && phase >= 2

      bullets = spawn_star_formation(sink)

      task.sleep(STARBURST_HOLD)
      break unless alive?

      bullets.each do |b, ang|
        b[:vx] = Math.cos(ang) * STARBURST_BURST_SPEED
        b[:vy] = Math.sin(ang) * STARBURST_BURST_SPEED
      end

      task.sleep(STARBURST_BURST)
      break unless alive?

      bullets.each { |b, _| b[:homing] = {turn_rate: STARBURST_TURN_RATE} }
    end
  end

  # 5 角星の 10 頂点（外角5・内角5を交互）に静止弾を配置。`[bullet, 散開角]` の組を返す。
  def spawn_star_formation(sink)
    cx0 = cx
    cy0 = cy + 60.0
    pairs = []
    10.times do |i|
      ang = -Math::PI / 2 + i * Math::PI * 2 / 10
      r   = i.even? ? STARBURST_R_OUTER : STARBURST_R_INNER
      bx  = cx0 + Math.cos(ang) * r - Config::B_SIZE / 2.0
      by  = cy0 + Math.sin(ang) * r - Config::B_SIZE / 2.0
      b   = bullet(bx, by, 0.0, 0.0, sprite: :bullet_star)
      sink.call(b)
      pairs << [b, ang]
    end
    pairs
  end

  def bullet(x, y, vx, vy, sine: false, phase: 0.0, bounce: false, sprite: :bullet_normal)
    {
      type: Assets::Icons::BULLET_NORMAL,
      sprite: sprite,
      x: x, y: y, vx: vx, vy: vy,
      sine: sine, phase: phase, bounce: bounce
    }
  end
end

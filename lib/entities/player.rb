# frozen_string_literal: true

require 'async'
require_relative '../config'
require_relative '../assets'
require_relative 'zako'
require_relative 'bullet'
require_relative 'food'
require_relative 'boss'
require_relative '../game/garbage_queue'

# 1プレイヤー＝1つの弾幕フィールドを所有する。
# 入力受付・自機・自弾・敵弾・雑魚・ボス・お邪魔受信キュー、すべてを保持。
#
# ── 並行モデル：produce / consume 分離 ──
#   Fiber が直接 @bullets / @foods を変更しない。代わりに inbox に push する。
#   tick の先頭で drain_inboxes が一括コピーする。
#
#   理由：tick は同期的に @bullets を iterate / reject! する。Fiber が同期実行中の
#   tick に干渉しないという協調スケジューリングの暗黙仕様に依存する設計は脆い。
#   inbox を経由することで「@bullets / @foods を変更するのは tick だけ」という
#   不変式が機械的に成立する。
#
# ── Fiber 配線 ──
#   - boss スポーン時に boss が main + bento パターン Fiber を barrier 配下で起動
#   - garbage_queue は 1警告=1 Fiber を barrier 配下で起動
#   - 食べ物スポーンと、食べ物取得時のパワーアップ寿命タイマーは Player 自身の Fiber
class Player
  COMBO_WINDOW     = 60   # 連続撃破とみなすframe猶予
  FRAME_DT         = 1.0 / Config::FPS
  POWERUP_DURATION = 3.0  # 食べ物取得後 3秒間 3-WAY

  attr_reader :controls, :rng, :diff, :name, :color, :powered
  attr_accessor :px, :py, :dx, :dy, :focus,
                :shots, :bullets, :foods, :zakos, :boss,
                :score, :lives, :frame,
                :combo, :last_kill_frame,
                :pending_attacks, :total_sent, :garbage_queue,
                :alive_state

  def initialize(name:, color:, controls:, diff:, seed:)
    @name     = name
    @color    = color
    @controls = controls
    @diff     = diff
    @rng      = Random.new(seed)

    @px = Config::FIELD_W / 2.0
    @py = Config::FIELD_H - 60.0
    @dx = 0
    @dy = 0
    @focus = false

    @shots   = []
    @bullets = []
    @foods   = []
    @zakos   = []
    @boss    = nil

    # produce/consume 用 inbox：Fiber 側はここに push、tick 先頭で drain される
    @bullet_inbox = []
    @food_inbox   = []

    @score      = 0
    @lives      = 3
    @frame      = 0
    @powered    = false
    @power_task = nil

    @combo           = 0
    @last_kill_frame = -1000
    @pending_attacks = []  # 1tick内に発生した攻撃の型シンボル配列（Battle が相手へ送る）
    @total_sent      = 0   # 累計送出数（ゲージ用）

    @garbage_queue = GarbageQueue.new
    @alive_state   = true

    @barrier = nil
  end

  def alive? = @alive_state

  # 接続スコープを受け取り、配下 Fiber を起動。
  # GarbageQueue / 食べ物スポーナーがここで活性化する。
  # sink は **inbox に向ける**（直接 @bullets を触らない）
  def attach_barrier!(barrier)
    @barrier = barrier
    @garbage_queue.attach!(
      barrier: barrier,
      target:  -> { [@px, @py] },
      sink:    ->(bullets) { @bullet_inbox.concat(bullets) }
    )
    barrier.async { |task| food_spawner_loop(task) }
  end

  # ── 入力 ─────────────────────────────────────
  def handle_event(event)
    return unless alive?
    case event[:type]
    when 'keydown'
      key = event[:key]
      loc = event[:loc] || 0
      case
      when @controls[:left].include?(key)  then @dx = -Config::P_SPEED
      when @controls[:right].include?(key) then @dx =  Config::P_SPEED
      when @controls[:up].include?(key)    then @dy = -Config::P_SPEED
      when @controls[:down].include?(key)  then @dy =  Config::P_SPEED
      end
      @focus = true if shift_match?(key, loc)
    when 'keyup'
      key = event[:key]
      loc = event[:loc] || 0
      case
      when @controls[:left].include?(key), @controls[:right].include?(key) then @dx = 0
      when @controls[:up].include?(key),   @controls[:down].include?(key)  then @dy = 0
      end
      @focus = false if shift_match?(key, loc)
    end
  end

  def shift_match?(key, loc)
    return false unless key == 'Shift'
    case @controls[:focus]
    when 'ShiftLeft'  then loc == 1
    when 'ShiftRight' then loc == 2
    end
  end

  # ── 1tick ──────────────────────────────────
  # 同期処理（移動・衝突・スコア）のみ。弾の生成・警告寿命・パワー寿命は Fiber 側。
  # 先頭で inbox を drain することで、Fiber が前 tick 〜今 tick の間に produce した
  # 弾・食べ物をまとめて取り込む。@bullets / @foods は以降このメソッド内でのみ変更される。
  def tick(opponent_alive: true)
    return unless alive?
    @frame += 1
    @score += 1

    drain_inboxes

    move
    spawn_shots
    update_shots

    @zakos.each { |z| Zako.update(z) }
    apply_bullet_homing
    @bullets.each { |b| Bullet.update(b) }
    @foods.each   { |f| Food.update(f) }
    @zakos.reject!   { |z| Zako.out?(z) }
    @bullets.reject! { |b| Bullet.out?(b) }
    @foods.reject!   { |f| Food.out?(f) }

    @boss&.tick

    # コンボ寿命
    if @frame - @last_kill_frame > COMBO_WINDOW
      @combo = 0
    end

    resolve_shot_collisions
    resolve_self_hit
    resolve_food_pickups
  end

  # ── 攻撃の精算（Battle が呼ぶ）─────────────
  def consume_pending_attacks
    a = @pending_attacks
    @pending_attacks = []
    @total_sent += a.size
    a
  end

  # 雑魚スポーン（Battle 側が同期スポーンしてくる）
  def spawn_zako(type, x:, phase: 0.0)
    @zakos << Zako.spawn(type, x: x, phase: phase)
  end

  # ボス生成 → 同時に弾幕パターン Fiber を起動。
  # sink は inbox に向ける（直接 @bullets には触らない）。
  def spawn_boss!
    @boss = Boss.new(diff: @diff)
    @boss.start_pattern!(
      barrier: @barrier,
      target:  -> { [@px, @py] },
      sink:    ->(b) { @bullet_inbox << b }
    )
  end

  def in_boss_phase? = !@boss.nil?

  # ── 内部処理 ─────────────────────────────────

  # Fiber が積んだ弾・食べ物をフィールドに取り込む（tick の唯一の書き込み口）。
  def drain_inboxes
    unless @bullet_inbox.empty?
      @bullets.concat(@bullet_inbox)
      @bullet_inbox.clear
    end
    unless @food_inbox.empty?
      @foods.concat(@food_inbox)
      @food_inbox.clear
    end
  end

  # `:homing => {turn_rate:}` を持つ弾を東方風にぬるぬる追尾させる。
  # 加速ではなく**速度ベクトルの回転**：速さを保ったまま方向だけを毎 frame 最大
  # turn_rate ラジアンだけ自機方向に向ける（角速度クランプ）。
  # → 「ガクッと曲がる」のではなく弧を描いて滑らかに収束する。
  def apply_bullet_homing
    pcx = @px + Config::P_SIZE / 2.0
    pcy = @py + Config::P_SIZE / 2.0
    @bullets.each do |b|
      h = b[:homing]
      next unless h
      speed = Math.hypot(b[:vx], b[:vy])
      next if speed < 0.01

      cur_a = Math.atan2(b[:vy], b[:vx])
      tgt_a = Math.atan2(pcy - (b[:y] + Config::B_SIZE / 2.0),
                         pcx - (b[:x] + Config::B_SIZE / 2.0))

      # 最短角差分を [-π, π] に正規化してから turn_rate でクランプ
      delta = tgt_a - cur_a
      delta -= 2 * Math::PI while delta >  Math::PI
      delta += 2 * Math::PI while delta < -Math::PI
      turn = delta.clamp(-h[:turn_rate], h[:turn_rate])

      new_a = cur_a + turn
      b[:vx] = Math.cos(new_a) * speed
      b[:vy] = Math.sin(new_a) * speed
    end
  end

  def move
    speed = @focus ? Config::P_SPEED * 0.4 : Config::P_SPEED
    mx = @dx == 0 ? 0 : (@dx <=> 0) * speed
    my = @dy == 0 ? 0 : (@dy <=> 0) * speed
    @px = (@px + mx).clamp(0, Config::FIELD_W - Config::P_SIZE)
    @py = (@py + my).clamp(0, Config::FIELD_H - Config::P_SIZE)
  end

  def spawn_shots
    return unless @frame % 4 == 0
    cx = @px + Config::P_SIZE / 2.0 - Config::SHOT_SIZE / 2.0
    cy = @py - Config::SHOT_SIZE
    if @powered
      [-0.25, 0.0, 0.25].each do |a|
        @shots << {x: cx, y: cy, vx: Math.sin(a) * 10.0, vy: -Math.cos(a) * 10.0}
      end
    else
      @shots << {x: cx, y: cy, vx: 0.0, vy: -10.0}
    end
  end

  def update_shots
    @shots.each { |s| s[:x] += s[:vx]; s[:y] += s[:vy] }
    @shots.reject! { |s| s[:y] < -Config::SHOT_SIZE || s[:x] < -Config::SHOT_SIZE || s[:x] > Config::FIELD_W }
  end

  def resolve_shot_collisions
    @shots.reject! do |s|
      hit_zako = @zakos.find { |z| shot_hits?(s, z[:x], z[:y], Config::ZAKO_SIZE, Config::ZAKO_SIZE) }
      if hit_zako
        hit_zako[:hp] -= 1
        hit_zako[:flash] = 3
        if hit_zako[:hp] <= 0
          register_zako_kill!(hit_zako)
          @zakos.delete(hit_zako)
        end
        next true
      end

      if @boss && shot_hits?(s, @boss.x, @boss.y, Config::BOSS_W, Config::BOSS_H)
        @boss.damage(5)
        next true
      end

      false
    end
  end

  def shot_hits?(s, x, y, w, h)
    s[:x] < x + w && s[:x] + Config::SHOT_SIZE > x &&
      s[:y] < y + h && s[:y] + Config::SHOT_SIZE > y
  end

  # 雑魚撃破 → カタログの attack_type を pending_attacks に積む。コンボで攻撃数+wave追加。
  def register_zako_kill!(z)
    @combo = (@frame - @last_kill_frame < COMBO_WINDOW) ? @combo + 1 : 1
    @last_kill_frame = @frame
    @score += z[:score]

    base = z[:attack_type] || :spread
    count = z[:garbage]                # 通常 1, 硬い敵 2
    count += 1 if @combo >= 2
    count.times { @pending_attacks << base }
    @pending_attacks << :wave if @combo >= 3   # 連続コンボでサイン波ボーナス
  end

  def resolve_self_hit
    hit = @bullets.find { |b| rect_collide?(b[:x], b[:y], Config::B_SIZE, Config::B_SIZE) }
    return unless hit
    @bullets.delete(hit)
    @lives -= 1
    @combo = 0
    if @lives <= 0
      @alive_state = false
    end
  end

  def resolve_food_pickups
    @foods.reject! do |f|
      if rect_collide?(f[:x], f[:y], Config::FOOD_SIZE, Config::FOOD_SIZE)
        @score += @diff[:score_food]
        trigger_powerup!
        true
      else
        false
      end
    end
  end

  def rect_collide?(x, y, w, h)
    m = 8
    @px + m < x + w - m &&
      @px + Config::P_SIZE - m > x + m &&
      @py + m < y + h - m &&
      @py + Config::P_SIZE - m > y + m
  end

  # ── パワーアップ寿命 Fiber ─────────────────
  # 連続取得時は前 Fiber を停止して 3 秒からやり直す（タイマー再延長）。
  def trigger_powerup!
    @powered = true
    @power_task&.stop
    return unless @barrier
    @power_task = @barrier.async do |task|
      task.sleep(POWERUP_DURATION)
      @powered = false
    end
  end

  # ── 食べ物スポーナー Fiber ─────────────────
  # @foods に直接 push せず、inbox 経由で tick に取り込ませる
  def food_spawner_loop(task)
    interval = @diff[:food_interval] * FRAME_DT
    loop do
      task.sleep(interval)
      break unless alive?
      @food_inbox << Food.spawn(rng: @rng)
    end
  end
end

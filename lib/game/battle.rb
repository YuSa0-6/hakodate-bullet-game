# frozen_string_literal: true

require_relative '../config'
require_relative '../assets'
require_relative '../entities/player'

# 2人プレイヤーの調停。
# - フェーズ遷移（wave → boss）
# - 雑魚の同一スポーン（公平性）
# - 攻撃の精算（コンボ送出）
# - 勝敗判定
#
# Fiber 配線：barrier を Player に渡して、各 Player の食べ物スポーナー・
# ボスパターン・お邪魔警告タイマーを barrier 配下で起動させる。
class Battle
  PHASES = %i[wave boss].freeze

  attr_reader :p1, :p2, :phase, :winner, :frame, :difficulty

  def initialize(difficulty:, barrier:)
    @difficulty = difficulty
    @diff       = Config::DIFF[difficulty]
    seed        = Random.new_seed
    @rng        = Random.new(seed)
    @barrier    = barrier

    @p1 = Player.new(
      name: 'P1', color: '#7cf',
      controls: Config::P1_CONTROLS, diff: @diff, seed: seed
    )
    @p2 = Player.new(
      name: 'P2', color: '#f7c',
      controls: Config::P2_CONTROLS, diff: @diff, seed: seed + 1
    )

    @p1.attach_barrier!(@barrier)
    @p2.attach_barrier!(@barrier)

    @frame  = 0
    @phase  = :wave
    @winner = nil
  end

  def over? = !@winner.nil?

  # 同期処理だけを担う：フェーズ遷移・雑魚同期スポーン・両プレイヤー tick・攻撃精算・勝敗判定。
  # 弾の生成（ボス・お邪魔・食べ物）は Fiber が独立に進めるので、ここからは消えている。
  def tick
    return if over?
    @frame += 1

    transition_phase
    spawn_zakos if @phase == :wave
    spawn_boss! if @phase == :boss && !@p1.in_boss_phase?

    @p1.tick(opponent_alive: @p2.alive?)
    @p2.tick(opponent_alive: @p1.alive?)

    settle_attacks!
    judge!
  end

  # キーイベントを両プレイヤーに分配（input_queue から呼ばれる）
  def dispatch_input(event)
    @p1.handle_event(event)
    @p2.handle_event(event)
  end

  private

  def transition_phase
    @phase = :boss if @frame >= Config::WAVE_FRAMES
  end

  def spawn_zakos
    return unless @frame % @diff[:zako_interval] == 0
    type  = Assets::ZAKO_TYPES.sample(random: @rng)
    x     = @rng.rand(Config::FIELD_W - Config::ZAKO_SIZE)
    phase = @rng.rand * Math::PI * 2
    @p1.spawn_zako(type, x: x, phase: phase)
    @p2.spawn_zako(type, x: x, phase: phase)
  end

  def spawn_boss!
    @p1.spawn_boss!
    @p2.spawn_boss!
  end

  # 一方向送出（獣王園スタイル）：相殺なし、自分の攻撃は必ず相手へ届く
  def settle_attacks!
    a1 = @p1.consume_pending_attacks
    a2 = @p2.consume_pending_attacks
    @p2.garbage_queue.enqueue(a1, rng: @rng)
    @p1.garbage_queue.enqueue(a2, rng: @rng)
  end

  def judge!
    if !@p1.alive? && !@p2.alive?
      @winner = :draw
    elsif !@p1.alive?
      @winner = :p2
    elsif !@p2.alive?
      @winner = :p1
    elsif @phase == :boss
      d1 = @p1.boss&.dead?
      d2 = @p2.boss&.dead?
      if d1 && d2
        @winner = :draw
      elsif d1
        @winner = :p1
      elsif d2
        @winner = :p2
      end
    end
  end
end

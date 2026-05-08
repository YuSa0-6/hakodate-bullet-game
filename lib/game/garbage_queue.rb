# frozen_string_literal: true

require 'async'
require_relative '../config'
require_relative '../entities/bullet'

# 受信お邪魔キュー（東方獣王園スタイル：相殺なし・一方向送出）。
# 攻撃は型情報を持つ：
#   :spread (基本)  / :radial (硬い)  / :aimed (素早い)  / :wave (コンボ)
#
# 1警告 = 1 Fiber。各警告 Fiber が独立にカウントダウンを進め、
# 期限到来でパターン化された弾を発射する。自前のスケジューラを書かず、
# Async リアクタにスケジューリングを委ねる。
class GarbageQueue
  attr_reader :warnings

  FRAME_DT = 1.0 / Config::FPS

  def initialize
    @warnings = []   # [{type:, x:, frames_left:}, ...] 描画用
    @barrier  = nil
    @target   = nil
    @sink     = nil
  end

  # Player から接続スコープと宛先を渡される。
  #   barrier : 接続スコープの Async::Barrier
  #   target  : -> { [px, py] } 受け手プレイヤーの自機座標
  #   sink    : ->(bullets_array) Player の @bullet_inbox に concat される
  def attach!(barrier:, target:, sink:)
    @barrier = barrier
    @target  = target
    @sink    = sink
  end

  # 攻撃配列（型シンボルの列）を受信。1要素ごとに警告 Fiber を起動する。
  def enqueue(attacks, rng:)
    return if attacks.nil? || attacks.empty? || @barrier.nil?
    attacks.each do |type|
      x = rng.rand(Config::FIELD_W - Config::B_SIZE).to_f
      warning = {type: type, x: x, frames_left: Config::GARBAGE_WARN_FRAMES}
      @warnings << warning
      spawn_warning_fiber(warning)
    end
  end

  def size = @warnings.size

  private

  # 警告寿命を1 Fiber に閉じ込める：
  #   - 1フレームごとに frames_left を減算（描画フェードアウト用）
  #   - 期限到来で警告を消去 → パターン化された弾を sink に流す
  def spawn_warning_fiber(warning)
    @barrier.async do |task|
      Config::GARBAGE_WARN_FRAMES.times do
        task.sleep(FRAME_DT)
        warning[:frames_left] -= 1
      end
      @warnings.delete(warning)
      tx, ty = @target.call
      @sink.call(Bullet.attack_pattern(warning[:type], warning[:x],
                                       target_x: tx, target_y: ty))
    end
  end
end

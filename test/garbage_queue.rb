# frozen_string_literal: true

require 'async'
require 'async/barrier'

require_relative '../lib/game/garbage_queue'
require_relative 'helper'

# お邪魔（受信）キューの仕様。
#
# 一方向送出モデル（獣王園スタイル）:
#   相手から送られてきた攻撃（型シンボルの配列）を「警告 ⚠️」として一定 frame 保持し、
#   時間が経つと型ごとの弾幕パターンに展開されて落ちてくる。相殺はない。
#
# 実装は 1警告=1 Fiber でカウントダウンする方式に変わったので、
#   - 同期側（enqueue 直後の状態）は TestBarrier で観察
#   - Fiber ライフサイクル（時間経過で弾を発射）は実 Async::Barrier + barrier.wait で観察
# の 2 層に分けてテストする。
describe GarbageQueue do
  let(:rng)   { Random.new(42) }
  let(:queue) { GarbageQueue.new }

  with '#enqueue（受信・同期側）' do
    let(:barrier) { TestBarrier.new }

    def attach!(target_x: 100.0, target_y: 100.0, sink: ->(_) {})
      queue.attach!(barrier: barrier, target: -> { [target_x, target_y] }, sink: sink)
    end

    it 'attach! 前の enqueue は no-op（barrier 未接続なら何もしない）' do
      queue.enqueue([:spread, :radial], rng: rng)
      expect(queue.size).to be == 0
    end

    it '攻撃配列の要素ごとに 1 警告ずつ積む' do
      attach!
      queue.enqueue([:spread, :radial, :aimed], rng: rng)
      expect(queue.size).to be == 3
    end

    it '型シンボルは警告にそのまま保持される（後で弾幕パターンの選択に使う）' do
      attach!
      queue.enqueue([:radial, :wave], rng: rng)
      expect(queue.warnings.map { |w| w[:type] }).to be == [:radial, :wave]
    end

    it 'nil や空配列は無視する（送信タイミングに 0 攻撃が来ても安全）' do
      attach!
      queue.enqueue(nil, rng: rng)
      queue.enqueue([], rng: rng)
      expect(queue.size).to be == 0
    end

    it '警告は FIELD 内の x 座標と既定の残 frame で生成される' do
      attach!
      queue.enqueue([:spread] * 5, rng: rng)
      queue.warnings.each do |w|
        expect(w[:x]).to be >= 0
        expect(w[:x]).to be <= Config::FIELD_W - Config::B_SIZE
        expect(w[:frames_left]).to be == Config::GARBAGE_WARN_FRAMES
      end
    end

    it '警告 Fiber が（少なくとも）警告数だけ起動を要求される' do
      attach!
      queue.enqueue([:spread, :radial, :aimed], rng: rng)
      # TestBarrier はスケジュールされた block を保持する。実際は走らない。
      expect(barrier.scheduled.size).to be == 3
    end
  end

  with '#tick 相当の Fiber ライフサイクル（結合）' do
    # 本物の Async::Barrier を使い、warning Fiber を最後まで走らせて
    # 「警告が消える / sink が呼ばれる / 弾の数と型が正しい」を観察する。
    # Config::GARBAGE_WARN_FRAMES * (1/30秒) ぶんの実時間が必要なので
    # 1ケースで十分（複数走らせると遅い）。

    it ':spread 警告は時間経過後に 3-way 弾になり警告キューから消える' do
      fired = []
      Sync do
        barrier = Async::Barrier.new
        queue.attach!(
          barrier: barrier,
          target:  -> { [100.0, 100.0] },
          sink:    ->(bullets) { fired.concat(bullets) }
        )
        queue.enqueue([:spread], rng: rng)
        # 全ての警告 Fiber が完走するまで待つ
        barrier.wait
      end

      expect(queue.size).to be == 0
      expect(fired.size).to be == 3
      expect(fired).to be(:all?) { |b| b[:garbage] == true }
    end

    it ':aimed 警告は受け手の自機座標方向に飛ぶ弾になる' do
      fired = []
      Sync do
        barrier = Async::Barrier.new
        queue.attach!(
          barrier: barrier,
          target:  -> { [10.0, 400.0] },
          sink:    ->(bullets) { fired.concat(bullets) }
        )
        queue.enqueue([:aimed], rng: Random.new(0))
        barrier.wait
      end

      expect(fired.size).to be == 3
      # 中央弾（off=0）は vy が必ず正（abs を取った後 +1.2 されるため）
      expect(fired[1][:vy]).to be > 0
    end
  end
end

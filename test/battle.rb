# frozen_string_literal: true

require_relative '../lib/game/battle'
require_relative 'helper'

# Battle の仕様（2人プレイヤーの調停）。
#
# - フェーズ遷移: WAVE_FRAMES 経過で wave → boss
# - 雑魚スポーン: 同じ Random で両者に同じ位置・同じ種別の雑魚を出す（公平性）
# - 攻撃精算: 一方向送出（自分の攻撃は必ず相手のキューへ。相殺はない）
# - 勝敗判定: 残機・ボス HP の組み合わせから決定
#
# barrier には Fiber を起動しない TestBarrier を渡す。Battle の同期処理だけを
# 検証するため、food spawner / 警告 Fiber / boss 弾幕 Fiber は走らせない。
describe Battle do
  let(:barrier) { TestBarrier.new }
  let(:battle)  { Battle.new(difficulty: :easy, barrier: barrier) }

  with '初期状態' do
    it ':wave フェーズで開始される' do
      expect(battle.phase).to be == :wave
    end

    it '勝者は未確定（over? は false）' do
      expect(battle.winner).to be_nil
      expect(battle.over?).to be == false
    end

    it 'P1 / P2 の生存と残機 3 が初期値' do
      expect(battle.p1).to be(:alive?)
      expect(battle.p2).to be(:alive?)
      expect(battle.p1.lives).to be == 3
      expect(battle.p2.lives).to be == 3
    end
  end

  with 'フェーズ遷移' do
    it 'WAVE_FRAMES に到達したら次 tick で :boss に移る' do
      Config::WAVE_FRAMES.times { battle.tick }

      expect(battle.phase).to be == :boss
    end
  end

  with '#settle_attacks!（一方向送出 / 獣王園スタイル）' do
    # P1/P2 に直接 pending_attacks を仕込んでから tick で精算させる
    # （tick は frame を進めて雑魚 update もするが、精算ロジックの観察はそれで十分）
    it 'P1 の攻撃は P2 のキューに、P2 の攻撃は P1 のキューに enqueue される' do
      battle.p1.pending_attacks.replace([:spread, :spread])
      battle.p2.pending_attacks.replace([:radial])

      battle.tick

      expect(battle.p2.garbage_queue.size).to be == 2
      expect(battle.p1.garbage_queue.size).to be == 1
    end

    it '相殺は発生しない（自分の攻撃が自分の警告を消すことはない）' do
      battle.p1.pending_attacks.replace([:spread] * 5)
      battle.p1.garbage_queue.enqueue([:spread] * 3, rng: Random.new(0))

      before = battle.p1.garbage_queue.size
      battle.tick

      # P1 自身のキューは P1 の攻撃の影響を受けず、tick 進行ぶんしか変動しない
      expect(battle.p1.garbage_queue.size).to be == before
    end

    it '消費後の pending_attacks は空（次 tick で二重送信しない）' do
      battle.p1.pending_attacks.replace([:spread, :spread])

      battle.tick

      expect(battle.p1.pending_attacks).to be(:empty?)
    end

    it '送出した数は total_sent に累積される（ゲージ表示用）' do
      battle.p1.pending_attacks.replace([:spread, :radial, :wave])

      battle.tick

      expect(battle.p1.total_sent).to be == 3
    end
  end

  with '#judge!（勝敗判定）' do
    # alive_state を直接落として勝敗ロジックだけ検証する
    it '両者死亡なら :draw' do
      battle.p1.alive_state = false
      battle.p2.alive_state = false

      battle.tick

      expect(battle.winner).to be == :draw
      expect(battle.over?).to be == true
    end

    it 'P1 のみ死亡なら :p2 の勝ち' do
      battle.p1.alive_state = false

      battle.tick

      expect(battle.winner).to be == :p2
    end

    it 'P2 のみ死亡なら :p1 の勝ち' do
      battle.p2.alive_state = false

      battle.tick

      expect(battle.winner).to be == :p1
    end

    it '両者生存中は勝者未確定（wave 中は判定されない）' do
      3.times { battle.tick }

      expect(battle.winner).to be_nil
    end

    # boss フェーズ判定：HP を直接削って dead? を制御する。
    # tick 経由で boss を立てると弾幕 Fiber が走るため、Boss を直接代入する。
    with 'boss フェーズの撃破判定' do
      def enter_boss_phase!
        battle.instance_variable_set(:@phase, :boss)
        battle.p1.boss = Boss.new(diff: Config::DIFF[:easy])
        battle.p2.boss = Boss.new(diff: Config::DIFF[:easy])
      end

      # 各プレイヤーは自分のフィールド側のボスを倒す（独立したボス）。
      # よって「P1 側の boss が dead? = P1 が自分のボスを倒した = P1 勝利」が正しい。
      it 'P1 が自分側のボスを先に倒したら :p1 の勝ち' do
        enter_boss_phase!
        battle.p1.boss.damage(battle.p1.boss.max_hp)

        battle.tick
        expect(battle.winner).to be == :p1
      end

      it 'P2 が自分側のボスを先に倒したら :p2 の勝ち' do
        enter_boss_phase!
        battle.p2.boss.damage(battle.p2.boss.max_hp)

        battle.tick
        expect(battle.winner).to be == :p2
      end

      it '両ボス同時撃破は :draw' do
        enter_boss_phase!
        battle.p1.boss.damage(battle.p1.boss.max_hp)
        battle.p2.boss.damage(battle.p2.boss.max_hp)

        battle.tick
        expect(battle.winner).to be == :draw
      end

      it '両ボス生存中は wave 終了後でも勝者未確定' do
        enter_boss_phase!
        battle.tick
        expect(battle.winner).to be_nil
      end
    end
  end

  with '雑魚スポーンの公平性' do
    it 'P1 と P2 の雑魚は同 frame で同じ位置・同じ種別になる' do
      # zako_interval (easy=50) フレーム経過した時点で 1 体スポーン
      Config::DIFF[:easy][:zako_interval].times { battle.tick }

      z1 = battle.p1.zakos.first
      z2 = battle.p2.zakos.first

      expect(z1).not.to be_nil
      expect(z2).not.to be_nil
      expect(z1[:emoji]).to be == z2[:emoji]
      expect(z1[:x]).to be == z2[:x]
    end
  end

  with 'spawn_boss! の二重呼出ガード' do
    it 'boss フェーズ中は in_boss_phase? ガードでボスは一度しか作られない' do
      battle.instance_variable_set(:@phase, :boss)

      battle.tick
      first_boss = battle.p1.boss
      expect(first_boss).not.to be_nil

      # 続けて tick しても @boss は同じインスタンスのまま（弾幕 Fiber が二重起動しない）
      5.times { battle.tick }
      expect(battle.p1.boss).to be_equal(first_boss)
      expect(battle.p2.boss).not.to be_nil
    end
  end
end

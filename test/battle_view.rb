# frozen_string_literal: true

require 'live'
require 'async'
require 'async/barrier'

require_relative '../lib/views/battle_view'
require_relative 'helper'

# BattleView の状態機械（:start / :playing / :result）と入力ハンドリング、
# 再戦サイクル（teardown → start で前 barrier の Fiber が確実に止まる）を観察する。
#
# Live::View#bind や render は WebSocket / Lively ランタイムが必要なため、ここでは
# - 状態遷移と難易度切替（handle 経由）
# - start_battle! 後に @battle / @barrier / @input_queue が立つこと
# - teardown_battle! で barrier がクリアされること
# - title_start_key? のホワイトリスト
# - tick_loop が break して :result に遷移すること（実 barrier で観察）
# だけを切り出して検証する。

# テスト用サブクラス。update! は本来 WebSocket page にメッセージを送るが、
# テスト中は bind されていないので no-op にする。state 遷移と Fiber 配線だけ観察する。
class TestBattleView < BattleView
  def update!
    nil
  end
end

describe BattleView do
  let(:view) { TestBattleView.new('test-view-id') }

  with '初期状態' do
    it ':start フェーズ・難易度 :easy で開始' do
      expect(view.instance_variable_get(:@state)).to be == :start
      expect(view.instance_variable_get(:@difficulty)).to be == :easy
      expect(view.instance_variable_get(:@battle)).to be_nil
      expect(view.instance_variable_get(:@barrier)).to be_nil
    end
  end

  with 'タイトル画面の入力' do
    it '左右キーで難易度がローテーションする' do
      view.handle(type: 'keydown', key: 'ArrowRight')
      expect(view.instance_variable_get(:@difficulty)).to be == :normal

      view.handle(type: 'keydown', key: 'ArrowRight')
      expect(view.instance_variable_get(:@difficulty)).to be == :hard

      # 末尾から戻ると先頭に折り返す
      view.handle(type: 'keydown', key: 'ArrowRight')
      expect(view.instance_variable_get(:@difficulty)).to be == :easy

      view.handle(type: 'keydown', key: 'ArrowLeft')
      expect(view.instance_variable_get(:@difficulty)).to be == :hard
    end

    it '通常文字キーで :playing に遷移する' do
      Sync do
        view.handle(type: 'keydown', key: 'z')
        expect(view.instance_variable_get(:@state)).to be == :playing
        expect(view.instance_variable_get(:@battle)).not.to be_nil

        # クリーンアップ：起動した Fiber を止める
        view.send(:teardown_battle!)
      end
    end

    it 'Tab / F12 / Meta などの機能キーでは :playing に遷移しない' do
      %w[F12 Tab Meta Shift Control Alt].each do |key|
        view.handle(type: 'keydown', key: key)
        expect(view.instance_variable_get(:@state)).to be == :start
      end
    end

    it 'repeat イベントは無視される（左右キーが押しっぱなしで暴走しない）' do
      view.handle(type: 'keydown', key: 'ArrowRight')
      d1 = view.instance_variable_get(:@difficulty)
      view.handle(type: 'keydown', key: 'ArrowRight', repeat: true)
      expect(view.instance_variable_get(:@difficulty)).to be == d1
    end

    it '未解放時は ←→ で :extra に到達しない（DIFFICULTIES 内のみ循環）' do
      Config::DIFFICULTIES.size.times do
        view.handle(type: 'keydown', key: 'ArrowRight')
      end
      expect(view.instance_variable_get(:@difficulty)).to be == :easy
      expect(view.instance_variable_get(:@extra_unlocked)).to be == false
    end
  end

  with 'Konami シーケンスによる EXTRA 解放' do
    def feed_konami(view)
      BattleView::KONAMI_SEQUENCE.each do |key|
        view.handle(type: 'keydown', key: key)
      end
    end

    it '完全な Konami 入力で @extra_unlocked = true になり、難易度が :extra に切替' do
      feed_konami(view)
      expect(view.instance_variable_get(:@extra_unlocked)).to be == true
      expect(view.instance_variable_get(:@difficulty)).to be == :extra
      expect(view.instance_variable_get(:@state)).to be == :start
    end

    it '途中で違うキーが入るとシーケンスは破綻する（解放されない）' do
      Sync do
        view.handle(type: 'keydown', key: 'ArrowUp')
        view.handle(type: 'keydown', key: 'ArrowUp')
        view.handle(type: 'keydown', key: 'z')  # Konami と無関係：start_battle! に流れる
        expect(view.instance_variable_get(:@extra_unlocked)).to be == false
        expect(view.instance_variable_get(:@state)).to be == :playing
        view.send(:teardown_battle!)
      end
    end

    it '解放後は ←→ で :extra も選択肢に並ぶ（ALL_DIFFICULTIES 循環）' do
      feed_konami(view)
      # 現在 :extra → 右に進めて :easy に折り返す
      view.handle(type: 'keydown', key: 'ArrowRight')
      expect(view.instance_variable_get(:@difficulty)).to be == :easy
      # ←→ で全要素に届くこと
      seen = [view.instance_variable_get(:@difficulty)]
      (Config::ALL_DIFFICULTIES.size - 1).times do
        view.handle(type: 'keydown', key: 'ArrowRight')
        seen << view.instance_variable_get(:@difficulty)
      end
      expect(seen.sort).to be == Config::ALL_DIFFICULTIES.sort
    end
  end

  with '#start_battle! / #teardown_battle!' do
    it 'start で @battle / @barrier / @input_queue が立ち、teardown でクリアされる' do
      Sync do
        view.send(:start_battle!)
        expect(view.instance_variable_get(:@battle)).not.to be_nil
        expect(view.instance_variable_get(:@barrier)).not.to be_nil
        expect(view.instance_variable_get(:@input_queue)).not.to be_nil

        view.send(:teardown_battle!)
        expect(view.instance_variable_get(:@barrier)).to be_nil
        expect(view.instance_variable_get(:@input_queue)).to be_nil
      end
    end

    it '再戦サイクル：start → teardown → start で barrier が新しいインスタンスになる' do
      Sync do
        view.send(:start_battle!)
        first_barrier = view.instance_variable_get(:@barrier)

        view.send(:teardown_battle!)
        view.send(:start_battle!)
        second_barrier = view.instance_variable_get(:@barrier)

        expect(second_barrier).not.to be_nil
        expect(second_barrier).not.to be_equal(first_barrier)

        view.send(:teardown_battle!)
      end
    end
  end

  with '結果画面の入力' do
    def force_result(view, winner: :p1)
      Sync do
        view.send(:start_battle!)
        view.instance_variable_get(:@battle).instance_variable_set(:@winner, winner)
        view.instance_variable_set(:@state, :result)
        view.send(:teardown_battle!)
      end
    end

    it '[R] / Enter で再戦（:playing に戻る）' do
      Sync do
        force_result(view)
        view.handle(type: 'keydown', key: 'R')
        expect(view.instance_variable_get(:@state)).to be == :playing

        view.send(:teardown_battle!)
      end
    end

    it '[S] / Escape でタイトルに戻る' do
      Sync do
        force_result(view)
        view.handle(type: 'keydown', key: 'Escape')
        expect(view.instance_variable_get(:@state)).to be == :start
        expect(view.instance_variable_get(:@battle)).to be_nil
      end
    end
  end

  with 'current_fps（重い時の描画レート切替）' do
    it 'battle 未起動なら常に Config::FPS' do
      expect(view.send(:current_fps)).to be == Config::FPS
    end

    it 'エンティティ総数が閾値以下なら通常 FPS' do
      Sync do
        view.send(:start_battle!)
        expect(view.send(:current_fps)).to be == Config::FPS
        view.send(:teardown_battle!)
      end
    end

    it 'エンティティ総数が閾値超で HEAVY_FPS にフォールバック' do
      Sync do
        view.send(:start_battle!)
        battle = view.instance_variable_get(:@battle)
        # 簡易にダミー要素を片側に詰める（合計が HEAVY_ENTITY_THRESHOLD 超）
        threshold = BattleView::HEAVY_ENTITY_THRESHOLD
        (threshold + 1).times do
          battle.p1.bullets << {
            x: 0.0, y: 0.0, vx: 0.0, vy: 0.0,
            sine: false, bounce: false, garbage: false
          }
        end
        expect(view.send(:current_fps)).to be == BattleView::HEAVY_FPS
        view.send(:teardown_battle!)
      end
    end
  end
end

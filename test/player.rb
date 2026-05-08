# frozen_string_literal: true

require_relative '../lib/entities/player'
require_relative '../lib/assets'

# Player の仕様。
# 入力・移動・コリジョンは描画と Async ループに依存するため、
# ここでは「雑魚撃破→攻撃型キュー (pending_attacks) への積み上げ」のみを検証する。
# これがゲーム性の根幹（撃破バリエーションがそのまま相手への弾幕パターンに化ける）。
describe Player do
  let(:player) do
    Player.new(
      name: 'P1', color: '#7cf',
      controls: Config::P1_CONTROLS, diff: Config::DIFF[:easy],
      seed: 12_345
    )
  end

  # 雑魚カタログから種類別の zako 風 Hash を生成するヘルパ。
  # （Player#register_zako_kill! は Zako.spawn 済みの Hash しか受けない）
  def zako_for(attack_type, garbage: 1, score: 30)
    {emoji: '🐙', score: score, garbage: garbage, attack_type: attack_type}
  end

  with '#register_zako_kill!（雑魚撃破時の攻撃型決定）' do
    it ':spread 型の雑魚は :spread を pending_attacks に積む' do
      player.register_zako_kill!(zako_for(:spread))

      expect(player.pending_attacks).to be == [:spread]
    end

    it ':radial 型の硬い雑魚（garbage:2）は :radial を 2 つ積む' do
      player.register_zako_kill!(zako_for(:radial, garbage: 2))

      expect(player.pending_attacks).to be == [:radial, :radial]
    end

    it ':aimed 型の素早い雑魚は :aimed を積む（受信側は自機狙いに展開される）' do
      player.register_zako_kill!(zako_for(:aimed))

      expect(player.pending_attacks).to be == [:aimed]
    end

    it 'attack_type が無い場合は :spread にフォールバック（後方互換）' do
      player.register_zako_kill!({emoji: '❓', score: 10, garbage: 1})

      expect(player.pending_attacks).to be == [:spread]
    end

    it 'スコアは雑魚定義の score だけ加算される' do
      base = player.score

      player.register_zako_kill!(zako_for(:spread, score: 30))

      expect(player.score - base).to be == 30
    end
  end

  with 'コンボ仕様（連続撃破ボーナス）' do
    let(:zako) { zako_for(:spread) }

    it '初回撃破は combo = 1' do
      player.register_zako_kill!(zako)

      expect(player.combo).to be == 1
    end

    it 'COMBO_WINDOW frame 以内の連続撃破で combo は伸びる' do
      player.register_zako_kill!(zako)
      player.frame += Player::COMBO_WINDOW - 1
      player.register_zako_kill!(zako)

      expect(player.combo).to be == 2
    end

    it 'COMBO_WINDOW を超えると combo は 1 にリセット' do
      player.register_zako_kill!(zako)
      player.frame += Player::COMBO_WINDOW + 1
      player.register_zako_kill!(zako)

      expect(player.combo).to be == 1
    end

    it 'combo >= 2 では送出量が +1 される（量的ボーナス）' do
      player.register_zako_kill!(zako)             # combo=1, [:spread] 1発
      player.frame += 5
      player.register_zako_kill!(zako)             # combo=2 → garbage:1+1 = 2発

      # 1 + 2 = 3
      expect(player.pending_attacks.size).to be == 3
    end

    it 'combo >= 3 では :wave がボーナスとして追加される（質的ボーナス）' do
      player.register_zako_kill!(zako); player.frame += 5  # combo=1
      player.register_zako_kill!(zako); player.frame += 5  # combo=2
      player.register_zako_kill!(zako)                     # combo=3 → :wave 追加

      expect(player.pending_attacks).to be(:include?, :wave)
    end

    # Extra モードは @diff[:wave_combo_threshold] = 1 で初撃から :wave を出す
    it 'EXTRA difficulty では combo=1 でも :wave が追加される（常時サイン波）' do
      extra_player = Player.new(
        name: 'P1', color: '#7cf',
        controls: Config::P1_CONTROLS, diff: Config::DIFF[:extra],
        seed: 12_345
      )
      extra_player.register_zako_kill!(zako)

      expect(extra_player.combo).to be == 1
      expect(extra_player.pending_attacks).to be(:include?, :wave)
    end
  end

  with '#consume_pending_attacks（Battle が毎 tick 取り出す）' do
    it '取り出すと内部キューは空になる（ダブル送出を防ぐ）' do
      player.register_zako_kill!({emoji: '🐙', score: 30, garbage: 1, attack_type: :spread})

      first = player.consume_pending_attacks

      expect(first.size).to be == 1
      expect(player.pending_attacks).to be(:empty?)
    end

    it '取り出した数だけ total_sent が累積する（中央ゲージ表示用）' do
      player.register_zako_kill!({emoji: '🐡', score: 80, garbage: 2, attack_type: :radial})

      player.consume_pending_attacks

      expect(player.total_sent).to be == 2
    end
  end
end

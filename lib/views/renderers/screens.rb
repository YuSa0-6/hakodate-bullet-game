# frozen_string_literal: true

require_relative '../../config'
require_relative '../../assets'

module Renderers
  # タイトル / 勝敗 / ゲームオーバーなどの全画面UIをまとめた渡し場。
  module Screens
    module_function

    DIFF_DESC = {
      easy:   'ゆっくり・少なめ (スコア×1)',
      normal: '速め・多め (スコア×2)',
      hard:   'カオス！ (スコア×3)',
      extra:  '弾幕地獄・常時サイン波・星形連弾 (スコア×5)'
    }.freeze

    def title(builder, difficulty:, extra_unlocked: false)
      d = Config::DIFF[difficulty]
      visible = extra_unlocked ? Config::ALL_DIFFICULTIES : Config::DIFFICULTIES
      builder.tag(:div, style: full_screen_bg) do
        builder.tag(:div, style: 'font-size:36px;font-weight:bold;letter-spacing:2px;margin-bottom:4px;') do
          builder.text("#{Assets::Icons::LANTERN} 函館 DANMAKU - VS BATTLE #{Assets::Icons::LANTERN}")
        end
        builder.tag(:div, style: 'font-size:13px;color:#888;margin-bottom:24px;') do
          builder.text('〜 ローカル対戦・雑魚撃破でお邪魔送出！ 〜')
        end

        if extra_unlocked
          builder.tag(:div, style: 'font-size:12px;color:#9c27b0;font-weight:bold;letter-spacing:1px;margin-bottom:8px;') do
            builder.text('★ EXTRA UNLOCKED ★')
          end
        end

        builder.tag(:div, style: 'font-size:12px;color:#666;margin-bottom:8px;') { builder.text('← → で難易度を選択') }
        builder.tag(:div, style: 'display:flex;justify-content:center;gap:10px;margin-bottom:8px;') do
          visible.each do |dk|
            selected = dk == difficulty
            c   = Config::DIFF[dk][:color]
            bg  = selected ? "#{c}28" : 'rgba(255,255,255,0.04)'
            bdr = selected ? "2px solid #{c}" : '2px solid #2a2a2a'
            txt = selected ? c : '#555'
            fw  = selected ? 'bold' : 'normal'
            builder.tag(:div, style: "padding:10px 28px;border-radius:8px;background:#{bg};border:#{bdr};font-size:17px;font-weight:#{fw};color:#{txt};") do
              builder.text(Config::DIFF[dk][:label])
            end
          end
        end

        builder.tag(:div, style: "font-size:12px;color:#{d[:color]};margin-bottom:24px;") do
          builder.text(DIFF_DESC[difficulty])
        end

        # 操作説明
        builder.tag(:div, style: 'display:flex;justify-content:center;gap:32px;margin-bottom:24px;') do
          render_controls(builder, color: '#7cf', name: 'P1', keys: 'WASD + LShift')
          render_controls(builder, color: '#f7c', name: 'P2', keys: '↑↓←→ + RShift')
        end

        # ルール
        builder.tag(:div, style: 'background:rgba(255,255,255,0.04);border:1px solid #2a2a2a;border-radius:8px;margin:0 80px 24px;padding:14px;font-size:12px;color:#aaa;line-height:1.6;') do
          builder.tag(:div, style: 'color:#7cf;font-weight:bold;margin-bottom:6px;') { builder.text('▶ ルール') }
          builder.tag(:div) { builder.text("① WAVE: 雑魚 (#{Assets::Icons::ZAKO_BASIC}#{Assets::Icons::ZAKO_TANK}#{Assets::Icons::ZAKO_AGILE}) を撃破して相手にお邪魔送出") }
          builder.tag(:div) { builder.text("② BOSS: 60秒経過で #{Assets::Icons::BOSS_CROWN}#{Assets::Icons::BOSS_BODY} 出現。先に倒した方が勝ち") }
          builder.tag(:div) { builder.text('③ 連続撃破でコンボ。攻撃数が増え、コンボ3でサイン波弾もボーナス送出') }
          builder.tag(:div) { builder.text("④ 雑魚の種類で攻撃パターン変化（#{Assets::Icons::ZAKO_BASIC}拡散 / #{Assets::Icons::ZAKO_TANK}放射 / #{Assets::Icons::ZAKO_AGILE}自機狙い）") }
        end

        builder.tag(:div, style: 'font-size:17px;color:#7cf;') { builder.text('— 任意のキーでスタート —') }
      end
    end

    def render_controls(builder, color:, name:, keys:)
      builder.tag(:div, style: 'text-align:center;') do
        builder.tag(:div, style: "color:#{color};font-weight:bold;font-size:15px;") { builder.text(name) }
        builder.tag(:div, style: 'color:#aaa;font-size:11px;font-family:monospace;margin-top:4px;') { builder.text(keys) }
      end
    end

    def result(builder, battle:)
      title_text = case battle.winner
                   when :p1   then "#{Assets::Icons::TROPHY} P1 WIN!"
                   when :p2   then "#{Assets::Icons::TROPHY} P2 WIN!"
                   when :draw then "#{Assets::Icons::SCALE} DRAW"
                   end
      tint = case battle.winner
             when :p1 then '#7cf'
             when :p2 then '#f7c'
             else          '#f0c040'
             end

      builder.tag(:div, style: full_screen_bg) do
        builder.tag(:div, style: "font-size:48px;font-weight:bold;color:#{tint};margin-bottom:18px;text-shadow:0 0 12px #{tint};") do
          builder.text(title_text)
        end

        builder.tag(:div, style: 'display:flex;gap:48px;justify-content:center;margin-bottom:32px;') do
          render_score_card(builder, battle.p1, color: '#7cf')
          render_score_card(builder, battle.p2, color: '#f7c')
        end

        builder.tag(:div, style: 'display:flex;justify-content:center;gap:16px;margin-bottom:24px;') do
          builder.tag(:div, style: 'background:#1a3a5a;border-radius:8px;padding:10px 20px;font-size:14px;') { builder.text('[R / Enter]  もう一度') }
          builder.tag(:div, style: 'background:#3a1a1a;border-radius:8px;padding:10px 20px;font-size:14px;') { builder.text('[S / Esc]  タイトルへ') }
        end
      end
    end

    def render_score_card(builder, p, color:)
      builder.tag(:div, style: "background:rgba(255,255,255,0.04);border:1px solid #{color}44;border-radius:8px;padding:16px 28px;min-width:180px;") do
        builder.tag(:div, style: "color:#{color};font-weight:bold;font-size:18px;margin-bottom:8px;") { builder.text(p.name) }
        builder.tag(:div, style: 'color:#aaa;font-size:12px;') { builder.text("SCORE  #{p.score}") }
        builder.tag(:div, style: 'color:#aaa;font-size:12px;') { builder.text("SENT   #{p.total_sent}") }
        builder.tag(:div, style: 'color:#aaa;font-size:12px;') { builder.text("LIVES  #{p.lives}") }
      end
    end

    def full_screen_bg
      "display:inline-block;font-family:sans-serif;user-select:none;width:#{Config::W}px;" \
        'background-color:#0a1a2a;' \
        "background-image:linear-gradient(rgba(10,21,37,0.55),rgba(5,10,20,0.85))," \
        "url('/bg-hakodate.png');" \
        'background-size:auto,cover;' \
        'background-position:center,center;' \
        'background-repeat:no-repeat,no-repeat;' \
        'image-rendering:pixelated;' \
        'color:white;text-align:center;padding:40px 0;box-sizing:border-box;'
    end
  end
end

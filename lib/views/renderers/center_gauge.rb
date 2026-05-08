# frozen_string_literal: true

require_relative '../../config'

module Renderers
  # 中央の対戦ゲージ。
  # 上半分: P1 → P2 へ送られた累計お邪魔
  # 下半分: P2 → P1 へ送られた累計お邪魔
  module CenterGauge
    module_function

    MAX_BAR = 30  # この量で満タン表示

    def call(builder, battle:)
      builder.tag(:div, style: outer_style) do
        render_phase(builder, battle)
        render_split(builder, battle)
        render_legend(builder)
      end
    end

    def outer_style
      "width:#{Config::GAUGE_W}px;height:#{Config::PANEL_H}px;flex-shrink:0;" \
        'display:flex;flex-direction:column;align-items:center;' \
        'background:#0a0a14;border:1px solid #1a1a2e;border-radius:6px;padding:8px 4px;box-sizing:border-box;'
    end

    def render_phase(builder, battle)
      remaining = ((Config::WAVE_FRAMES - battle.frame) / Config::FPS.to_f).clamp(0.0, Float::INFINITY)
      label = battle.phase == :wave ? "WAVE #{format('%02d', remaining.ceil)}" : '⚔ BOSS ⚔'
      color = battle.phase == :wave ? '#7cf' : '#f44'
      builder.tag(:div, style: "color:#{color};font-size:11px;font-weight:bold;letter-spacing:1px;margin-bottom:6px;text-align:center;") do
        builder.text(label)
      end
    end

    def render_split(builder, battle)
      bar_h  = (Config::PANEL_H - 100) / 2
      p1_pct = (battle.p1.total_sent.to_f / MAX_BAR).clamp(0.0, 1.0)
      p2_pct = (battle.p2.total_sent.to_f / MAX_BAR).clamp(0.0, 1.0)

      # 上半分（P1の貢献）— transition 不使用、solid color、毎フレーム差分が小さい
      builder.tag(:div, style: "width:14px;height:#{bar_h}px;background:#1a1a2e;border-radius:7px;position:relative;overflow:hidden;margin:4px 0;") do
        builder.tag(:div, style: "position:absolute;left:0;right:0;bottom:0;height:#{(p1_pct * 100).to_i}%;background:#36c;") {}
      end
      builder.tag(:div, style: 'font-size:10px;color:#7cf;') { builder.text("↑#{battle.p1.total_sent}") }

      builder.tag(:div, style: 'font-size:18px;color:#444;margin:6px 0;') { builder.text('×') }

      builder.tag(:div, style: 'font-size:10px;color:#f7c;') { builder.text("↓#{battle.p2.total_sent}") }
      builder.tag(:div, style: "width:14px;height:#{bar_h}px;background:#1a1a2e;border-radius:7px;position:relative;overflow:hidden;margin:4px 0;") do
        builder.tag(:div, style: "position:absolute;left:0;right:0;top:0;height:#{(p2_pct * 100).to_i}%;background:#c39;") {}
      end
    end

    def render_legend(builder)
      builder.tag(:div, style: 'color:#444;font-size:9px;text-align:center;margin-top:auto;') do
        builder.text('SEND')
      end
    end
  end
end

# frozen_string_literal: true

require 'async'
require 'async/barrier'

# ── テスト用 barrier 群 ─────────────────────────────
#
# Lively 本体は Async::Barrier を Battle / Player / GarbageQueue / Boss に注入し、
# 各所で `barrier.async { Fiber }` を呼ぶ。
# テストでは：
#   * 同期処理（tick / move / settle / judge / register_zako_kill! など）の検証だけ
#     したいケース → TestBarrier（Fiber を起動しない null 実装）
#   * Fiber のライフサイクルそのもの（GarbageQueue の警告→展開）を観察したいケース
#     → 本物の Async::Barrier を Sync ブロックで包む
#
# こうすることで「Async リアクタを起動しない普通のテスト」と
# 「Fiber を実際に走らせる結合テスト」を意図的に分離できる。

# Fiber を実際には起動しない null Barrier。
# Battle / Player / Boss / GarbageQueue の同期側ロジックだけを観察したいときに使う。
class TestBarrier
  attr_reader :scheduled

  def initialize
    @scheduled = []   # 起動を試みられた block を一応保持（必要なら手動実行できる）
  end

  # 本物は Async::Task を返すが、テスト用途では nil で十分。
  def async(*, **, &block)
    @scheduled << block if block
    nil
  end

  def stop
    @scheduled.clear
  end

  def wait
    nil
  end
end

# Live::View の builder と同じ呼び出し面（tag / text / raw / inline_tag）を最小限再現する
# キャプチャ用 builder。Renderers::Panel などの出力を文字列・木構造で観察できる。
#
# Lively の builder API は `tag(name, **attrs) { ... }` / `text(str)` / `raw(str)` を
# サポートしていれば本テスト群では十分。
class CaptureBuilder
  attr_reader :nodes

  def initialize
    @nodes = []
    @stack = [@nodes]
  end

  def tag(name, **attrs)
    children = []
    node = {tag: name, attrs: attrs, children: children}
    @stack.last << node
    if block_given?
      @stack.push(children)
      begin
        yield self
      ensure
        @stack.pop
      end
    end
    node
  end

  def text(str)
    @stack.last << {text: str.to_s}
  end

  def raw(str)
    @stack.last << {raw: str.to_s}
  end

  # 全 tag node を再帰列挙
  def each_tag(&block)
    walk(@nodes, &block)
  end

  # 指定したクラス名を含む tag を全部抽出
  def find_by_class(klass)
    out = []
    each_tag do |n|
      classes = (n[:attrs][:class] || '').to_s.split
      out << n if classes.include?(klass.to_s)
    end
    out
  end

  # 指定タグの全ノード
  def find_by_tag(tag_name)
    out = []
    each_tag { |n| out << n if n[:tag] == tag_name }
    out
  end

  def to_html
    @nodes.map { |n| node_to_html(n) }.join
  end

  private

  def walk(nodes, &block)
    nodes.each do |n|
      next unless n.is_a?(Hash) && n[:tag]
      yield n
      walk(n[:children], &block)
    end
  end

  def node_to_html(n)
    return n[:text] if n.key?(:text)
    return n[:raw] if n.key?(:raw)
    attrs_str = n[:attrs].map { |k, v| %( #{k}="#{v}") }.join
    inner = n[:children].map { |c| node_to_html(c) }.join
    "<#{n[:tag]}#{attrs_str}>#{inner}</#{n[:tag]}>"
  end
end

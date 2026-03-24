#!/usr/bin/env ruby
# frozen_string_literal: true

require 'kubeclient'
require 'async'
require 'async/http/internet'
require 'fileutils'

STORE = ENV.fetch('STORE_ROOT', '/nix/store')
CACHE = ENV.fetch('CACHE_URL', 'https://cache.nixos.org')
LABEL = 'nix.cia.net/closure=true'

module StoreDaemon
  module_function

  def kube_client
    Kubeclient::Client.new(
      'https://kubernetes.default.svc',
      'v1',
      auth_options: { bearer_token_file: '/var/run/secrets/kubernetes.io/serviceaccount/token' },
      ssl_options: { ca_file: '/var/run/secrets/kubernetes.io/serviceaccount/ca.crt' }
    )
  end

  def paths_from(configmap)
    configmap.data&.paths&.lines&.map(&:strip)&.reject(&:empty?) || []
  end

  def fetch(store_path, internet)
    hash = File.basename(store_path)[0, 32]
    $stderr.puts "fetching #{File.basename(store_path)}"

    narinfo = internet.get("#{CACHE}/#{hash}.narinfo").read
    url     = narinfo[/^URL: (.+)/, 1]
    comp    = narinfo[/^Compression: (.+)/, 1] || 'xz'
    decomp  = { 'xz' => 'xz -d', 'zstd' => 'zstd -d', 'bzip2' => 'bzip2 -d' }.fetch(comp, 'cat')

    tmp = "#{STORE}/.tmp-#{hash}"
    FileUtils.mkdir_p(tmp)
    system("curl -sf '#{CACHE}/#{url}' | #{decomp} | nix-store --restore #{tmp}/out") or raise "fetch failed"
    File.rename("#{tmp}/out", store_path)
    FileUtils.rm_rf(tmp)
  end

  def sync(configmap)
    Async do
      internet = Async::HTTP::Internet.new
      missing = paths_from(configmap).reject { |p| File.exist?(p) }

      missing.each do |store_path|
        Async { fetch(store_path, internet) }
      end
    ensure
      internet&.close
    end
  end

  def run
    $stderr.puts "store-daemon starting (store=#{STORE} cache=#{CACHE})"
    FileUtils.mkdir_p(STORE)
    client = kube_client

    client.get_config_maps(label_selector: LABEL).each { |cm| sync(cm) }

    client.watch_config_maps(label_selector: LABEL).each do |notice|
      sync(notice.object) if %w[ADDED MODIFIED].include?(notice.type)
    end
  rescue Kubeclient::WatchError
    retry
  end
end

StoreDaemon.run

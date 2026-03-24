#!/usr/bin/env ruby
# frozen_string_literal: true

require 'kubeclient'
require 'fileutils'

STORE = ENV.fetch('STORE_ROOT', '/nix/store')
CACHE = ENV.fetch('CACHE_URL', 'https://cache.nixos.org')
LABEL = 'nix-store-operator.ghcr.io/mount=true'

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

  def sync(configmap)
    wanted = paths_from(configmap)
    missing = wanted.reject { |p| File.exist?(p) }
    return if missing.empty?

    $stderr.puts "fetching #{missing.length} store paths"
    missing.each { |p| $stderr.puts "  #{File.basename(p)}" }

    system("nix", "copy", "--from", CACHE, "--no-check-sigs", *missing) or
      $stderr.puts "WARNING: nix copy failed for some store paths"
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

#!/usr/bin/env ruby
# frozen_string_literal: true

require 'kubeclient'
require 'fileutils'

STORE  = ENV.fetch('STORE_ROOT', '/nix/store')
MOUNTS = ENV.fetch('MOUNTS_ROOT', '/var/lib/nixfs/mounts')
CACHE  = ENV.fetch('CACHE_URL', 'https://cache.nixos.org')
LABEL  = 'nix-store-operator.ghcr.io/mount=true'

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

    unless missing.empty?
      $stderr.puts "fetching #{missing.length} store paths"
      missing.each { |p| $stderr.puts "  #{File.basename(p)}" }

      system("nix", "copy", "--from", CACHE, "--no-check-sigs", *missing) or
        $stderr.puts "WARNING: nix copy failed for some store paths"
    end

    link_mount(configmap)
  end

  def link_mount(configmap)
    name = configmap.metadata.name
    mount_dir = File.join(MOUNTS, name)

    FileUtils.rm_rf(mount_dir)
    FileUtils.mkdir_p(mount_dir)

    linked = 0
    paths_from(configmap).each do |store_path|
      basename = File.basename(store_path)
      src = File.join(STORE, basename)
      dst = File.join(mount_dir, basename)
      if File.exist?(src)
        system("cp", "-rl", src, dst)
        linked += 1
      else
        $stderr.puts "WARNING: store path missing: #{basename}"
      end
    end

    $stderr.puts "mounted #{name} (#{linked} paths)"
  end

  def unlink_mount(configmap)
    name = configmap.metadata.name
    mount_dir = File.join(MOUNTS, name)
    FileUtils.rm_rf(mount_dir)
    $stderr.puts "unmounted #{name}"
  end

  def run
    $stderr.puts "store-daemon starting (store=#{STORE} mounts=#{MOUNTS} cache=#{CACHE})"
    FileUtils.mkdir_p(STORE)
    FileUtils.mkdir_p(MOUNTS)
    client = kube_client

    # Initial reconciliation
    client.get_config_maps(label_selector: LABEL).each { |cm| sync(cm) }

    # Watch for changes
    client.watch_config_maps(label_selector: LABEL).each do |notice|
      case notice.type
      when 'ADDED', 'MODIFIED'
        sync(notice.object)
      when 'DELETED'
        unlink_mount(notice.object)
      end
    end
  rescue Kubeclient::WatchError
    retry
  end
end

StoreDaemon.run

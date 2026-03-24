#!/usr/bin/env ruby
# frozen_string_literal: true

# fuse-daemon - FUSE filesystem that lazily fetches /nix/store paths from a binary cache.
#
# Mounts a read-only passthrough FUSE at MOUNT, backed by ROOT. The backing
# directory is separate from the mount point so downloads (via nix-download)
# write directly to ROOT without going through FUSE.
#
# On access to a whitelisted store path missing from ROOT, fetches it (and its
# full closure) via nix-download. Paths not in the whitelist are denied.

require 'rfuse'
require 'set'
require 'optparse'
require 'fileutils'

$stdout.sync = true
$stderr.sync = true

def log(msg)
  $stderr.puts "fuse-daemon: #{msg}"
end

class FuseDaemon
  STORE_PREFIX = '/nix/store'

  def initialize(root, whitelist, cache)
    @root  = root
    @cache = cache
    @whitelist = whitelist

    @lock       = Mutex.new
    @path_locks = {}
    @fetched    = Set.new
  end

  # ── helpers ──────────────────────────────────────────────────────────

  def real(path)
    path = path.b if path.encoding != Encoding::ASCII_8BIT
    ensure_fetched(path)
    File.join(@root, path)
  end

  def store_basename(path)
    path = path.b if path.encoding != Encoding::ASCII_8BIT
    parts = path.delete_prefix('/'.b).split('/'.b)
    parts.first&.force_encoding('UTF-8')
  end

  def ensure_fetched(path)
    basename = store_basename(path)
    return unless basename
    return if @fetched.include?(basename)
    return if File.exist?(File.join(@root, basename))

    store_path = "#{STORE_PREFIX}/#{basename}"
    unless @whitelist.include?(store_path)
      log "DENIED #{basename} (not in whitelist)"
      return
    end

    mu = @lock.synchronize { @path_locks[basename] ||= Mutex.new }

    mu.synchronize do
      return if File.exist?(File.join(@root, basename))
      log "FETCH #{basename}"
      ok = system('nix-download', '-store', @root, '-substituter', @cache, store_path)
      if ok
        log "OK    #{basename}"
        @fetched.add(basename)
      else
        log "FAIL  #{basename} (nix-download exit #{$?.exitstatus})"
      end
    end
  end

  def to_rfuse_stat(s)
    type = if    s.directory? then RFuse::Stat::S_IFDIR
           elsif s.symlink?   then RFuse::Stat::S_IFLNK
           elsif s.file?      then RFuse::Stat::S_IFREG
           else RFuse::Stat::S_IFREG
           end

    RFuse::Stat.new(type, s.mode & 0o7777,
      size:  s.size,
      uid:   s.uid,
      gid:   s.gid,
      atime: s.atime,
      mtime: s.mtime,
      ctime: s.ctime,
      nlink: s.nlink,
    )
  end

  # ── FUSE operations ─────────────────────────────────────────────────

  def getattr(ctx, path)
    to_rfuse_stat(File.lstat(real(path)))
  rescue Errno::ENOENT
    raise Errno::ENOENT, path
  rescue => e
    log "ERR getattr #{path}: #{e.class}: #{e.message}"
    raise Errno::EIO
  end

  def readdir(ctx, path, filler, offset, ffi)
    Dir.foreach(real(path)) { |e| filler.push(e, nil, 0) }
  rescue Errno::ENOENT
    raise Errno::ENOENT, path
  rescue => e
    log "ERR readdir #{path}: #{e.class}: #{e.message}"
    raise Errno::EIO
  end

  def readlink(ctx, path)
    target = File.readlink(real(path))
    target + "\0"
  rescue Errno::ENOENT
    raise Errno::ENOENT, path
  rescue => e
    log "ERR readlink #{path}: #{e.class}: #{e.message}"
    raise Errno::EIO
  end

  def open(ctx, path, ffi)
    ffi.fh = IO.sysopen(real(path), File::RDONLY)
  rescue Errno::ENOENT
    raise Errno::ENOENT, path
  rescue => e
    log "ERR open #{path}: #{e.class}: #{e.message}"
    raise Errno::EIO
  end

  def read(ctx, path, size, offset, ffi)
    io = IO.new(ffi.fh, 'rb', autoclose: false)
    io.sysseek(offset)
    io.sysread(size)
  rescue EOFError
    ''
  rescue => e
    log "ERR read #{path}: #{e.class}: #{e.message}"
    raise Errno::EIO
  end

  def release(ctx, path, ffi)
    IO.new(ffi.fh, autoclose: true).close rescue nil
  end

  def statfs(ctx, path)
    RFuse::StatVfs.new
  end

  def access(ctx, path, mode)
    real(path)
    0
  rescue Errno::ENOENT
    raise Errno::EACCES
  rescue => e
    log "ERR access #{path}: #{e.class}: #{e.message}"
    raise Errno::EIO
  end
end

# ── main ────────────────────────────────────────────────────────────────

options = {
  root:      '/data/store',
  mount:     '/mnt/nix/store',
  whitelist: '/etc/nix/store-whitelist',
  cache:     ENV.fetch('CACHE_URL', 'https://cache.nixos.org'),
}

OptionParser.new do |opts|
  opts.banner = 'Usage: fuse-daemon.rb [options]'
  opts.on('--root DIR',      'Backing store directory')       { |v| options[:root] = v }
  opts.on('--mount DIR',     'FUSE mount point')              { |v| options[:mount] = v }
  opts.on('--whitelist FILE','Path whitelist (one per line)')  { |v| options[:whitelist] = v }
  opts.on('--cache URL',     'Binary cache URL')              { |v| options[:cache] = v }
end.parse!

whitelist = Set.new(
  File.readlines(options[:whitelist]).map(&:strip).reject(&:empty?)
)

log "root=#{options[:root]} mount=#{options[:mount]} cache=#{options[:cache]} whitelist=#{whitelist.size} paths"
whitelist.each { |p| log "  whitelist: #{p}" }

FileUtils.mkdir_p(options[:root])
FileUtils.mkdir_p(options[:mount])

# Log what's already in the backing store
existing = Dir.children(options[:root]) rescue []
unless existing.empty?
  log "#{existing.size} paths already in backing store:"
  existing.each { |e| log "  exists: #{e}" }
end

fuse_opts = 'ro,default_permissions'
fuse_opts += ',allow_other' if File.readable?('/etc/fuse.conf') &&
  File.read('/etc/fuse.conf').include?('user_allow_other')

log "mounting FUSE at #{options[:mount]} (opts: #{fuse_opts})"

fs = RFuse::FuseDelegator.new(
  FuseDaemon.new(options[:root], whitelist, options[:cache]),
  options[:mount],
  '-o', fuse_opts
)

log "FUSE mounted, entering event loop"
fs.loop

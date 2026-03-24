{ pkgs }:

drv: pkgs.runCommand "${drv.name}-closure" {} ''
  cat ${pkgs.closureInfo { rootPaths = [ drv ]; }}/store-paths > $out
''

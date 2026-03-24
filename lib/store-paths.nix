{ pkgs }:

drv: pkgs.runCommand "${drv.name}-store-paths" {} ''
  cat ${pkgs.closureInfo { rootPaths = [ drv ]; }}/store-paths > $out
''

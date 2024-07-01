self: { pkgs, lib, ... }: {
  nixpkgs.overlays = [ self.overlays.default ];
  programs.nh.package = lib.mkDefault pkgs.nh_darwin;
}

{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/~0.1.tar.gz";
    crate2nix.url = "github:nix-community/crate2nix";
  };

  outputs =
    { self
    , nixpkgs
    , crate2nix
    }:
    let
      forAllSystems = function:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
          # experimental
          "x86_64-darwin"
          "aarch64-darwin"
        ]
          (system:
            function (import nixpkgs {
              inherit system;
            }));

      lib = nixpkgs.lib;
      rev = self.shortRev or self.dirtyShortRev or "dirty";
    in
    {
      overlays.default = final: prev: {
        nh_darwin = self.packages.${final.stdenv.hostPlatform.system}.nh_darwin;
      };

      packages = forAllSystems (pkgs: rec {
          nh_darwin = pkgs.callPackage ./package.nix {
            inherit rev;
          };
          default = nh_darwin;
        });

      devShells = forAllSystems (pkgs: {
        default = pkgs.callPackage ./devshell.nix { };
      });

      nixosModules.default = import ./module.nix self;
      # use this module before this pr is merged https://github.com/LnL7/nix-darwin/pull/942
      nixDarwinModules.prebuiltin = import ./darwin-module.nix self;
      # use this module after that pr is merged
      nixDarwinModules.default = import ./module.nix self;
      # use this module before this pr is merged https://github.com/nix-community/home-manager/pull/5304
      homeManagerModules.prebuiltin = import ./home-manager-module.nix self;
      # use this module after that pr is merged
      homeManagerModules.default = import ./module.nix self;
    };
}

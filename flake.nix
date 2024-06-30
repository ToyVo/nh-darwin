{
  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/~0.1.tar.gz";
    crate2nix.url = "github:nix-community/crate2nix";
  };

  outputs =
    { self
    , nixpkgs
    , crate2nix
    ,
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
    in
    {
      overlays.default = final: prev: {
        nh_darwin = self.packages.${final.stdenv.hostPlatform.system}.nh_darwin;
      };

      packages = forAllSystems (pkgs:
        let
          generated = crate2nix.tools.${pkgs.stdenv.hostPlatform.system}.generatedCargoNix {
            name = "nh_darwin";
            src = ./.;
          };
          crates = pkgs.callPackage "${generated}/default.nix" {
            buildRustCrateForPkgs = pkgs: pkgs.buildRustCrate.override {
              defaultCrateOverrides = pkgs.defaultCrateOverrides // {
                nh_darwin = attrs: {
                  buildInputs = with pkgs.darwin.apple_sdk.frameworks; lib.optionals (pkgs.stdenv.isDarwin) [
                    SystemConfiguration
                  ];
                  nativeBuildInputs = with pkgs; [
                    installShellFiles
                    makeBinaryWrapper
                  ];
                  preFixup = ''
                    mkdir completions
                    $out/bin/nh_darwin completions --shell bash > completions/nh_darwin.bash
                    $out/bin/nh_darwin completions --shell zsh > completions/nh_darwin.zsh
                    $out/bin/nh_darwin completions --shell fish > completions/nh_darwin.fish
                    installShellCompletion completions/*
                  '';

                  postFixup = ''
                    wrapProgram $out/bin/nh_darwin \
                      --prefix PATH : ${lib.makeBinPath [pkgs.nvd pkgs.nix-output-monitor]}
                  '';

                  meta = {
                    description = "Yet another nix cli helper. Works on NixOS, NixDarwin, and HomeManager Standalone";
                    homepage = "https://github.com/ToyVo/nh_darwin";
                    license = lib.licenses.eupl12;
                    mainProgram = "nh_darwin";
                    maintainers = with lib.maintainers; [drupol viperML ToyVo];
                  };
                };
              };
            };
          };
        in
        rec {
          nh_darwin = crates.workspaceMembers.nh_darwin.build;
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

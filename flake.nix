{
  description = "nh_darwin";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    rust-overlay.url = "github:oxalica/rust-overlay";
    crate2nix.url = "github:nix-community/crate2nix";

    # Development

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-trusted-public-keys = "eigenvalue.cachix.org-1:ykerQDDa55PGxU25CETy9wF6uVDpadGGXYrFNJA3TUs=";
    extra-substituters = "https://eigenvalue.cachix.org";
    allow-import-from-derivation = true;
  };

  outputs =
    inputs @ { self
    , nixpkgs
    , flake-parts
    , rust-overlay
    , crate2nix
    , devshell
    }: flake-parts.lib.mkFlake { inherit inputs; } {
      flake = {
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

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      imports = [
        devshell.flakeModule
        flake-parts.flakeModules.easyOverlay
      ];

      perSystem = { system, pkgs, lib, inputs', config, ... }:
        let
          # If you dislike IFD, you can also generate it with `crate2nix generate`
          # on each dependency change and import it here with `import ./Cargo.nix`.
          generatedCargoNix = crate2nix.tools.${system}.generatedCargoNix {
            name = "nh_darwin";
            src = ./.;
          };
          cargoNix = pkgs.callPackage "${generatedCargoNix}/default.nix" {
            buildRustCrateForPkgs = pkgs: pkgs.buildRustCrate.override {
              defaultCrateOverrides = pkgs.defaultCrateOverrides // {
                nh_darwin = attrs: {
                  postInstall = ''
                    wrapProgram $out/bin/nh_darwin \
                      --prefix PATH : ${lib.makeBinPath [pkgs.nvd pkgs.nix-output-monitor]}
                    mkdir completions
                    $out/bin/nh_darwin completions --shell bash > completions/nh_darwin.bash
                    $out/bin/nh_darwin completions --shell zsh > completions/nh_darwin.zsh
                    $out/bin/nh_darwin completions --shell fish > completions/nh_darwin.fish
                    installShellCompletion completions/*
                  '';

                  buildInputs = with pkgs; [
                    nvd
                    nix-output-monitor
                  ]
                  ++ lib.optionals
                    stdenv.isDarwin
                    [ darwin.apple_sdk.frameworks.Security ];

                  nativeBuildInputs = with pkgs; [
                    installShellFiles
                    makeBinaryWrapper
                  ];

                  meta = {
                    description = "Yet another nix cli helper. Works on NixOS, NixDarwin, and HomeManager Standalone";
                    homepage = "https://github.com/ToyVo/nh_darwin";
                    license = lib.licenses.eupl12;
                    mainProgram = "nh_darwin";
                    maintainers = with lib.maintainers; [ drupol viperML ToyVo ];
                  };
                };
              };
            };
          };
        in
        rec {
          _module.args.pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (import rust-overlay)
              (final: prev: assert !(prev ? rust-toolchain); rec {
                rust-toolchain = (prev.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml).override {
                  extensions = [ "rust-src" "rust-std" "rust-analyzer" "rustfmt" "clippy" ];
                };

                # buildRustCrate/crate2nix depend on this.
                rustc = rust-toolchain;
                cargo = rust-toolchain;
                rustfmt = rust-toolchain;
                clippy = rust-toolchain;
                rust-analyzer = rust-toolchain;
              })
            ];
            config = { };
          };

          overlayAttrs = {
            inherit (config.packages) nh_darwin;
          };

          packages = {
            nh_darwin = cargoNix.workspaceMembers.nh_darwin.build;
            default = packages.nh_darwin;

            inherit (pkgs) rust-toolchain;

            rust-toolchain-versions = pkgs.writeScriptBin "rust-toolchain-versions" ''
              ${pkgs.rust-toolchain}/bin/cargo --version
              ${pkgs.rust-toolchain}/bin/rustc --version
            '';
          };

          devshells.default = {
            imports = [
              "${devshell}/extra/language/c.nix"
              # "${devshell}/extra/language/rust.nix"
            ];

            env = [
              {
                name = "NH_NOM";
                value = "1";
              }
              {
                name = "RUST_LOG";
                value = "nh_darwin=trace";
              }
              {
                name = "RUST_SRC_PATH";
                value = "${pkgs.rust-toolchain}/lib/rustlib/src/rust/library";
              }
            ];

            commands = with pkgs; [
              { package = rust-toolchain; category = "rust"; }
            ];

            packages = with pkgs; [
              nvd
              nix-output-monitor
            ];

            language.c = {
              libraries = lib.optional pkgs.stdenv.isDarwin pkgs.libiconv;
            };
          };
        };
    };
}

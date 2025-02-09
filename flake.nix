{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    treefmt.url = "github:numtide/treefmt-nix";
    treefmt.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    treefmt,
  }: let
    forEachSystem = nixpkgs.lib.genAttrs [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-darwin"
      "x86_64-linux"
    ];

    clientCargoToml = nixpkgs.lib.importTOML ./client/Cargo.toml;

    # https://github.com/ipetkov/crane/blob/112e6591b2d6313b1bd05a80a754a8ee42432a7e/lib/cleanCargoSource.nix
    cargoSrc = nixpkgs.lib.cleanSourceWith {
      # Apply the default source cleaning from nixpkgs
      src = nixpkgs.lib.cleanSource self;
      # https://github.com/ipetkov/crane/blob/112e6591b2d6313b1bd05a80a754a8ee42432a7e/lib/filterCargoSources.nix
      filter = orig_path: type: let
        path = toString orig_path;
        base = baseNameOf path;
        parentDir = baseNameOf (dirOf path);

        matchesSuffix = nixpkgs.lib.any (suffix: nixpkgs.lib.hasSuffix suffix base) [
          # Keep rust sources
          ".rs"
          # Keep all toml files as they are commonly used to configure other
          # cargo-based tools
          ".toml"
        ];

        # Cargo.toml already captured above
        isCargoFile = base == "Cargo.lock";

        # .cargo/config.toml already captured above
        isCargoConfig = parentDir == ".cargo" && base == "config";
      in
        type == "directory" || matchesSuffix || isCargoFile || isCargoConfig;
    };

    treefmtEval = pkgs:
      treefmt.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          alejandra.enable = true;
          prettier.enable = true;
          rustfmt.enable = true;
          taplo.enable = true;
        };
      };

    overlay = final: prev: {
      nix-post-build-hook-queue = prev.rustPlatform.buildRustPackage {
        pname = "nix-post-build-hook-queue";
        version = clientCargoToml.package.version;

        src = cargoSrc;

        cargoDeps = prev.rustPlatform.importCargoLock {
          lockFile = ./Cargo.lock;
        };

        nativeCheckInputs = [prev.clippy];

        preCheck = ''
          echo "Running clippy..."
          cargo clippy -- -Dwarnings
        '';

        meta = {
          description = "Nix post-build-hook queue";
          homepage = clientCargoToml.package.repository;
          license = prev.lib.licenses.mit;
          maintainers = [prev.lib.maintainers.newam];
        };
      };
    };
  in {
    packages = forEachSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [overlay];
        };
      in {
        default = pkgs.nix-post-build-hook-queue;
      }
    );

    formatter = forEachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        (treefmtEval pkgs).config.build.wrapper
    );

    checks = forEachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      pkgs = self.packages.${system}.default;

      formatting = (treefmtEval pkgs).config.build.check self;

      basic = pkgs.callPackage ./nixos/tests/basic.nix {inherit self;};
    });

    overlays.default = overlay;

    nixosModules.default = import ./nixos/module.nix;
  };
}

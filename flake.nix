{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane.url = "github:ipetkov/crane";

    treefmt.url = "github:numtide/treefmt-nix";
    treefmt.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    crane,
    treefmt,
  }: let
    forEachSystem = nixpkgs.lib.genAttrs [
      "aarch64-darwin"
      "aarch64-linux"
      "x86_64-darwin"
      "x86_64-linux"
    ];

    clientCargoToml = nixpkgs.lib.importTOML ./client/Cargo.toml;
    serverCargoToml = nixpkgs.lib.importTOML ./server/Cargo.toml;

    srcClean = pkgs: (crane.mkLib pkgs).cleanCargoSource self;

    namePrefix = "nix-post-build-hook-queue";
    inherit (clientCargoToml.package) version;

    cargoArtifacts = pkgs:
      (crane.mkLib pkgs).buildDepsOnly {
        pname = "${namePrefix}-deps";
        inherit version;
        src = srcClean pkgs;
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
  in {
    packages = forEachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        client = (crane.mkLib pkgs).buildPackage {
          pname = clientCargoToml.package.name;
          inherit version;
          src = srcClean pkgs;
          cargoArtifacts = cargoArtifacts pkgs;
          cargoExtraArgs = "-p ${clientCargoToml.package.name}";
        };
        server = (crane.mkLib pkgs).buildPackage {
          pname = serverCargoToml.package.name;
          inherit version;
          src = srcClean pkgs;
          cargoArtifacts = cargoArtifacts pkgs;
          cargoExtraArgs = "-p ${serverCargoToml.package.name}";
        };
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
      inherit (self.packages.${system}) client server;

      clippy = (crane.mkLib pkgs).cargoClippy {
        pname = "${namePrefix}-clippy";
        inherit version;
        src = srcClean pkgs;
        cargoArtifacts = cargoArtifacts pkgs;
        cargoClippyExtraArgs = "-- --deny warnings";
      };

      formatting = (treefmtEval pkgs).config.build.check self;

      basic = pkgs.callPackage ./nixos/tests/basic.nix {inherit self;};
    });

    overlays.default = final: prev: {
      nix-post-build-hook-queue-client = self.packages.${prev.system}.client;
      nix-post-build-hook-queue-server = self.packages.${prev.system}.server;
    };

    nixosModules.default = import ./nixos/module.nix;
  };
}

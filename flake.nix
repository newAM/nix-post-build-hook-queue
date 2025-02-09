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
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];

    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    craneLib = crane.mkLib pkgs;

    clientCargoToml = nixpkgs.lib.importTOML ./client/Cargo.toml;
    serverCargoToml = nixpkgs.lib.importTOML ./server/Cargo.toml;

    src = craneLib.cleanCargoSource self;

    namePrefix = "nix-post-build-hook-queue";
    inherit (clientCargoToml.package) version;

    cargoArtifacts = craneLib.buildDepsOnly {
      pname = "${namePrefix}-deps";
      inherit src version;
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
    packages.x86_64-linux = {
      client = craneLib.buildPackage {
        inherit src cargoArtifacts version;
        pname = clientCargoToml.package.name;
        cargoExtraArgs = "-p ${clientCargoToml.package.name}";
      };
      server = craneLib.buildPackage {
        inherit src cargoArtifacts version;
        pname = serverCargoToml.package.name;
        cargoExtraArgs = "-p ${serverCargoToml.package.name}";
      };
    };

    formatter = forEachSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        (treefmtEval pkgs).config.build.wrapper
    );

    checks.x86_64-linux = {
      inherit (self.packages.x86_64-linux) client server;

      clippy = craneLib.cargoClippy {
        pname = "${namePrefix}-clippy";
        inherit src cargoArtifacts version;
        cargoClippyExtraArgs = "-- --deny warnings";
      };

      formatting = (treefmtEval pkgs).config.build.check self;
    };

    overlays.default = final: prev: {
      nix-post-build-hook-queue-client = self.packages.${prev.system}.client;
      nix-post-build-hook-queue-server = self.packages.${prev.system}.server;
    };

    nixosModules.default = import ./nixos/module.nix;
  };
}

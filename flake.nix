{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    crane,
  }: let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
    craneLib = crane.mkLib pkgs;

    clientCargoToml = nixpkgs.lib.importTOML ./client/Cargo.toml;
    serverCargoToml = nixpkgs.lib.importTOML ./server/Cargo.toml;

    src = craneLib.cleanCargoSource ./.;

    namePrefix = "nix-post-build-hook-queue";
    inherit (clientCargoToml.package) version;

    cargoArtifacts = craneLib.buildDepsOnly {
      pname = "${namePrefix}-deps";
      inherit src version;
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

    checks.x86_64-linux = let
      nixSrc = nixpkgs.lib.sources.sourceFilesBySuffices ./. [".nix"];
    in {
      inherit (self.packages.x86_64-linux) client server;

      clippy = craneLib.cargoClippy {
        pname = "${namePrefix}-clippy";
        inherit src cargoArtifacts version;
        cargoClippyExtraArgs = "-- --deny warnings";
      };

      rustfmt = craneLib.cargoFmt {
        pname = "${namePrefix}-rustfmt";
        inherit src version;
      };

      alejandra = pkgs.runCommand "alejandra" {} ''
        ${pkgs.alejandra}/bin/alejandra --check ${nixSrc}
        touch $out
      '';
    };

    overlays.default = final: prev: {
      nix-post-build-hook-queue-client = self.packages.${prev.system}.client;
      nix-post-build-hook-queue-server = self.packages.${prev.system}.server;
    };

    nixosModules.default = import ./module.nix;
  };
}

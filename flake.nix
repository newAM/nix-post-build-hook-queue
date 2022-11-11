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
    craneLib = crane.lib.x86_64-linux;

    clientCargoToml = nixpkgs.lib.importTOML ./client/Cargo.toml;
    serverCargoToml = nixpkgs.lib.importTOML ./server/Cargo.toml;

    src = craneLib.cleanCargoSource ./.;

    cargoArtifacts = craneLib.buildDepsOnly {inherit src;};
  in {
    packages.x86_64-linux = {
      client = crane.lib.x86_64-linux.buildPackage {
        inherit src cargoArtifacts;
        pname = clientCargoToml.package.name;
        inherit (clientCargoToml.package) version;
        cargoExtraArgs = "-p ${clientCargoToml.package.name}";
      };
      server = crane.lib.x86_64-linux.buildPackage {
        inherit src cargoArtifacts;
        pname = serverCargoToml.package.name;
        inherit (serverCargoToml.package) version;
        cargoExtraArgs = "-p ${serverCargoToml.package.name}";
      };
    };

    checks.x86_64-linux = let
      nixSrc = nixpkgs.lib.sources.sourceFilesBySuffices ./. [".nix"];
    in {
      inherit (self.packages.x86_64-linux) client server;

      clippy = craneLib.cargoClippy {
        inherit src cargoArtifacts;
        cargoClippyExtraArgs = "-- --deny warnings";
      };

      rustfmt = craneLib.cargoFmt {inherit src;};

      alejandra = pkgs.runCommand "alejandra" {} ''
        ${pkgs.alejandra}/bin/alejandra --check ${nixSrc}
        touch $out
      '';

      statix = pkgs.runCommand "statix" {} ''
        ${pkgs.statix}/bin/statix check ${nixSrc}
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

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

    commonArgs.src = craneLib.cleanCargoSource ./.;

    cargoArtifacts = craneLib.buildDepsOnly commonArgs;
  in {
    packages.x86_64-linux = {
      client = crane.lib.x86_64-linux.buildPackage (commonArgs
        // {
          inherit cargoArtifacts;
          pname = clientCargoToml.package.name;
          inherit (clientCargoToml.package) version;
          cargoExtraArgs = "-p ${clientCargoToml.package.name}";
        });
      server = crane.lib.x86_64-linux.buildPackage (commonArgs
        // {
          inherit cargoArtifacts;
          pname = serverCargoToml.package.name;
          inherit (serverCargoToml.package) version;
          cargoExtraArgs = "-p ${serverCargoToml.package.name}";
        });
    };

    checks.x86_64-linux = {
      inherit (self.packages.x86_64-linux) client server;

      clippy = craneLib.cargoClippy (commonArgs
        // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "-- --deny warnings";
        });

      rustfmt = craneLib.cargoFmt {inherit (commonArgs) src;};

      alejandra = pkgs.runCommand "alejandra" {} ''
        ${pkgs.alejandra}/bin/alejandra --check ${./.}
        touch $out
      '';

      statix = pkgs.runCommand "statix" {} ''
        ${pkgs.statix}/bin/statix check ${./.}
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

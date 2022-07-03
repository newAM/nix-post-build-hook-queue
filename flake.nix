{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, crane }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      craneLib = crane.lib.x86_64-linux;

      clientCargoToml = nixpkgs.lib.importTOML ./client/Cargo.toml;
      serverCargoToml = nixpkgs.lib.importTOML ./server/Cargo.toml;

      commonArgs = {
        src = ./.;
      };

      cargoArtifacts = craneLib.buildDepsOnly commonArgs;
    in
    {
      packages.x86_64-linux = {
        client = crane.lib.x86_64-linux.buildPackage (commonArgs // {
          inherit cargoArtifacts;
          pname = clientCargoToml.package.name;
          inherit (clientCargoToml.package) version;
          cargoBuildCommand = "cargo build -p ${clientCargoToml.package.name} --release";
          cargoTestCommand = "cargo test -p ${clientCargoToml.package.name} --release";
        });
        server = crane.lib.x86_64-linux.buildPackage (commonArgs // {
          inherit cargoArtifacts;
          pname = serverCargoToml.package.name;
          inherit (serverCargoToml.package) version;
          cargoBuildCommand = "cargo build -p ${serverCargoToml.package.name} --release";
          cargoTestCommand = "cargo test -p ${serverCargoToml.package.name} --release";
        });
      };

      checks.x86_64-linux = {
        inherit (self.packages.x86_64-linux) client server;

        clippy = craneLib.cargoClippy (commonArgs // {
          inherit cargoArtifacts;
          cargoClippyExtraArgs = "-- --deny warnings";
        });

        rustfmt = craneLib.cargoFmt { src = ./.; };

        nixpkgs-fmt = pkgs.runCommand "nixpkgs-fmt" { } ''
          ${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt --check ${./.}
          touch $out
        '';

        statix = pkgs.runCommand "statix" { } ''
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

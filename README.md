# Nix post-build-hook queue

[![CI](https://github.com/newAM/nix-post-build-hook-queue/workflows/CI/badge.svg)](https://github.com/newAM/nix-post-build-hook-queue/actions)

From [Using the post-build-hook] in the nix manual:

> The post build hook program runs after each executed build, and blocks the build loop. The build loop exits if the hook program fails.
>
> Concretely, this implementation will make Nix slow or unusable when the internet is slow or unreliable.
>
> A more advanced implementation might pass the store paths to a user-supplied daemon or queue for processing the store paths outside of the build loop.

This is my implementation of a user-supplied daemon to process the store paths outside of the build loop.

There are two binaries, a server and a client, both running on the same system.

The client binary is called by `post-build-hook` in `nix.conf`, the server binary runs as a daemon.

The client sends store paths to the server via unix domain socket.

The server daemon will:

1. Sign paths, if `signingPrivateKeyPath` is set
2. Upload paths, if `uploadTo` is set

## Usage

- Add this repository to your flake inputs:

```nix
{
  inputs = {
    unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    nix-post-build-hook-queue = {
      url = "github:newam/nix-post-build-hook-queue";
      inputs.nixpkgs.follows = "unstable";
      inputs.treefmt.follows = "";
    };
  };
}
```

- Add `nix-post-build-hook-queue.overlays.default` to `nixpkgs.overlays`.
- Import the `nix-post-build-hook-queue.nixosModules.default` module.
- Configure:

```nix
{ config, ... }:

{
  # Use sops-nix to store keys: https://github.com/Mic92/sops-nix
  # Alternatives: https://nixos.wiki/wiki/Comparison_of_secret_managing_schemes
  sops.secrets =
    let
      sopsAttrs = {
        mode = "0400";
        owner = config.services.nix-post-build-hook-queue.user;
        restartUnits = [ "nix-post-build-hook-queue.service" ];
      };
    in
    {
      cache-signing-priv-key = sopsAttrs;
      cache-ssh-priv-key = sopsAttrs;
    };

  services.nix-post-build-hook-queue = {
    enable = true;
    # optional setting to sign paths before uploading
    signingPrivateKeyPath = config.sops.secrets.cache-signing-priv-key.path;
    # optional settings to upload store paths after signing
    sshPrivateKeyPath = config.sops.secrets.cache-ssh-priv-key.path;
    uploadTo = "ssh://nix-ssh@nix-cache.example.com";
  };
}
```

[Using the post-build-hook]: https://nixos.org/manual/nix/stable/advanced-topics/post-build-hook.html#implementation-caveats

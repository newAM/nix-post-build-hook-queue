{
  lib,
  self,
  pkgs,
}: let
  cacheDomain = "nix-cache.local";
in
  pkgs.nixosTest {
    name = "basic";

    nodes = {
      build = {
        pkgs,
        nodes,
        modulesPath,
        ...
      }: {
        imports = [
          self.nixosModules.default
          "${modulesPath}/installer/cd-dvd/channel.nix"
        ];
        nixpkgs.overlays = [self.overlays.default];

        networking.hosts.${nodes.cache.networking.primaryIPAddress} = [cacheDomain];

        virtualisation.writableStore = true;

        # do not attempt to fetch from cache.nixos.org
        nix.settings = {
          substituters = lib.mkForce [];
          experimental-features = "nix-command";
        };

        services.nix-post-build-hook-queue = {
          enable = true;
          sshPrivateKeyPath = ./test_key;
          uploadTo = "ssh://nix-ssh@${cacheDomain}";
        };

        programs.ssh.knownHosts.${cacheDomain} = {
          hostNames = [cacheDomain];
          publicKeyFile = ./test_host_key.pub;
        };
      };

      cache = {
        config,
        pkgs,
        nodes,
        ...
      }: {
        nix = {
          sshServe = {
            enable = true;
            write = true;
            keys = [
              (builtins.readFile ./test_key.pub)
            ];
          };
          # required for writing without a valid signature
          settings.trusted-users = ["nix-ssh"];
        };

        environment.etc = {
          "ssh/ssh_host_ed25519_key" = {
            source = ./test_host_key;
            mode = "0600";
          };
          "ssh/ssh_host_ed25519_key.pub" = {
            source = ./test_host_key.pub;
            mode = "0644";
          };
        };

        services.openssh = {
          enable = true;
          hostKeys = [
            {
              type = "ed25519";
              path = "/etc/ssh/ssh_host_ed25519_key";
            }
          ];
        };
      };
    };

    testScript = ''
      # from nixos/tests/qemu-vm-store.nix
      build_derivation = """
        nix-build --option substitute false -E 'derivation {{
          name = "{name}";
          builder = "/bin/sh";
          args = ["-c" "echo something > $out"];
          system = builtins.currentSystem;
          preferLocalBuild = true;
        }}'
      """

      start_all()

      build.systemctl("start network-online.target")
      cache.systemctl("start network-online.target")
      build.wait_for_unit("network-online.target")
      cache.wait_for_unit("network-online.target")

      with subtest("Basic upload"):
        for name in ("a", "b"):
          store_path: str = build.succeed(build_derivation.format(name=name)).rsplit(" ", 1)[-1].strip()
          print(f"{store_path=}")
          cache.wait_until_succeeds(f"nix-store --verify-path {store_path}", timeout=3)

      with subtest("Ensure nix-post-build-hook-queue can stop gracefully"):
        build.systemctl("stop nix-post-build-hook-queue.service")
        build.succeed("journalctl --grep 'nix-post-build-hook-queue.service: Deactivated successfully'")
        build.succeed("journalctl --grep 'Stopped nix-post-build-hook-queue'")
    '';
  }

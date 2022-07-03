{ config, lib, pkgs, ... }:


let
  cfg = config.services.nix-post-build-hook-queue;
in
{
  options.services.nix-post-build-hook-queue = with lib; {
    enable = lib.mkEnableOption "nix-post-build-hook-queue";

    package = mkOption {
      type = types.package;
      default = pkgs.nix;
      defaultText = literalExpression "pkgs.nix";
      description = ''
        The Nix package instance to use for the post-build actions.
      '';
    };

    signingPrivateKeyPath = mkOption {
      type = types.path;
      description = ''
        Path to the PEM encoded private key to sign store paths.
        Setting this enables signing.
      '';
    };

    uploadTo = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ssh://nix-ssh@nix-cache.example.com";
      description = ''
        Binary cache to upload store paths to after building.
      '';
    };

    sshPrivateKeyPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a private SSH key file.

        This is only relevant if
        <link linkend="opt-services.nix-post-build-hook-queue.uploadTo">uploadTo</link>
        is set to a binary cache served over SSH.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "nix-pb";
      description = ''
        User account under which the daemon runs.
      '';
    };

    group = mkOption {
      type = types.str;
      default = "nix-pb";
      description = ''
        Group under which the daemon runs.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/nix-post-build-hook-queue";
      description = ''
        Directory holding all state for nix-post-build-hook-queue to run.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    users = {
      users."${cfg.user}" = {
        inherit (cfg) group;
        description = "Nix post-build user";
        isSystemUser = true;
        createHome = true;
        home = "${cfg.stateDir}";
      };
      groups."${cfg.group}" = { };
    };

    nix.settings.trusted-users = [ cfg.user ];

    nix.extraOptions =
      let
        clientBin = "${pkgs.nix-post-build-hook-queue-client}/bin/nix-post-build-hook-queue-client";

        postBuildHook = pkgs.writeShellScriptBin "post-build-hook" ''
          set -f # disable globbing
          export IFS=' '

          ${clientBin} $OUT_PATHS || true
        '';
      in
      ''
        post-build-hook = ${postBuildHook}/bin/post-build-hook
      '';

    systemd.services.nix-post-build-hook-queue =
      let
        configFile = pkgs.writeText "nix-post-build-hook-queue-config.json" (builtins.toJSON {
          nix_bin = "${cfg.package}/bin/nix";
          key_path = "${cfg.signingPrivateKeyPath}";
          upload = cfg.uploadTo;
        });
        serverBin = "${pkgs.nix-post-build-hook-queue-server}/bin/nix-post-build-hook-queue-server";
      in
      {
        wantedBy = [ "multi-user.target" ];
        after = [ ] ++ lib.optional (cfg.uploadTo != null) "network.target";
        description = "nix-post-build-hook-queue";
        path = [ ] ++ lib.optional (cfg.uploadTo != null) pkgs.openssh;
        environment = {
          NIX_SSHOPTS = "-o IPQoS=throughput"
            + lib.optionalString (cfg.sshPrivateKeyPath != null) " -i ${cfg.sshPrivateKeyPath}";
        };

        serviceConfig = {
          Type = "idle";
          KillSignal = "SIGINT";
          ExecStart = "${serverBin} ${configFile}";
          Restart = "on-failure";
          RestartSec = 300;

          User = cfg.user;
          Group = cfg.group;

          # hardening
          DevicePolicy = "closed";
          CapabilityBoundingSet = "";
          RestrictAddressFamilies = [
            "AF_UNIX"
          ] ++ lib.optionals (cfg.uploadTo != null) [
            "AF_INET"
            "AF_INET6"
          ];
          DeviceAllow = [ ];
          NoNewPrivileges = true;
          PrivateDevices = true;
          PrivateMounts = true;
          PrivateTmp = true;
          PrivateUsers = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHome = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectSystem = "strict";
          BindPaths = [
            "${cfg.stateDir}"
          ];
          MemoryDenyWriteExecute = true;
          LockPersonality = true;
          RemoveIPC = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "~@debug"
            "~@mount"
            "~@privileged"
            "~@resources"
            "~@cpu-emulation"
            "~@obsolete"
          ];
          ProtectProc = "invisible";
          ProtectHostname = true;

          # permissive to prevent GC warnings
          # "GC Warning: Couldn't read /proc/stat"
          ProcSubset = "all";
        };
      };
  };
}

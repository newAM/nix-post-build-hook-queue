{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.nix-post-build-hook-queue;
in {
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
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to the PEM encoded private key to sign store paths.

        Paths will not be signed if null.
      '';
    };

    uploadTo = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ssh://nix-ssh@nix-cache.example.com";
      description = ''
        Binary cache to upload store paths to after building.

        Paths will not be uploaded if null.
      '';
    };

    sshPrivateKeyPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a private SSH key file.

        This is only relevant if
        <link linkend="opt-services.nix-post-build-hook-queue.uploadTo">uploadTo</link>
        is set to an SSH URL.
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
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !lib.isStorePath cfg.signingPrivateKeyPath;
        message = ''
          <option>services.nix-post-build-hook-queue.signingPrivateKeyPath</option>
          points to a file in the Nix store.
          You should use a quoted absolute path to prevent this.
        '';
      }
      {
        assertion = !lib.isStorePath cfg.sshPrivateKeyPath;
        message = ''
          <option>services.nix-post-build-hook-queue.sshPrivateKeyPath</option>
          points to a file in the Nix store.
          You should use a quoted absolute path to prevent this.
        '';
      }
    ];

    systemd.sockets.nix-post-build-hook-queue = {
      # NB: hard-coded in client
      listenDatagrams = ["/run/nix-post-build-hook-queue.sock"];
      wantedBy = ["sockets.target"];
      partOf = ["nix-post-build-hook-queue.service"];
      socketConfig = {
        SocketMode = "0600";
        SocketUser = cfg.user;
        SocketGroup = cfg.group;
        # start the service on incoming traffic
        Service = "nix-post-build-hook-queue.service";
      };
    };

    users = {
      users."${cfg.user}" = {
        inherit (cfg) group;
        description = "Nix post-build user";
        isSystemUser = true;
        shell = pkgs.bashInteractive;
      };
      groups."${cfg.group}" = {};
    };

    nix.settings = {
      trusted-users = [cfg.user];
      post-build-hook = "${pkgs.nix-post-build-hook-queue}/bin/post-build-hook";
    };

    systemd.services.nix-post-build-hook-queue = {
      after = lib.optionals (cfg.uploadTo != null) ["network.target"];
      description = "nix-post-build-hook-queue";
      path = [cfg.package] ++ lib.optionals (cfg.uploadTo != null) [pkgs.openssh];
      environment =
        {
          NIX_SSHOPTS =
            "-o IPQoS=throughput"
            + lib.optionalString (cfg.sshPrivateKeyPath != null) " -i ${cfg.sshPrivateKeyPath}";
        }
        // lib.optionalAttrs (cfg.signingPrivateKeyPath != null) {
          NPBHQ_SIGNING_PRIVATE_KEY_PATH = cfg.signingPrivateKeyPath;
        }
        // lib.optionalAttrs (cfg.uploadTo != null) {
          NPBHQ_UPLOAD_TO = cfg.uploadTo;
        };

      serviceConfig = {
        Type = "idle";
        KillSignal = "SIGINT";
        ExecStart = "${pkgs.nix-post-build-hook-queue}/bin/post-build-hook-queue";

        # disable rate limiting
        StartLimitIntervalSec = 0;

        User = cfg.user;
        Group = cfg.group;

        StandardInput = "socket";

        # hardening
        DevicePolicy = "closed";
        CapabilityBoundingSet = "";
        RestrictAddressFamilies =
          [
            "AF_UNIX"
          ]
          ++ lib.optionals (cfg.uploadTo != null) [
            "AF_INET"
            "AF_INET6"
          ];
        DeviceAllow = [];
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
        BindPaths = [];
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
        RemoveIPC = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        ProtectProc = "invisible";
        ProtectHostname = true;
        UMask = "0077";

        # permissive to prevent GC warnings
        # "GC Warning: Couldn't read /proc/stat"
        ProcSubset = "all";
      };
    };
  };
}

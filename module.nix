{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.virtualisation.nspawn-machines;
  name = config.networking.fqdnOrHostName;

  format = pkgs.formats.ini { listsAsDuplicateKeys = true; };
  settings = format.generate "${name}.nspawn" cfg.settings;

  system = "/nix/var/nix/profiles/system";

  systemd = pkgs.systemd.overrideAttrs (old: {
    patches = old.patches ++ [
      # https://github.com/systemd/systemd/pull/43731
      (pkgs.fetchpatch {
        url = "https://github.com/CathalMullan/systemd/commit/c044423910af1d95b242a697acd6b3eeb6f903f7.patch";
        hash = "sha256-xtSoirHMczkOfkE+dck2wX6M1RvZ71CgeYUC0PSGrkg=";
      })

      # https://github.com/systemd/systemd/pull/43739
      (pkgs.fetchpatch {
        url = "https://github.com/CathalMullan/systemd/commit/886dd44dabd6ad93999ec2943e7c3439132da581.patch";
        hash = "sha256-MTeHvlj8YWWfAbOpDDv7uayjFty7fC8oB6yqP97VyhM=";
      })
    ];
  });

  # nspawn requires a minimal directory tree to boot.
  tree = pkgs.runCommand "nspawn-${name}" { } ''
    mkdir -p $out/usr/lib $out/sbin

    # Needs to be copied directly, since it must exist prior to activation.
    cp ${config.environment.etc."os-release".source} $out/usr/lib/os-release

    ln -s ${system}/init $out/sbin/init
  '';

  runner = pkgs.writeShellApplication {
    name = "run-${config.networking.hostName}-nspawn-machine";

    runtimeInputs = with pkgs; [
      coreutils
      nix
      cfg.package
    ];

    text = ''
      if [ -n "''${STATE_DIRECTORY:-}" ]; then
        state="''${STATE_DIRECTORY%%:*}"
      else
        state="/var/lib/machines"
      fi

      # Use mstack to layer writes over the read-only tree.
      mkdir -p "$state/${name}.mstack/rw"
      ln -sfn ${tree} "$state/${name}.mstack/layer@store"
      ln -sfn ${settings} "$state/${name}.nspawn"

      # Ensure machine doesn't get GC'd while alive.
      nix-store \
        --add-root "$state/.${name}.gcroot" \
        --indirect \
        --realise \
        ${placeholder "out"} > /dev/null

      # Ideally we'd use `machinectl start` here instead.
      # But it runs from `/`, meaning any relative binds won't work.
      # https://github.com/systemd/systemd/blob/v261.2/units/systemd-nspawn@.service.in
      exec systemd-run \
        --unit=nspawn-machine-${config.networking.hostName} \
        --service-type=notify \
        --property=KillMode=mixed \
        --property=Delegate=yes \
        --property=DelegateSubgroup=supervisor \
        --property=SuccessExitStatus=133 \
        --property=TasksMax=16384 \
        --slice=machine.slice \
        --same-dir \
        --collect \
        -- \
        systemd-nspawn \
          --keep-unit \
          --mstack="$state/${name}.mstack" \
          --machine=${name} \
          --settings=trusted \
          "$@"
    '';
  };
in
{
  options.virtualisation.nspawn-machines = {
    package = lib.mkOption {
      type = lib.types.package;
      default = systemd;
    };

    settings = lib.mkOption {
      type = format.type;
      default = { };
    };
  };

  config = {
    boot.isContainer = lib.mkDefault true;
    system.build.nspawn-machine = runner;

    virtualisation.nspawn-machines.settings = {
      Exec = {
        Boot = lib.mkDefault true;
        NotifyReady = lib.mkDefault true;
        LinkJournal = lib.mkDefault "try-host";

        # Upstream warns this will be restricted in the future.
        # So might as well restrict by default now.
        # https://github.com/systemd/systemd/blob/v261.2/src/nspawn/nspawn.c#L6182-L6185
        RestrictAddressFamilies = lib.mkDefault [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"

          # For `networkd`
          # https://github.com/systemd/systemd/blob/v261.2/units/systemd-networkd.service.in#L43
          "AF_NETLINK"
          "AF_PACKET"
        ];
      };

      Files.BindReadOnly = [
        "/nix/store"
        "${config.system.build.toplevel}:${system}"
      ];
    };
  };
}

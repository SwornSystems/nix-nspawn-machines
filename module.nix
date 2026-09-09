{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.virtualisation.systemd-nspawn;
  name = config.system.name;

  format = pkgs.formats.ini { listsAsDuplicateKeys = true; };
  settings = format.generate "${name}.nspawn" cfg.settings;

  system = "/nix/var/nix/profiles/system";

  # nspawn requires a minimal directory tree to boot.
  # NOTE: Stored as a tarball to workaround initial image issues below.
  tree = pkgs.runCommand "nspawn-${name}.tar" { } ''
    mkdir -p tree/usr/lib tree/sbin

    # Needs to be copied directly, since it must exist prior to activation.
    cp ${config.environment.etc."os-release".source} tree/usr/lib/os-release

    ln -s ${system}/init tree/sbin/init

    # https://github.com/NixOS/nixpkgs/blob/d6524aaca2ff07876657ae2b323f24be4874944b/nixos/lib/make-system-tarball.sh#L44
    cd tree
    tar --sort=name --mtime='@1' --owner=0 --group=0 --numeric-owner -c . > $out
  '';

  runner = pkgs.writeShellApplication {
    name = "run-${name}-nspawn";

    runtimeInputs = with pkgs; [
      coreutils
    ];

    excludeShellChecks = [
      "SC2016"
    ];

    text = ''
      # Store image in the same location(s) as upstream.
      # https://github.com/systemd/systemd/blob/v261.2/src/shared/discover-image.c#L2511
      if [ -n "''${STATE_DIRECTORY:-}" ]; then
        state="''${STATE_DIRECTORY%%:*}"
      elif [ "$EUID" -ne 0 ]; then
        state="''${XDG_STATE_HOME:-$HOME/.local/state}/machines"
      else
        state="/var/lib/machines"
      fi

      ln -sfn ${settings} "$state/${name}.nspawn"

      # Manually setup initial image.
      # TODO: https://github.com/systemd/systemd/pull/35685#issuecomment-2557420827
      if [ "$EUID" -ne 0 ]; then
        scope=--user
      else
        scope=--system
      fi

      if [ ! -e "$state/${name}" ]; then
        import="$(systemd-path systemd-util)/systemd-import"
        "$import" "$scope" --image-root="$state" tar ${tree} ${name}
      fi

      # Ensure machine doesn't get GC'd while alive.
      nix-store \
        --add-root "$state/.${name}.gcroot" \
        --indirect \
        --realise \
        ${settings} > /dev/null

      exec systemd-nspawn \
        --directory="$state/${name}" \
        --machine=${name} \
        --settings=trusted \
        ${
          lib.escapeShellArgs (
            [ ]
            ++ lib.optional (cfg.register != null) "--register=${lib.boolToString cfg.register}"
            ++ lib.optional cfg.keepUnit "--keep-unit"
            ++ lib.mapAttrsToList (id: path: "--load-credential=${id}:${path}") cfg.loadCredential
            ++ lib.mapAttrsToList (id: value: "--set-credential=${id}:${value}") cfg.setCredential
            ++ lib.optional (cfg.forwardJournal != null) "--forward-journal=${cfg.forwardJournal}"
            ++ lib.optional (cfg.forwardJournalMaxUse != null) "--forward-journal-max-use=${cfg.forwardJournalMaxUse}"
            ++ lib.optional (cfg.slice != null) "--slice=${cfg.slice}"
            ++ map (property: "--property=${property}") cfg.property
            ++ lib.optional (cfg.selinuxContext != null) "--selinux-context=${cfg.selinuxContext}"
            ++ lib.optional (cfg.selinuxApifsContext != null) "--selinux-apifs-context=${cfg.selinuxApifsContext}"
            ++ map (group: "--bind-user-group=${group}") cfg.bindUserGroup
          )
        } \
        "$@"
    '';
  };
in
{
  # NOTE: Only options which don't have a settings field get a separate option.
  options.virtualisation.systemd-nspawn = {
    register = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
    };

    keepUnit = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    loadCredential = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };

    setCredential = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
    };

    forwardJournal = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    forwardJournalMaxUse = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    slice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    property = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    selinuxContext = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    selinuxApifsContext = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };

    bindUserGroup = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    settings = lib.mkOption {
      type = format.type;
      default = { };
    };
  };

  config = {
    boot.isContainer = lib.mkDefault true;
    system.build.nspawnRunner = runner;

    virtualisation.systemd-nspawn.settings = {
      Exec.Boot = lib.mkDefault true;
      Files.BindReadOnly = [
        "/nix/store"
        "${config.system.build.toplevel}:${system}"
      ];
    };
  };
}

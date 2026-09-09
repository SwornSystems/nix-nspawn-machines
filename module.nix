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

  # nspawn refuses to boot without a real directory tree.
  directory = pkgs.runCommand "nspawn-${name}" { } ''
    mkdir -p $out/root/usr/lib $out/root/sbin

    # Needs to be copied directly, since it must exist prior to activation.
    cp ${config.environment.etc."os-release".source} $out/root/usr/lib/os-release

    ln -s ${config.system.build.toplevel}/init $out/root/sbin/init
    cp ${settings} $out/${name}.nspawn
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

      # Sync latest image.
      mkdir -p "$state/${name}/usr/lib" "$state/${name}/sbin"
      ln -sfn ${directory}/${name}.nspawn "$state/${name}.nspawn"
      cp --no-preserve=mode ${directory}/root/usr/lib/os-release "$state/${name}/usr/lib/os-release"
      ln -sfn ${directory}/root/sbin/init "$state/${name}/sbin/init"

      # Ensure machine doesn't get GC'd while alive.
      nix-store \
        --add-root "$state/.${name}.gcroot" \
        --indirect \
        --realise \
        ${directory} > /dev/null

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
  };
}

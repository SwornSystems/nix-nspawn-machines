{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.virtualisation.systemd-nspawn;
  name = config.networking.fqdnOrHostName;

  format = pkgs.formats.ini { listsAsDuplicateKeys = true; };
  settings = format.generate "${name}.nspawn" cfg.settings;

  system = "/nix/var/nix/profiles/system";

  # nspawn requires a minimal directory tree to boot.
  tree = pkgs.runCommand "nspawn-${name}" { } ''
    mkdir -p $out/usr/lib $out/sbin

    # Needs to be copied directly, since it must exist prior to activation.
    cp ${config.environment.etc."os-release".source} $out/usr/lib/os-release

    ln -s ${system}/init $out/sbin/init
  '';

  runner = pkgs.writeShellApplication {
    name = "run-${name}-nspawn";

    runtimeInputs = with pkgs; [
      coreutils
    ];

    text = ''
      state="/var/lib/machines"

      if [ ! -e "$state/${name}" ]; then
        importctl --class=machine import-fs ${tree} ${name}
      fi

      mkdir -p /run/systemd/nspawn
      ln -sfn ${settings} "/run/systemd/nspawn/${name}.nspawn"

      # Ensure machine doesn't get GC'd while alive.
      nix-store \
        --add-root "$state/.${name}.gcroot" \
        --indirect \
        --realise \
        ${settings} > /dev/null

      exec machinectl start ${name}
    '';
  };
in
{
  options.virtualisation.systemd-nspawn = {
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

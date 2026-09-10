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
        --unit=machine-${name} \
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
    settings = lib.mkOption {
      type = format.type;
      default = { };
    };
  };

  config = {
    boot.isContainer = lib.mkDefault true;
    system.build.nspawn-machine = runner;

    virtualisation.nspawn-machines.settings = {
      Exec.Boot = lib.mkDefault true;
      Files.BindReadOnly = [
        "/nix/store"
        "${config.system.build.toplevel}:${system}"
      ];
    };
  };
}

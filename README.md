![license: MIT/Apache-2.0](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)
[![ci](https://github.com/SwornSystems/nix-nspawn-machines/actions/workflows/ci.yml/badge.svg)](https://github.com/SwornSystems/nix-nspawn-machines/actions/workflows/ci.yml)

# `nix-nspawn-machines`

Declarative NixOS machines on `systemd-nspawn`.

## Example

```nix
{
  inputs = {
    nspawn-machines = {
      url = "github:SwornSystems/nix-nspawn-machines";
    };
  };
}
```

```nix
nixpkgs.lib.nixosSystem {
  inherit system;

  modules = [
    nspawn-machines.nixosModules.default

    (
      {
        lib,
        pkgs,
        ...
      }:

      {
        networking = {
          hostName = "hello";
          domain = "example";
          firewall.allowedTCPPorts = [ 80 ];
        };

        virtualisation.nspawn-machines.settings = {
          Network.VirtualEthernet = true;
        };

        services.nginx = {
          enable = true;
          virtualHosts.default.root = pkgs.writeTextDir "index.html" "Hello world!";
        };

        system.stateVersion = lib.trivial.release;
      }
    )
  ];
}
```

```sh
> nix build .#nixosConfigurations.hello.config.system.build.nspawn-machine
> sudo ./result/bin/run-hello-nspawn-machine
Running as unit: nspawn-machine-hello.service; invocation ID: ...

> sudo machinectl list
MACHINE       CLASS     SERVICE        OS    VERSION ADDRESSES
hello.example container systemd-nspawn nixos ...     ...

1 machines listed.

> curl http://hello.example
Hello world!

> sudo journalctl --machine hello.example --unit nginx
... hello systemd[1]: Started Nginx Web Server.

> sudo machinectl stop hello.example
```

## Why

Upstream nixpkgs already ships [`nspawn-container`](https://github.com/NixOS/nixpkgs/tree/master/nixos/modules/virtualisation/nspawn-container) support, though
It's more focused on usage in NixOS integration tests rather than general use.

It makes certain environmental assumptions that this approach does not.
Our approach aims to be as minimal as possible, just a thin wrapper around `systemd.nspawn` files.

## Limitations

Many.

These are some I found trying to replace `Docker` and `QEMU` usages with `nspawn`.
When running as root, most things work fine.
Ideally, over time these issues resolve upstream, and rootless becomes usable.

### `systemd`

1. `rootidmap` mounts are unwritable when the user's UID and GID differ.
2. `mountfsd` reuses the UID map as the GID map.
3. `PrivateUsers=pick` defaults to `chown` ownership when set in a settings file, but `auto` on the CLI.
4. Rootless `Bind=` mounts cannot read the user's own files.
5. `Zone=` and `Bridge=` require root.
6. `nss-mymachines` only resolves root machines, not rootless ones.
7. `mountfsd` requires root to mount `/nix/store`, even though it's world-readable.

### `nixpkgs`

1. Firewall stops machines from getting a DHCP lease.
2. `systemd` package needs `vmlinux.h` for rootless machines.
3. `nsresourced`, `mountfsd`, and user `machined` units aren't installed.

## License

Licensed under the terms of both the [MIT License](LICENSE-MIT) and the [Apache License (Version 2.0)](LICENSE-APACHE).

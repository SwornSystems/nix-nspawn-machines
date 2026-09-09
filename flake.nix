{
  description = "nix-nspawn-machines";

  inputs = {
    nixpkgs = {
      url = "github:NixOS/nixpkgs/nixos-unstable";
    };
  };

  # nix flake show
  outputs =
    {
      self,
      nixpkgs,
      ...
    }:

    let
      perSystem = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;

      systemPkgs = perSystem (
        system:

        import nixpkgs {
          inherit system;

          overlays = [
            self.overlays.default
            (final: _prev: {
              # Markdown
              vale-styles = final.symlinkJoin {
                name = "vale-styles";
                paths = with final.valeStyles; [
                  proselint
                  write-good
                  redhat
                ];
              };
            })
          ];
        }
      );

      perSystemPkgs = f: perSystem (system: f (systemPkgs.${system}));
    in
    {
      overlays = {
        default = _final: _prev: { };
      };

      devShells = perSystemPkgs (pkgs: {
        # nix develop
        default = pkgs.mkShell {
          name = "nix-nspawn-machines-shell";

          env = {
            # Nix
            NIX_PATH = "nixpkgs=${nixpkgs.outPath}";

            # Vale
            VALE_STYLES_PATH = "${pkgs.vale-styles}/share/vale/styles";
          };

          buildInputs = with pkgs; [
            # Nix
            deadnix
            nil
            nixd
            nixfmt

            # Spellchecking
            typos
            typos-lsp

            # Markdown
            lychee
            vale
            vale-ls

            # TOML
            tombi

            # YAML
            yaml-language-server

            # JSON
            vscode-langservers-extracted

            # Nushell
            nushell
            nufmt
            nu-lint

            # Git
            committed

            # GitHub
            gh
            pinact
            zizmor
          ];
        };

        # nix develop .#ci
        ci = pkgs.mkShell {
          name = "nix-nspawn-machines-ci-shell";

          env = {
            # Vale
            VALE_STYLES_PATH = "${pkgs.vale-styles}/share/vale/styles";
          };

          buildInputs = with pkgs; [
            # Nix
            deadnix
            nixfmt

            # Spellchecking
            typos

            # Markdown
            lychee
            vale

            # TOML
            tombi

            # Nushell
            nushell
            nufmt
            nu-lint

            # Git
            committed

            # GitHub
            zizmor
          ];
        };
      });
    };
}

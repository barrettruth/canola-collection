{
  description = "canola-collection — optional adapters and extensions for canola.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      nixpkgs,
      systems,
      ...
    }:
    let
      forEachSystem =
        f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});
    in
    {
      formatter = forEachSystem (pkgs: pkgs.nixfmt-tree);

      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.prettier
            pkgs.stylua
            pkgs.selene
            pkgs.lua-language-server
            pkgs.vimdoc-language-server
            (pkgs.luajit.withPackages (ps: [
              ps.busted
              ps.nlua
            ]))
          ];
        };

        ci = pkgs.mkShell {
          packages = [
            pkgs.prettier
            pkgs.neovim
            pkgs.stylua
            pkgs.selene
            pkgs.lua-language-server
            pkgs.vimdoc-language-server
            (pkgs.luajit.withPackages (ps: [
              ps.busted
              ps.nlua
            ]))
          ];
        };
      });
    };
}

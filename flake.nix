{
  description = "Fivetrex — Elixir client library for the Fivetran REST API";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-utils.url = "github:numtide/flake-utils";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      nixpkgs,
      flake-utils,
      treefmt-nix,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Elixir 1.20 on the OTP 28 BEAM (matches CI's 1.20 / OTP 28 target).
        beam = pkgs.beam.packages.erlang_28;
        elixir_1_20 = beam.elixir_1_20;

        # treefmt config — one formatter per language. See formatters.md.
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.mix-format.enable = true; # Elixir (uses .formatter.exs)
          programs.prettier.enable = true; # Markdown / YAML / JSON
        };
      in
      {
        devShells.default = pkgs.mkShell {
          # Toolchains for the detected languages + shared dev tools.
          packages = [
            pkgs.lefthook
            elixir_1_20 # Elixir 1.20 + Mix
            beam.erlang # OTP 28 (BEAM runtime)
          ];
        };

        # `nix fmt` runs treefmt across the repo.
        formatter = treefmtEval.config.build.wrapper;

        # `nix flake check` verifies everything is formatted.
        checks.formatting = treefmtEval.config.build.check ./.;
      }
    );
}

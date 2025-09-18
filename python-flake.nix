{
  description = "A high-performance Python 3.13 development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # --- Overlays ---
        # Overlays are a way to modify the final Nix package set (pkgs).
        # We use an overlay here to replace the default Python 3.13 with our
        # own customized, performance-optimized version.
        overlays = [
          (final: prev: {
            # This overlay targets the 'python313' package.
            python313 = prev.python313.override {
              enableOptimizations = true;
              enableLTO = true;
            };
          })
        ];

        # --- Package Set ---
        # Import nixpkgs for the specific system, applying our overlays.
        # Now, whenever we reference 'pkgs.python313', it will refer to our
        # optimized version, not the default one.
        pkgs = import nixpkgs {
          inherit system;
          inherit overlays;
        };

        # --- Python Packages ---
        # Define the list of Python packages for the environment.
        # CRITICAL: We use 'pkgs.python313Packages' here. Because 'pkgs' has
        # our overlay applied, 'python313Packages' is now the package set
        # corresponding to our *optimized* Python interpreter. This ensures
        # all Python libraries are built correctly against it.
        pythonLibs = with pkgs.python313Packages; [
          # Essential development tools
          pip
          virtualenv

          # Jupyter environment for interactive notebooks
          jupyter

          # Common data science libraries
          pandas
          numpy
        ];

      in
      {
        # --- Development Shell ---
        # The 'devShell' is the main development environment that `nix develop`
        # or `direnv` will activate.
        devShells.default = pkgs.mkShell {
          # The buildInputs are the packages made available in the shell's PATH.
          buildInputs = [
            # Add our optimized Python interpreter to the shell.
            pkgs.python313
          ]
          ++ pythonLibs; # Add all the Python libraries.

          # A shell hook is a command that runs when you enter the environment.
          shellHook = ''
            echo "Entering python shell"
          '';
        };
      }
    );
}

# /flake.nix
{
  description = "A high-performance Python development environment with Jupyter";

  # Define the inputs for our flake.
  # 'nixpkgs' points to the unstable channel for the latest packages.
  # 'flake-utils' is a helper library to easily support multiple systems.
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  # Define the outputs of our flake.
  # We use flake-utils to generate outputs for each supported system.
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        # Create an overlay to apply our custom configurations to nixpkgs.
        # Overlays are a way to modify the package set.
        overlays = [
          (final: prev: {
            # This overlay customizes the Python 3.11 package set.
            python311 = prev.python311.override {
              # Enable non-reproducible, performance-oriented compiler optimizations.
              # This can result in faster code at the cost of determinism.
              enableOptimizations = true;
              # Enable Link-Time Optimization (LTO), which can further improve performance.
              enableLTO = true;
            };
          })
        ];

        # Import nixpkgs for the specific system, applying our overlays.
        pkgs = import nixpkgs {
          inherit system;
          inherit overlays;
        };

        # Define the list of Python packages needed for the environment.
        # These will be built using the optimized Python interpreter.
        pythonPackages = with pkgs.python311Packages; [
          # Essential development tools
          pip
          virtualenv

          # Jupyter environment for notebooks
          jupyter

          # Common data science libraries
          pandas
          numpy
        ];

      in
      {
        # The 'devShell' is the main development environment.
        # It's what `nix develop` or `direnv` will activate.
        devShells.default = pkgs.mkShell {
          # The buildInputs are the packages available in the shell.
          buildInputs = [
            # The optimized Python interpreter
            pkgs.python311
          ] ++ pythonPackages;

          # Shell hook to provide a welcome message upon entering the environment.
          shellHook = ''
            echo "🐍 Python 3.11 High-Performance Environment (with LTO) is active."
            echo "🐍 Jupyter and other tools are available in your PATH."
          '';
        };

        # A formatter to ensure consistent code style for .nix files.
        # Run with `nix fmt`.
        formatters.default = pkgs.nixpkgs-fmt;
      });
}

{
  description = "A reproducible and high-performance Python 3.13 development environment.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    # The `eachDefaultSystem` function from `flake-utils` generates an attribute set
    # for each of the default systems (x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin).
    # This avoids hardcoding system architectures and makes the flake more portable.
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        # 1. Define Overlays for Customizing Packages:
        # Overlays are the idiomatic way to modify the nixpkgs package set.
        # Here, we create an overlay to build a performance-optimized Python interpreter.
        overlays = [
          (final: prev: {
            optimizedPython = prev.python313.override {
              enableOptimizations = true;
              enableLTO = true; # Enable Link Time Optimization
            };
          })
        ];

        # 2. Instantiate nixpkgs for the Current System with Overlays:
        # We import nixpkgs for the specific system, applying our custom overlays.
        # This makes `pkgs.optimizedPython` available.
        pkgs = import nixpkgs {
          inherit system;
          inherit overlays;
        };

        # 3. Define Python Packages:
        # A list of Python packages to be included in the development environment.
        # Managing this list separately improves readability and maintainability.
        pythonPackages =
          python-pkgs: with python-pkgs; [
            ruff
            mypy
            pandas
            numpy
            scipy
            requests
            debugpy
          ];

        # 4. Create the Python Environment:
        # Use `withPackages` on our optimized Python to create a consistent environment
        # for both development and any potential packaging tasks.
        pythonEnv = pkgs.optimizedPython.withPackages pythonPackages;

        # 5. Define Non-Python Development Tools:
        # A list of essential development tools that are not Python packages.
        devTools = with pkgs; [
          # Language Server Protocol for Python
          basedpyright
        ];

      in
      {
        # 6. Define the Development Shell:
        # The `devShells.default` output is the entry point for `nix develop`.
        devShells.default = pkgs.mkShell {
          # The `packages` attribute is the modern and preferred way over `buildInputs`.
          packages = [
            pythonEnv
          ]
          ++ devTools;

          # The shellHook provides useful feedback to the user upon entering the environment.
          shellHook = ''
            echo "
            Entering optimized Python 3.13 development environment.
            Interpreter: $(which python)
            Version:     $(python --version)
            "
          '';
        };
      }
    );
}

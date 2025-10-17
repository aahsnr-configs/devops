{
  description = "A Python environment with targeted x86-64-v3 optimizations, built with GCC15";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        lib = nixpkgs.lib;
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        optimizedPkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            (final: prev:
              lib.optionalAttrs (prev.stdenv.hostPlatform.system == "x86_64-linux") {
                bootstrapTools = prev.bootstrapTools.overrideAttrs (old: {
                  NIX_CFLAGS_COMPILE = "-march=x86-64-v3 -flto=auto -fprofile-use";
                });
              })
          ];
        };

        # --- Component Definitions ---

        pythonOptimized = (optimizedPkgs.python313.overrideAttrs (oldAttrs: {
          hardeningDisable = [ "all" ];
        })).override {
          stdenv = optimizedPkgs.overrideCC optimizedPkgs.stdenv optimizedPkgs.gcc15;

          enableOptimizations = true; # PGO
          enableLTO = true;
          reproducibleBuild = false;
        };

        pythonPackages = with pythonOptimized.pkgs; [
          pytorch torchvision torchaudio
          jupyterlab notebook ipykernel ipywidgets
          numpy scipy pandas scikit-learn matplotlib seaborn
          debugpy
        ];

        pythonDevTools = with optimizedPkgs; [
          ruff mypy basedpyright
        ];

        devTools = with pkgs; [
          gcc15
          cmake
          ninja
          pkg-config
          gnumake
        ];

      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs =
            devTools           # Standard tools (including gcc15)
            ++ pythonDevTools  # Optimized tools
            ++ pythonPackages  # Optimized libraries
            ++ [ pythonOptimized ]; # The PGO-optimized interpreter

          shellHook = ''
            echo "====================================================="
            echo "  Deep Learning Shell (GCC15, Max Opts, x86-64-v3)"
            echo "====================================================="
            echo "✓ Python:   $(python --version) (PGO, LTO, No Hardening)"
            echo "✓ GCC:      $(gcc --version | head -n 1)"
            echo "✓ PyTorch:  $(python -c 'import torch; print(torch.__version__)' 2/dev/null || echo 'Not found')"
            echo "✓ Tools:    Ruff, MyPy, Basedpyright, Jupyter"
            echo "====================================================="
          '';
        };

        packages = {
          default = pythonOptimized.withPackages (ps: pythonPackages);
          python = pythonOptimized;
        };

        formatter = pkgs.nixpkgs-fmt;
      }
    );
}

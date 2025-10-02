{
  description = "A reproducible, multi-environment hub for high-performance development.";

  inputs = {
    nixpkgs.url = "github.com/NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github.com/hercules-ci/flake-parts";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-parts,
    }:
    flake-parts.lib.mkFlake { inherit self; } {
      # 1. Define the systems to support.
      systems = [ "x86_64-linux" ]; # CUDA support is primarily available on x86_64-linux

      # 2. Use `perSystem` to define system-specific outputs like dev shells and overlays.
      perSystem =
        {
          config,
          self',
          pkgs,
          ...
        }:
        let
          # Define an overlay to build the optimized Python interpreter using Clang/LLVM.
          # This overlay is now scoped within the perSystem context.
          clang-build-python-overlay = final: prev: {
            python313 = prev.python313.override {
              # Use the Clang standard environment to compile CPython itself.
              stdenv = prev.clangStdenv;
              # Enable Profile Guided Optimization (PGO) and Link Time Optimization (LTO).
              enableOptimizations = true;
              enableLTO = true;
            };
          };

          # --- Package Set Definitions ---
          # Create a standard package set that includes our Clang-built Python.
          pkgsStd = import nixpkgs {
            inherit (pkgs) system;
            overlays = [ clang-build-python-overlay ]; # Use the locally defined overlay
            config.allowUnfree = false;
          };

          # Create a specialized package set for GPU tasks.
          # Removed `cudaSupport = true;` from config as it's not a direct option.
          # CUDA support is achieved by including `cudatoolkit` and other GPU packages in buildInputs.
          pkgsGpu = import nixpkgs {
            inherit (pkgs) system;
            overlays = [ clang-build-python-overlay ]; # Use the locally defined overlay
            config = {
              allowUnfree = true; # Required for NVIDIA's drivers and libraries
            };
          };

          # --- Common Package Group Definitions ---
          # Base Python environment with the Clang-built interpreter.
          optimizedPythonEnv = pkgsStd.python313.withPackages (
            ps: with ps; [
              pandas
              numpy
              debugpy
            ]
          );

          # Standalone tools for Python development.
          pythonDevelopmentTools = with pkgsStd; [
            pyright
            ruff
            black
          ];

          # Common tools for C/C++ development.
          commonCppTools = with pkgsStd; [
            clang-tools
            llvm
            lldb
            cmake
          ];

        in
        {
          # 3. Define the collection of specialized development shells.
          devShells = {
            # --- Default Python Shell ---
            default = pkgsStd.mkShell {
              name = "python-dev";
              buildInputs = [ optimizedPythonEnv ] ++ pythonDevelopmentTools;
              shellHook = ''echo "Optimized Python (Clang build) environment loaded: $(python --version) at $(which python)"'';
            };

            # --- General C/C++ Shell ---
            cpp = pkgsStd.mkShell {
              name = "cpp-dev";
              buildInputs = commonCppTools;
              shellHook = ''echo "C/C++ (Clang/LLVM) environment loaded: $(clang --version | head -n 1)"'';
            };

            # --- CUDA C++ Shell ---
            cuda = pkgsGpu.mkShell {
              name = "cuda-cpp-dev";
              buildInputs = commonCppTools ++ [ pkgsGpu.cudatoolkit ];
              shellHook = ''echo "CUDA C/C++ environment loaded. NVCC version: $(nvcc --version | grep 'release')" '';
            };

            # --- Deep Learning Shell (Python + GPU) ---
            deep-learning = pkgsGpu.mkShell {
              name = "deep-learning-dev";
              buildInputs = [
                (pkgsGpu.python313.withPackages (
                  ps: with ps; [
                    pytorchWithCuda
                    tensorflowWithCuda
                    debugpy
                  ]
                ))
              ]
              ++ pythonDevelopmentTools
              ++ (with pkgsGpu; [
                cudatoolkit
                cudnn
                nccl
              ]);
              shellHook = ''
                echo "Deep Learning (Python + CUDA) environment loaded: $(python --version)"
                echo "Ensure your host has the correct NVIDIA driver installed."
              '';
            };

            # --- Unified 'all' Shell ---
            all = pkgsGpu.mkShell {
              name = "all-tools-dev";
              buildInputs =
                let
                  unifiedPythonEnv = pkgsGpu.python313.withPackages (
                    ps: with ps; [
                      pandas
                      numpy
                      pytorchWithCuda
                      tensorflowWithCuda
                      debugpy
                    ]
                  );
                in
                [ unifiedPythonEnv ]
                ++ pythonDevelopmentTools
                ++ commonCppTools
                ++ (with pkgsGpu; [
                  cudatoolkit
                  cudnn
                  nccl
                ]);
              shellHook = ''
                echo "Unified environment loaded. Includes Python, C/C++, CUDA, and ML tools."
                echo "Python: $(python --version)"
                echo "Clang:  $(clang --version | head -n 1)"
                echo "NVCC:   $(nvcc --version | grep 'release' || echo 'Not found')"
              '';
            };
          };
        };
    };
}

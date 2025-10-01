Of course. Here is the complete, unified guide containing the final `flake.nix` and `.envrc` files, along with all the necessary instructions and explanations from our previous conversations.

---

## Unified Guide: A Multi-Environment Nix Setup for High-Performance Development

This guide provides a complete, scalable, and reproducible development setup using Nix Flakes. It is designed for complex projects that require different toolchains, such as high-performance Python, C/C++, CUDA, and GPU-accelerated Deep Learning.

The setup is composed of three key parts:

1.  **The `flake.nix` File:** The heart of the system, defining all the development environments. It uses the `flake-parts` framework for modularity and scalability.
2.  **The `.envrc` File:** The entry point for `direnv`, allowing for automatic and conditional loading of the desired environment.
3.  **The Workflow:** A simple, user-friendly process for selecting and switching between environments.

---

### **Part 1: The `flake.nix` File**

This file defines a collection of distinct development shells, including a unified "all" shell that combines every tool. The core Python environment is custom-built with the Clang/LLVM toolchain for optimized performance.

**`flake.nix`**

```nix
{
  description = "A reproducible, multi-environment hub for high-performance development.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = { self, nixpkgs, flake-parts }:
    flake-parts.lib.mkFlake { inherit self; } {
      # 1. Define the systems to support.
      systems = [ "x86_64-linux" ]; # CUDA support is primarily available on x86_64-linux

      # 2. Define outputs that are shared across all systems, like our custom overlay.
      outputs = {
        # Define an overlay to build the optimized Python interpreter using Clang/LLVM.
        clang-build-python-overlay = final: prev: {
          python313 = prev.python313.override {
            # Use the Clang standard environment to compile CPython itself.
            stdenv = prev.clangStdenv;
            # Enable Profile Guided Optimization (PGO) and Link Time Optimization (LTO).
            enableOptimizations = true;
            enableLTO = true;
          };
        };
      };

      # 3. Use `perSystem` to define system-specific outputs like dev shells.
      perSystem = { config, self', pkgs, ... }:
        let
          # --- Package Set Definitions ---
          # Create a standard package set that includes our Clang-built Python.
          pkgsStd = import nixpkgs {
            inherit (pkgs) system;
            overlays = [ self.outputs.clang-build-python-overlay ];
            config.allowUnfree = false;
          };

          # Create a specialized package set for GPU tasks.
          pkgsGpu = import nixpkgs {
            inherit (pkgs) system;
            overlays = [ self.outputs.clang-build-python-overlay ];
            config = {
              allowUnfree = true; # Required for NVIDIA's drivers and libraries
              cudaSupport = true;
            };
          };

          # --- Common Package Group Definitions ---
          # Base Python environment with the Clang-built interpreter.
          optimizedPythonEnv = pkgsStd.python313.withPackages (ps: with ps; [
            pandas
            numpy
            debugpy
          ]);

          # Standalone tools for Python development.
          pythonDevelopmentTools = with pkgsStd; [ pyright ruff black ];

          # Common tools for C/C++ development.
          commonCppTools = with pkgsStd; [ clang-tools llvm lldb cmake ];

        in
        {
          # 4. Define the collection of specialized development shells.
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
                (pkgsGpu.python313.withPackages (ps: with ps; [ pytorchWithCuda tensorflowWithCuda debugpy ]))
              ] ++ pythonDevelopmentTools ++ (with pkgsGpu; [ cudatoolkit cudnn nccl ]);
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
                  unifiedPythonEnv = pkgsGpu.python313.withPackages (ps: with ps; [
                    pandas numpy pytorchWithCuda tensorflowWithCuda debugpy
                  ]);
                in
                [ unifiedPythonEnv ] ++ pythonDevelopmentTools ++ commonCppTools ++ (with pkgsGpu; [ cudatoolkit cudnn nccl ]);
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
```

---

### **Part 2: The `direnv` and `.envrc` Setup**

This setup provides the automation layer. The `.envrc` file is committed to your project, while a local `.envrc.local` file allows each user to choose their preferred environment without creating version control conflicts.

**`.envrc`**

```bash
# .envrc

# This file enables conditional loading of Nix flake environments using direnv.
# It checks for a DEV_ENV variable to select the appropriate devShell.

# 1. Check for a local, untracked .envrc.local file and load it if it exists.
#    This is where you will set your personal DEV_ENV preference.
if [ -f .envrc.local ]; then
  source_env .envrc.local
fi

# 2. Set a default environment if DEV_ENV is not defined.
#    You can set this to "all" or "python" depending on your preference.
: ${DEV_ENV:=python}

# 3. Use a case statement to select and load the correct flake attribute.
#    This calls `nix-direnv` to build and activate the chosen shell.
log_status "Loading Flake environment: $DEV_ENV"
case "$DEV_ENV" in
  "python")
    use flake .
    ;;
  "cpp")
    use flake .#cpp
    ;;
  "cuda")
    use flake .#cuda
    ;;
  "deep-learning")
    use flake .#deep-learning
    ;;
  "all")
    # This option loads the combined 'all' shell from the flake.
    use flake .#all
    ;;
  *)
    log_error "Unknown DEV_ENV '$DEV_ENV'. Falling back to the default Python environment."
    use flake .
    ;;
esac
```

---

### **Part 3: The Complete User Workflow**

Follow these steps to get the entire system running in your project.

**Step 1: Save the Files**

- Save the code from Part 1 as `flake.nix` in your project's root directory.
- Save the code from Part 2 as `.envrc` in the same directory.

**Step 2: Configure Version Control**

- It is crucial to prevent personal configuration from being committed. Add the following lines to your `.gitignore` file:

  ```gitignore
  # .gitignore

  # Ignore local direnv configuration
  .envrc.local

  # Ignore direnv state directory
  .direnv/
  ```

**Step 3: Choose Your Environment**

- Create a file named `.envrc.local` in your project root. This file is **not** committed to Git.
- In this file, specify which development shell you want to use.
  - **Example 1: Select the `deep-learning` shell**

    ```bash
    # in .envrc.local
    export DEV_ENV="deep-learning"
    ```

  - **Example 2: Select the unified `all` shell**
    ```bash
    # in .envrc.local
    export DEV_ENV="all"
    ```

**Step 4: Activate the Environment**

- Open your terminal in the project directory. `direnv` will detect the new files and show a security warning.
- Run the following command to approve and activate the setup:

  ```bash
  direnv allow
  ```

- `nix-direnv` will now read the `DEV_ENV` variable and build the corresponding environment. This may take some time on the first run as it compiles the optimized Python and downloads all necessary tools.

**Step 5: Switching Environments**

- To switch to a different toolset, simply edit the `DEV_ENV` variable in your `.envrc.local` file.
- For instance, to switch from "deep-learning" to "cpp", change your `.envrc.local` to:
  ```bash
  # in .envrc.local
  export DEV_ENV="cpp"
  ```
- `direnv` will automatically detect the change and reload your shell with the new set of tools, providing a seamless transition between complex development environments.

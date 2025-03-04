{
  description = "The EZA flake for developing and releasing (soon)";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    naersk.url = "github:nix-community/naersk";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = {
    self,
    flake-utils,
    naersk,
    nixpkgs,
    treefmt-nix,
    rust-overlay,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        overlays = [(import rust-overlay)];

        pkgs = (import nixpkgs) {
          inherit system overlays;
        };

        toolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        naersk' = pkgs.callPackage naersk {
          cargo = toolchain;
          rustc = toolchain;
          clippy = toolchain;
        };

        treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;
        buildInputs = with pkgs; lib.optionals stdenv.isDarwin [libiconv darwin.apple_sdk.frameworks.Security];
      in rec {
        # For `nix fmt`
        formatter = treefmtEval.config.build.wrapper;

        packages = {
          # For `nix build` `nix run`, & `nix profile install`:
          default = naersk'.buildPackage {
            pname = "eza";
            version = "latest";

            src = ./.;
            doCheck = true; # run `cargo test` on build

            # buildInputs = with pkgs; [ zlib ]
            #   ++ lib.optionals stdenv.isDarwin [ libiconv Security ];
            buildInputs = buildInputs ++ (with pkgs; [zlib]);

            nativeBuildInputs = with pkgs; [cmake pkg-config installShellFiles pandoc];

            buildNoDefaultFeatures = true;
            # buildFeatures = lib.optional gitSupport "git";
            buildFeatures = "git";

            # outputs = [ "out" "man" ];

            postInstall = ''
              pandoc --standalone -f markdown -t man man/eza.1.md > man/eza.1
              pandoc --standalone -f markdown -t man man/eza_colors.5.md > man/eza_colors.5
              pandoc --standalone -f markdown -t man man/eza_colors-explanation.5.md > man/eza_colors-explanation.5
              installManPage man/eza.1 man/eza_colors.5 man/eza_colors-explanation.5
              installShellCompletion \
                --bash completions/bash/eza \
                --fish completions/fish/eza.fish \
                --zsh completions/zsh/_eza
            '';

            meta = with pkgs.lib; {
              description = "A modern, maintained replacement for ls";
              longDescription = ''
                eza is a modern replacement for ls. It uses colours for information by
                default, helping you distinguish between many types of files, such as
                whether you are the owner, or in the owning group. It also has extra
                features not present in the original ls, such as viewing the Git status
                for a directory, or recursing into directories with a tree view. eza is
                written in Rust, so it’s small, fast, and portable.
              '';
              homepage = "https://github.com/eza-community/eza";
              license = licenses.mit;
              mainProgram = "eza";
              maintainers = with maintainers; [cafkafk];
            };
          };

          # Run `nix build .#check` to check code
          check = naersk'.buildPackage {
            src = ./.;
            mode = "check";
            inherit buildInputs;
          };

          # Run `nix build .#test` to run tests
          test = naersk'.buildPackage {
            src = ./.;
            mode = "test";
            inherit buildInputs;
          };

          # Run `nix build .#clippy` to lint code
          clippy = naersk'.buildPackage {
            src = ./.;
            mode = "clippy";
            inherit buildInputs;
          };

          vhs = pkgs.buildGoModule rec {
            pname = "vhs";
            version = "0.6.0";

            src = pkgs.fetchFromGitHub {
              owner = "PThorpe92";
              repo = pname;
              rev = "70ff84c3b192a2f3379adf56dd873c63bc8163ac";
              hash = "sha256-QgE9XpJKZSJDjY2Z2GC1ndWgwXOJaB1fzvGUGFFf5XM=";
            };

            vendorHash = "sha256-zugGnhLrqqqVjMFZrO4rrSj3UzyHWpLra1rxyGG2ga4=";

            nativeBuildInputs = with pkgs; [installShellFiles makeWrapper];

            ldflags = ["-s" "-w" "-X=main.Version=${version}"];

            postInstall = ''
              wrapProgram $out/bin/vhs --prefix PATH : ${pkgs.lib.makeBinPath (pkgs.lib.optionals pkgs.stdenv.isLinux [pkgs.chromium] ++ [pkgs.ffmpeg pkgs.ttyd])}
              $out/bin/vhs man > vhs.1
              installManPage vhs.1
              installShellCompletion --cmd vhs \
                --bash <($out/bin/vhs completion bash) \
                --fish <($out/bin/vhs completion fish) \
                --zsh <($out/bin/vhs completion zsh)
            '';

            meta = with pkgs.lib; {
              description = "A tool for generating terminal GIFs with code";
              homepage = "https://github.com/charmbracelet/vhs";
              changelog = "https://github.com/charmbracelet/vhs/releases/tag/v${version}";
              license = licenses.mit;
              maintainers = with maintainers; [cafkafk];
            };
          };
        };

        # For `nix develop`:
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [toolchain just pandoc packages.vhs convco];
        };

        # For `nix flake check`
        checks = {
          formatting = treefmtEval.config.build.check self;
          build = packages.check;
          test = packages.test;
          lint = packages.clippy;
        };
      }
    );
}

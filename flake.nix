{
  description = "Build a cargo project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    crane = {
      url = "github:ipetkov/crane";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, crane, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        craneLib = crane.lib.${system};
        src = ./.;

        openssl-sysNativeDeps = {
          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ pkgs.openssl.dev ];
        };

        # Build *just* the cargo dependencies, so we can reuse
        # all of that work (e.g. via cachix) when running in CI
        cargoArtifacts = craneLib.buildDepsOnly ({
          inherit src;
        } // openssl-sysNativeDeps);

        # Build the actual crate itself, reusing the dependency
        # artifacts from above.
        recaphub = craneLib.buildPackage ({
          inherit cargoArtifacts src;
        } // openssl-sysNativeDeps);
      in
      {
        checks = {
          # Build the crate as part of `nix flake check` for convenience
          inherit recaphub;

          # Run clippy (and deny all warnings) on the crate source,
          # again, resuing the dependency artifacts from above.
          #
          # Note that this is done as a separate derivation so that
          # we can block the CI if there are issues here, but not
          # prevent downstream consumers from building our crate by itself.
          recaphub-clippy = craneLib.cargoClippy {
            inherit cargoArtifacts src;
            cargoClippyExtraArgs = "-- --deny warnings";
          };

          # Check formatting
          recaphub-fmt = craneLib.cargoFmt {
            inherit src;
          };

          # Check code coverage (note: this will not upload coverage anywhere)
          recaphub-coverage = craneLib.cargoTarpaulin {
            inherit cargoArtifacts src;
          };
        };

        defaultPackage = recaphub;
        packages.recaphub = recaphub;

        apps.my-app = flake-utils.lib.mkApp {
          drv = recaphub;
        };
        defaultApp = self.apps.${system}.my-app;

        devShell = pkgs.mkShell {
          inputsFrom = builtins.attrValues self.checks 
            ++ [ cargoArtifacts recaphub ];

          # Extra inputs can be added here
          nativeBuildInputs = with pkgs; [
            cargo
            rustc
          ];
        };
      });
}

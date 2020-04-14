{
sources ? import ../sources.nix;

# PKGS

pkgs ? import sources.nixpkgs { },

dhall-json ? pkgs.dhall-json,

nodejs ? pkgs.nodejs,

yarn ? pkgs.yarn,

nixfmt ? pkgs.nixfmt,

nix-prefetch-git ? pkgs.nix-prefetch-git,

jq ? pkgs.jq,

# EASY PURESCRIPT

easy-purescript-nix ? import sources.easy-purescript-nix { },

spago2nix ? easy-purescript-nix.spago2nix,

purs ? easy-purescript-nix.purs,

# YARN2NIX

yarn2nix ? import sources.yarn2nix { }

}:
let

  yarnPackage = yarn2nix.mkYarnPackage {
    src = pkgs.runCommand "src" { } ''
      mkdir $out

      ln -s ${./package.json} $out/package.json
      ln -s ${./yarn.lock} $out/yarn.lock
    '';

    publishBinsFor = [ "purescript-psa" "parcel" ];
  };

  spago2nix-ree = pkgs.stdenv.mkDerivation {

    name = "spago2nix-ree";

    version = "v0.1.1";

    phases = [
      "preBuildPhase"
      "buildPhase"
      "checkPhase"
      "installPhase"
      "fixupPhase"
      "installCheckPhase"
    ];

    buildInputs = [ yarnPackage purs nodejs yarn pkgs.makeWrapper ];

    doCheck = true;

    doInstallCheck = true;

    src = pkgs.runCommand "src" { } ''
      mkdir $out

      ln -s ${./Makefile} $out/Makefile
      ln -s ${./src} $out/src
      ln -s ${./test} $out/test
    '';

    preBuildPhase = ''
      TMP=`mktemp -d`
      cd $TMP

      ln -s $src/* -t .
      bash ${(pkgs.callPackage ./spago-packages.nix { }).installSpagoStyle}
    '';

    installPhase = ''
      mkdir $out
      cp -r $TMP/dist/* -t $out 
    '';

  };

in pkgs.writeShellScriptBin "spago2nix-ree" ''
  PURE=true
  DHALL_TO_JSON=${dhall-json}/bin/dhall-to-json
  NIX_PREFETCH_GIT=${nix-prefetch-git}/bin/nix-prefetch-git

  ${spago2nix-ree}/bin/spago2nix-ree $@
''
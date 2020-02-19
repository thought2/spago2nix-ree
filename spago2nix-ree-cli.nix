let sources = import ./nix/sources.nix;

in {
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

in pkgs.stdenv.mkDerivation {
  name = "spago2nix-ree";

  phases = [
    "preBuildPhase"
    "buildPhase"
    "checkPhase"
    "installPhase"
    "preFixupPhase"
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

  preFixupPhase = ''
    mv $out/bin/spago2nix-ree $out/bin/spago2nix-ree-unpure

    makeWrapper $out/bin/spago2nix-ree-unpure $out/bin/spago2nix-ree \
      --set PURE true \
      --set DHALL_TO_JSON ${dhall-json}/bin/dhall-to-json \
      --set NIX_PREFETCH_GIT ${nix-prefetch-git}/bin/nix-prefetch-git
  '';

}
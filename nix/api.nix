{ sources ? import ./sources.nix,

# PKGS

pkgs ? import sources.nixpkgs { },

dhall-json ? pkgs.dhall-json

}:
with builtins;
with pkgs.lib;
let
  buildPackage = import ./build-package.nix { inherit sources; };
  util = import ./util.nix { inherit pkgs; };

in rec {

  getPackages = { packagesLock, localSrcDirs }:

    util.resolvePackages {
      packagesLock = util.getPackagesConfig packagesLock;
      inherit localSrcDirs;
    };

  buildProjectDependencies = {

    spagoPackages,

    configFiles,

    packagesLock,

    spagoDhall ? util.defaultSpagoDhall

    }:

    let
      spagoConfig = util.getSpagoConfig configFiles spagoDhall;

      buildPackageConfig = {

        inherit spagoPackages;

        package = rec {
          name = spagoConfig.name + "-dependencies";
          dependencies = spagoConfig.dependencies;
          version = "no-version";
          source = pkgs.runCommand "${name}-source" { } "mkdir $out";
        };

        packagesLock = util.getPackagesConfig packagesLock;

      };

    in buildPackage.buildPackage buildPackageConfig;

  buildProject = {

    spagoPackages,

    srcDirs,

    configFiles,

    packagesLock,

    spagoDhall ? util.defaultSpagoDhall

    }:

    let
      spagoConfig = util.getSpagoConfig configFiles spagoDhall;

      projectSources = util.createFiles srcDirs;

      projectDepenedencies = buildProjectDependencies {
        inherit spagoPackages;
        inherit configFiles;
        inherit spagoDhall;
        inherit packagesLock;
      };

      compileSpagoProjectConfig = {
        inherit projectDepenedencies;
        inherit projectSources;
      };

    in util.compileSpagoProject compileSpagoProjectConfig;

  buildCLI = {

    spagoPackages,

    name ? let

      spagoConfig = util.getSpagoConfig configFiles spagoDhall;
    in spagoConfig.name,

    srcDirs,

    configFiles,

    packagesLock,

    spagoDhall ? util.defaultSpagoDhall,

    entryModule ? util.defaultEntry,

    node_modules ? util.emptyDir }:

    let

      project = buildProject {
        inherit spagoPackages;
        inherit srcDirs;
        inherit configFiles;
        inherit packagesLock;
        inherit spagoDhall;
      };

      buildParcelConfigNode = {
        src = util.createFiles {
          "." = project + "/*";
          "index.js" = util.defaultEntryJS { inherit entryModule; };
        };
        entry = "index.js";
        inherit node_modules;
      };

    in pipe buildParcelConfigNode [
      util.buildParcelNode
      (src:
        util.createNodeBinary {
          inherit src;
          inherit name;
        })
    ];

  buildWebApp = {

    spagoPackages,

    name,

    title ? name,

    srcDirs,

    configFiles,

    packagesLock,

    spagoDhall ? util.defaultSpagoDhall,

    entryModule ? util.defaultEntry,

    node_modules ? util.emptyDir,

    containerId ? "app"

    }:

    let

      project = buildProject {
        inherit spagoPackages;
        inherit srcDirs;
        inherit configFiles;
        inherit packagesLock;
        inherit spagoDhall;
      };

      buildParcelConfigWeb = {
        src = util.createFiles {
          "." = project + "/*";
          "index.js" = util.defaultEntryJS { inherit entryModule; };
          "index.html" = util.defaultEntryHTML {
            inherit title;
            script = "index.js";
            inherit containerId;
          };
        };
        entry = "index.html";
        inherit node_modules;
      };

    in util.buildParcelWeb buildParcelConfigWeb;

}

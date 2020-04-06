{ pkgs ? import ./nix/nixpkgs.nix {}
, ghc ? import ./nix/ghc.nix { inherit (pkgs) lib haskell; }
, smoke ? import ./nix/smoke.nix { inherit ghc; inherit (pkgs) nix-gitignore; }
}:

ghc.shellFor {
  packages = _: [ smoke ];
  withHoogle = true;
  buildInputs = with pkgs; [
    cabal-install
    ghc.hlint
    git
    glibcLocales
    gmp
    libiconv
    nix
    nixpkgs-fmt
    openssl
    ormolu
    ruby
    zlib
  ];
}

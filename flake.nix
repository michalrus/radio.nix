{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = inputs: {
    packages =
      inputs.nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ] (system: let
        inherit (inputs.nixpkgs.legacyPackages.${system}) callPackage;
      in rec {
        default = radio;
        accuradio = callPackage ./accuradio {};
        radio = callPackage ./radio {
          inherit accuradio radio-chillhop radio-jazzradio-fr;
        };
        radio-chillhop = callPackage ./radio-chillhop {};
        radio-jazzradio-fr = callPackage ./radio-jazzradio-fr {};
      });
  };
}

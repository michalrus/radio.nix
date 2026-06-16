{
  writeShellApplication,
  coreutils,
  util-linux,
  gnused,
  gnugrep,
  curl,
  jq,
  skim,
  mpv,
  mpvScripts,
}: let
  mpv' = mpv.override {scripts = with mpvScripts; [mpris];};
in
  writeShellApplication {
    name = "radio-zenradio";
    runtimeInputs = [coreutils util-linux gnused gnugrep curl jq skim mpv'];
    text = builtins.readFile ./radio.sh;
    derivationArgs.meta.description = "Plays ZenRadio.com in the terminal";
  }

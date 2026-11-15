{ pkgs }:
let
  version = "1.11.0";
  appimage = pkgs.fetchurl {
    url = "https://github.com/TheZwiss/backspace/releases/download/v${version}/Backspace-${version}-linux-x86_64.AppImage";
    hash = "sha256-5ij6Po82PyAFdpbQRYaRpj3FtJR+J+5v0BqnAQjKbAc=";
  };
  upstream = pkgs.fetchzip {
    url = "https://github.com/TheZwiss/backspace/archive/cfa6ce43306f829f1c273f6402ef625362b793da.tar.gz";
    sha256 = "1rzy5wipxg418sqfqjjznsdnf712a8hd1gxnbp6rnsxia25sjfax";
  };
  source = pkgs.applyPatches {
    name = "backspace-audio-source";
    src = upstream;
    patches = [ ./desktop/upstream.patch ];
  };
  extracted = pkgs.appimageTools.extract {
    pname = "backspace";
    inherit version;
    src = appimage;
    postExtract = ''
      export ASAR_MODULE=${pkgs.asar}/lib/node_modules/@electron/asar
      ${pkgs.nodejs}/bin/node ${./desktop/repack.cjs} "$out/resources/app.asar" "$TMPDIR/app"
      ${pkgs.esbuild}/bin/esbuild \
        ${source}/packages/desktop/src/main.ts \
        ${source}/packages/desktop/src/systemAudio.ts \
        ${source}/packages/desktop/src/audioSourcePicker.ts \
        ${source}/packages/desktop/src/audioSourcePickerPreload.ts \
        --platform=node --format=cjs --target=node22 \
        --tsconfig=${source}/packages/desktop/tsconfig.json --outdir="$TMPDIR/app/dist"
      cp ${source}/packages/desktop/resources/audio-source-picker.html "$TMPDIR/app/resources/"
      mkdir -p "$TMPDIR/app/resources/fonts"
      cp ${source}/packages/web/public/fonts/DMSans-Variable.woff2 \
        ${source}/packages/web/public/fonts/OFL.txt "$TMPDIR/app/resources/fonts/"
      ${pkgs.nodejs}/bin/node ${./desktop/repack.cjs} --pack "$TMPDIR/app" "$out/resources/app.asar"
    '';
  };
in
pkgs.appimageTools.wrapAppImage {
  pname = "backspace";
  version = "${version}-audio3";
  src = extracted;
  # Chromium dlopen()s libva for VA-API. The generic AppImage FHS profile has
  # libdrm/libgbm but not libva; the host provides radeonsi_drv_video.so under
  # /run/opengl-driver/lib/dri.
  extraPkgs = pkgs': [ pkgs'.libva ];
  passthru = { inherit source; };
  meta = {
    description = "Backspace desktop client with PipeWire playback source selection";
    homepage = "https://github.com/daviaaze/backspace-nix";
    license = pkgs.lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "backspace";
  };
}

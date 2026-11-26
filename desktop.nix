{ pkgs }:
let
  version = "1.12.0";
  appimage = pkgs.fetchurl {
    url = "https://github.com/TheZwiss/backspace/releases/download/v${version}/Backspace-${version}-linux-x86_64.AppImage";
    hash = "sha256-87EYi7NwDImQzUsQFJ4u/e28qUoTUWIPFRjDQSbLwno=";
  };
  # Community desktop fork: PipeWire audio source selection and stream pop-out.
  source = pkgs.fetchzip {
    url = "https://github.com/daviaaze/backspace/archive/c4abeb4d5040a7db1423ace278586eb8f4bc9be0.tar.gz";
    hash = "sha256-DA/T7OVNZ95huZkJt814Ck5Sor65sfvyzhtCYTkhdO8=";
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
        ${source}/packages/desktop/src/popoutPolicy.ts \
        ${source}/packages/desktop/src/hyprlandPin.ts \
        ${source}/packages/desktop/src/preload.ts \
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
  desktopItem = pkgs.makeDesktopItem {
    name = "backspace";
    desktopName = "Backspace";
    comment = "Chat, voice, video and screen sharing";
    exec = "backspace %U";
    icon = "backspace";
    terminal = false;
    startupNotify = true;
    startupWMClass = "io.github.TheZwiss.backspace";
    categories = [
      "Network"
      "InstantMessaging"
    ];
    mimeTypes = [ "x-scheme-handler/backspace" ];
  };
in
pkgs.appimageTools.wrapAppImage {
  pname = "backspace";
  version = "${version}-audio12";
  src = extracted;
  # Chromium dlopen()s libva for VA-API. The generic AppImage FHS profile has
  # libdrm/libgbm but not libva; the host provides radeonsi_drv_video.so under
  # /run/opengl-driver/lib/dri.
  extraPkgs = pkgs': [ pkgs'.libva ];
  extraInstallCommands = ''
    install -Dm444 ${desktopItem}/share/applications/backspace.desktop \
      "$out/share/applications/backspace.desktop"
    substituteInPlace "$out/share/applications/backspace.desktop" \
      --replace-fail 'Exec=backspace %U' "Exec=$out/bin/backspace %U"
    install -Dm444 ${extracted}/Backspace.png "$out/share/pixmaps/backspace.png"
    ${pkgs.desktop-file-utils}/bin/desktop-file-validate \
      "$out/share/applications/backspace.desktop"
  '';
  passthru = { inherit source; };
  meta = {
    description = "Backspace desktop client with PipeWire playback source selection";
    homepage = "https://github.com/daviaaze/backspace-nix";
    license = pkgs.lib.licenses.agpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "backspace";
  };
}

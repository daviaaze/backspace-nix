{
  description = "Portable Backspace NixOS module";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      makeSystem = modules: lib.nixosSystem { inherit system modules; };
      minimal = makeSystem [
        self.nixosModules.default
        ({ ... }: {
          system.stateVersion = "24.11";
          services.backspace = {
            enable = true;
            domain = "chat.example.net";
            livekitDomain = "media.example.net";
            acmeEmail = "admin@example.net";
          };
        })
      ];
      generator = pkgs.writeShellScript "backspace-test-secrets"
        (builtins.replaceStrings [ "/var/lib/backspace" ] [ "$TMPDIR" ]
          minimal.config.systemd.services.backspace-secrets.script);
      smoke = pkgs.runCommand "backspace-secrets-smoke" { nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.openssl ]; } ''
        export TMPDIR="$NIX_BUILD_TOP/backspace-secrets-test"
        mkdir -m 0700 "$TMPDIR"
        ${generator}
        for name in jwt-secret livekit-api-key livekit-api-secret backspace.env livekit.yaml; do
          test "$(stat -c %a "$TMPDIR/secrets/$name")" = 600
        done
        key=$(cat "$TMPDIR/secrets/livekit-api-key")
        secret=$(cat "$TMPDIR/secrets/livekit-api-secret")
        grep -Fq "\"$key\": \"$secret\"" "$TMPDIR/secrets/livekit.yaml"
        grep -Fq "LIVEKIT_API_KEY=$key" "$TMPDIR/secrets/backspace.env"
        grep -Fq "LIVEKIT_API_SECRET=$secret" "$TMPDIR/secrets/backspace.env"
        cp "$TMPDIR/secrets/jwt-secret" jwt.before
        cp "$TMPDIR/secrets/livekit-api-key" key.before
        cp "$TMPDIR/secrets/livekit-api-secret" secret.before
        ${generator}
        cmp jwt.before "$TMPDIR/secrets/jwt-secret"
        cmp key.before "$TMPDIR/secrets/livekit-api-key"
        cmp secret.before "$TMPDIR/secrets/livekit-api-secret"
        touch $out
      '';
    in {
      nixosModules.default = import ./module.nix;
      checks.${system} = {
        inherit smoke;
        backspace-service-invariants =
          let c = minimal.config;
          in assert c.services.backspace.enable;
             assert c.services.nginx.enable;
             assert c.virtualisation.oci-containers.backend == "podman";
             assert c.virtualisation.oci-containers.containers.backspace.environment.LIVEKIT_URL == "wss://media.example.net";
             assert c.virtualisation.oci-containers.containers.backspace.volumes == [ "/var/lib/backspace/data:/app/data" ];
             assert c.services.nginx.virtualHosts."chat.example.net".enableACME;
             assert c.services.nginx.virtualHosts."media.example.net".enableACME;
             assert c.systemd.services.backspace-secrets.serviceConfig.Type == "oneshot";
             assert c.virtualisation.oci-containers.containers.backspace.environmentFiles == [ "/var/lib/backspace/secrets/backspace.env" ];
             assert c.virtualisation.oci-containers.containers.livekit.volumes == [ "/var/lib/backspace/secrets/livekit.yaml:/etc/livekit.yaml:ro" ];
             assert c.systemd.services.backspace-secrets.serviceConfig.RemainAfterExit;
             assert c.services.nginx.virtualHosts."chat.example.net".locations."/".proxyWebsockets;
             assert c.services.nginx.virtualHosts."media.example.net".locations."/".proxyWebsockets;
             assert c.networking.firewall.allowedTCPPorts == [ 80 443 7881 ];
             assert c.networking.firewall.allowedUDPPortRanges == [ { from = 50000; to = 60000; } ];
             pkgs.runCommand "backspace-service-invariants" { } "touch $out";
      };
    };
}

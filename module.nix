{ config, lib, pkgs, ... }:
let
  cfg = config.services.backspace;
  inherit (lib) mkEnableOption mkIf mkOption types;
  secretDir = "/var/lib/backspace/secrets";
  secretGenerator = ''
    set -eu
    state_dir="''${1:-/var/lib/backspace/secrets}"
    install -d -m 0700 "$state_dir"
    for name in jwt-secret livekit-api-key livekit-api-secret; do
      if [ ! -s "$state_dir/$name" ]; then
        temp="$state_dir/$name.tmp"
        ${pkgs.openssl}/bin/openssl rand -hex 32 > "$temp"
        chmod 0600 "$temp"
        mv "$temp" "$state_dir/$name"
      fi
    done
    key=$(cat "$state_dir/livekit-api-key")
    secret=$(cat "$state_dir/livekit-api-secret")
    {
      printf 'port: 7880\nbind_addresses:\n  - "0.0.0.0"\n'
      printf 'rtc:\n  tcp_port: 7881\n  port_range_start: 50000\n  port_range_end: 60000\n  use_external_ip: %s\n' '${if cfg.useExternalIp then "true" else "false"}'
      printf 'keys:\n  "%s": "%s"\n' "$key" "$secret"
    } > "$state_dir/livekit.yaml.tmp"
    chmod 0600 "$state_dir/livekit.yaml.tmp"
    mv "$state_dir/livekit.yaml.tmp" "$state_dir/livekit.yaml"
    {
      printf 'JWT_SECRET=%s\n' "$(cat "$state_dir/jwt-secret")"
      printf 'LIVEKIT_API_KEY=%s\n' "$key"
      printf 'LIVEKIT_API_SECRET=%s\n' "$secret"
    } > "$state_dir/backspace.env.tmp"
    chmod 0600 "$state_dir/backspace.env.tmp"
    mv "$state_dir/backspace.env.tmp" "$state_dir/backspace.env"
  '';
in {
  options.services.backspace = {
    enable = mkEnableOption "Backspace self-hosted chat";
    domain = mkOption { type = types.str; description = "Public hostname for the Backspace web app."; };
    livekitDomain = mkOption { type = types.str; description = "Public hostname for LiveKit signaling/media API."; };
    acmeEmail = mkOption { type = types.str; description = "Email used by ACME for both HTTPS hostnames."; };
    useExternalIp = mkOption { type = types.bool; default = true; description = "Have LiveKit discover and advertise its public IP (disable on LAN/VPN-only installations)."; };
  };

  config = mkIf cfg.enable {
    assertions = [
      { assertion = cfg.domain != cfg.livekitDomain; message = "Backspace and LiveKit must use distinct hostnames."; }
      { assertion = cfg.acmeEmail != ""; message = "services.backspace.acmeEmail is required."; }
    ];

    services.nginx.enable = true;
    security.acme.acceptTerms = true;
    security.acme.defaults.email = cfg.acmeEmail;
    services.nginx.virtualHosts.${cfg.domain} = {
      enableACME = true;
      forceSSL = true;
      locations."/".proxyPass = "http://127.0.0.1:3000";
      locations."/".proxyWebsockets = true;
      extraConfig = ''client_max_body_size 100M;'';
    };
    services.nginx.virtualHosts.${cfg.livekitDomain} = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:7880";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
        '';
      };
    };

    virtualisation.oci-containers.backend = "podman";
    virtualisation.oci-containers.containers.backspace = {
      image = "ghcr.io/daviaaze/backspace:streaming-3";
      autoStart = true;
      ports = [ "127.0.0.1:3000:3000" ];
      volumes = [ "/var/lib/backspace/data:/app/data" ];
      environmentFiles = [ "${secretDir}/backspace.env" ];
      environment = {
        NODE_ENV = "production";
        HOST = "0.0.0.0";
        PORT = "3000";
        DOMAIN = cfg.domain;
        TRUSTED_PROXY_HOPS = "1";
        BACKSPACE_SOURCE_URL = "https://github.com/daviaaze/backspace";
        DB_PATH = "/app/data/backspace.db";
        UPLOAD_DIR = "/app/data/uploads";
        LIVEKIT_URL = "wss://${cfg.livekitDomain}";
      };
    };
    virtualisation.oci-containers.containers.livekit = {
      image = "livekit/livekit-server:v1.9.11";
      autoStart = true;
      extraOptions = [ "--network=host" ];
      volumes = [ "${secretDir}/livekit.yaml:/etc/livekit.yaml:ro" ];
      cmd = [ "--config" "/etc/livekit.yaml" ];
    };

    networking.firewall = {
      allowedTCPPorts = [ 80 443 7881 ];
      allowedUDPPortRanges = [ { from = 50000; to = 60000; } ];
    };

    systemd.tmpfiles.rules = [ "d ${secretDir} 0700 root root - -" "d /var/lib/backspace/data 0750 root root - -" ];
    systemd.services.backspace-secrets = {
      description = "Generate persistent Backspace and LiveKit credentials";
      before = [ "podman-backspace.service" "podman-livekit.service" ];
      requiredBy = [ "podman-backspace.service" "podman-livekit.service" ];
      after = [ "local-fs.target" ];
      requires = [ "local-fs.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; User = "root"; UMask = "0077"; };
      path = [ pkgs.coreutils ];
      script = ''
        set -eu
        ${secretGenerator}
        install -d -m 0750 /var/lib/backspace/data/uploads
      '';
    };
  };
}

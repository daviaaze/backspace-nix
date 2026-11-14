# Backspace no NixOS

Módulo NixOS independente para executar [Backspace](https://github.com/thezwiss/backspace) e LiveKit com Podman, Nginx e certificados ACME. O módulo é público; o aplicativo Backspace é distribuído pelo upstream sob AGPL-3.0. Nenhuma configuração deste projeto ativa o sistema: o administrador importa o módulo e decide quando reconstruir e aplicar.

## Requisitos

- NixOS x86_64-linux com flakes habilitados e `virtualisation.podman.enable = true`.
- Dois hostnames DNS distintos apontando para o servidor: um para o app, outro para LiveKit.
- Para ACME HTTP-01, tráfego de entrada TCP 80/443 alcançável da Internet durante emissão/renovação.
- Portas TCP 7881 e UDP 50000–60000 permitidas no firewall e, se aplicável, encaminhadas pelo roteador até o servidor. Com NAT público, mantenha `useExternalIp = true`; LAN/VPN sem acesso público pode definir `false`.

## Importar

Adicione ao flake do host:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    backspace-nix.url = "github:daviaaze/backspace-nix";
    backspace-nix.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { nixpkgs, backspace-nix, ... }: {
    nixosConfigurations.meu-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        backspace-nix.nixosModules.default
      ];
    };
  };
}
```

Na configuração NixOS:

```nix
{ ... }:
{
  virtualisation.podman.enable = true;
  services.backspace = {
    enable = true;
    domain = "chat.seu-dominio.example";
    livekitDomain = "media.seu-dominio.example";
    acmeEmail = "admin@seu-dominio.example";
    useExternalIp = true;
  };
}
```

Substitua os domínios e email pelos valores reais antes de avaliar. `domain`, `livekitDomain` e `acmeEmail` são obrigatórios quando o serviço está habilitado. O módulo configura Nginx e ACME, encaminhando o app e a sinalização WebSocket do LiveKit por HTTPS/WSS. Não coloque esses hostnames atrás do proxy HTTP de um CDN: os clientes de mídia LiveKit precisam conectar diretamente às portas de mídia. O módulo não inclui DNS nem regras de NAT do roteador.

Depois de revisar a configuração, o administrador pode executar `sudo nixos-rebuild switch --flake .#<host>`. O primeiro usuário registrado no Backspace recebe privilégios administrativos; proteja o serviço e desabilite/controle novos registros conforme a política do upstream após o bootstrap.

## Segredos e dados

Na primeira inicialização, uma unidade oneshot cria JWT secret e credenciais LiveKit aleatórias em `/var/lib/backspace/secrets`, persistidos com acesso root-only. O mesmo par LiveKit é compartilhado pelo app e servidor. O app persiste banco e uploads em `/var/lib/backspace/data`; inclua ambos os diretórios nos seus backups. Perder os segredos pode invalidar sessões/tokens e impedir que o LiveKit aceite tokens já emitidos. Faça backup protegido dos segredos e teste restauração. Para rotação, planeje a alteração coordenada de credenciais e reinicie ambos os serviços; não edite arquivos dentro de `/nix/store`.

ACME precisa alcançar o servidor na porta 80. Em redes locais, HTTPS público pode não resolver internamente sem DNS split-horizon; clientes precisam confiar no certificado. O serviço não abre portas para acesso administrativo remoto além dos endpoints descritos.

## Verificações de avaliação

`nix flake check` avalia uma configuração NixOS mínima e invariantes do módulo e executa um teste isolado de geração, permissões, consistência e preservação dos segredos. Não ativa serviços nem baixa a imagem do aplicativo. As versões fixadas são Backspace `1.11.0` e LiveKit `v1.9.11`; as imagens são obtidas quando os serviços iniciam.

Os checks passaram localmente. Não foi realizado teste de chamada real nem implantação deste flake: após aplicar, confira `systemctl status podman-backspace podman-livekit`, acesse `https://<domínio>/api/health` e teste voz/vídeo entre dois clientes.

# Backspace no NixOS

Módulo NixOS independente para executar [Backspace](https://github.com/thezwiss/backspace) e LiveKit com Podman, Nginx e certificados ACME. O módulo é público; o aplicativo Backspace é distribuído pelo upstream sob AGPL-3.0. Nenhuma configuração deste projeto ativa o sistema: o administrador importa o módulo e decide quando reconstruir e aplicar.

## Cliente desktop

Execute o cliente para Linux x86_64 diretamente com Nix:

```sh
nix run github:daviaaze/backspace-nix#backspace
```

Sem endereço salvo, o cliente abre o seletor de instância: informe o endereço HTTPS do servidor Backspace. Use **Change Instance** para trocar de servidor. `BACKSPACE_URL` pode definir o endereço ao iniciar. O pacote é uma variante comunitária do Backspace `1.11.0`, com alterações locais de áudio; não ativa nem configura um servidor.

### Compartilhar áudio no Linux/PipeWire

1. Entre na chamada e habilite **System audio** nas opções de compartilhamento.
2. Ao escolher a tela, o cliente abre **Compartilhar áudio**: marque os streams desejados e pressione **Compartilhar selecionados**, ou escolha **Todo áudio (menos Backspace)**.
3. Escolha a tela/janela no portal do compositor e inicie a transmissão normalmente.

Comece a reprodução antes de abrir o seletor; **Atualizar** recarrega a lista preservando as marcações disponíveis. Os streams aparecem por aplicativo e nome da reprodução. A seleção vale para os streams atuais, não para todo aplicativo futuro: se o programa reiniciar sua reprodução, pare e selecione novamente. Não há alteração de seleção ao vivo.

O seletor segue o visual Aether Drift do Backspace: paleta escura, acento violeta,
cards selecionáveis e fonte DM Sans incluída localmente, sem download de fontes.
A janela é um modal compacto sem moldura do sistema, centralizado sobre o cliente;
a lista rola sem esconder os botões. **Esc**, o botão fechar e **Cancelar** encerram
a escolha sem compartilhar áudio. Atualizações desse visual exigem apenas sair do
cliente pela bandeja e executar `nix run --refresh github:daviaaze/backspace-nix#backspace`,
sem rebuild do servidor.

A captura aceita reprodução em saídas não padrão e saídas virtuais (por exemplo, roteamento de áudio por efeitos), sem mudar a saída ou o microfone padrão. Os processos do próprio Backspace ficam excluídos. Cancelamento ou falha após selecionar fontes não autoriza fallback para o áudio inteiro do desktop. Áudio de chamadas reproduzido por **outros** aplicativos só fica fora se você não os selecionar.

Verificado: tipos TypeScript, 19 testes de roteamento, build Nix, janela real Electron e captura real do Chromium com dois tons sintéticos em uma saída virtual não padrão. O stream não selecionado ficou mais de 60 dB abaixo do selecionado. Não foi validada uma chamada LiveKit entre dois computadores; uma tentativa WebRTC local não estabeleceu recepção, portanto não é prova de chamada completa.

### Código-fonte e licença do desktop

O módulo NixOS e o empacotamento próprio usam a licença MIT da raiz. O desktop Backspace e as alterações em `desktop/upstream.patch` são **AGPL-3.0-only**, conforme a [licença upstream](https://github.com/TheZwiss/backspace/blob/cfa6ce43306f829f1c273f6402ef625362b793da/LICENSE). O patch inclui os testes e a interface local; `desktop.nix` fixa fonte e AppImage pelos respectivos hashes e reconstrói o ASAR sem recompilar nem substituir os módulos nativos.

Para obter o código-fonte completo com as alterações aplicadas:

```sh
nix build github:daviaaze/backspace-nix#backspace-source
```

## Requisitos do servidor

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

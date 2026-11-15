# Backspace no NixOS

Módulo NixOS independente para executar [Backspace](https://github.com/thezwiss/backspace) e LiveKit com Podman, Nginx e certificados ACME. O módulo é público; o aplicativo Backspace é distribuído pelo upstream sob AGPL-3.0. Nenhuma configuração deste projeto ativa o sistema: o administrador importa o módulo e decide quando reconstruir e aplicar.

## Cliente desktop

Execute o cliente para Linux x86_64 diretamente com Nix:

```sh
nix run github:daviaaze/backspace-nix#backspace
```

Sem endereço salvo, o cliente abre o seletor de instância: informe o endereço HTTPS do servidor Backspace. Use **Change Instance** para trocar de servidor. `BACKSPACE_URL` pode definir o endereço ao iniciar. O pacote é uma variante comunitária do Backspace `1.11.0`, com alterações locais de áudio; não ativa nem configura um servidor.

A instalação do pacote pelo NixOS/Home Manager também inclui o atalho
**Backspace**, ícone e suporte a links `backspace://` no menu de aplicativos.
`nix run` apenas executa o cliente; não instala esse atalho no perfil.

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

### Aceleração de vídeo (AMD/NixOS)

O pacote inclui `libva` no ambiente FHS e habilita o encoder VA-API do Chromium no Linux, preservando as features passadas na linha de comando. Na RX 6700 XT, o teste WebRTC sintético H.264 720p30 usou `VaapiVideoEncodeAccelerator` e `VaapiVideoDecoder`, ambos com `powerEfficient=true`: 121 frames codificados e 121 decodificados, sem descarte. Também houve reprodução real em 3840×2160, configurada para 30 FPS, com encode/decode VA-API e zero frames descartados.

Foi necessário corrigir a ordem dos parâmetros H.264: o encoder radeonsi emitia `IDR,SPS,PPS`, causando vídeo preto no receptor. O worker da interface reposiciona os parâmetros para `SPS,PPS,IDR`, sem alterar os outros NALs ou os metadados dos frames. É o problema descrito no [Chromium 574768145](https://issues.chromium.org/issues/574768145). O tratamento cobre os senders H.264 de câmera e compartilhamento e não substitui transforms de criptografia já instalados.

**Atualize primeiro o servidor para `ghcr.io/daviaaze/backspace:streaming-2` e só depois o cliente.** O reparo roda na interface servida pelo servidor; ativar encode GPU com uma interface upstream/antiga sem esse worker pode gerar vídeo preto em AMD. VP9/AV1 continuam sem encode por hardware nessa RX 6700 XT; selecione **H.264** para usar o encoder testado. O teste foi WebRTC local com vídeo sintético, não uma chamada LiveKit entre computadores.

### Resolução 4K e nativa

Novas instâncias permitem 540p, 720p, 1080p, 1440p, 2160p (4K) e **Nativa**; o máximo numérico é 2160. Instâncias existentes mantêm os limites já salvos: um admin deve habilitar 2160p/Nativa em **Configurações da instância → Streaming** e salvar.

Uma resolução numérica é solicitada como ideal, preservando a proporção da fonte; Nativa não impõe dimensões à captura. Não é promessa de resolução transmitida fixa: o modo **Jogo** permite adaptação de resolução/FPS à CPU e à banda; **Texto** prioriza manter a resolução. Fontes menores e limites do encoder continuam podendo produzir dimensões diferentes da opção escolhida.

A captura aceita reprodução em saídas não padrão e saídas virtuais (por exemplo, roteamento de áudio por efeitos), sem mudar a saída ou o microfone padrão. Os processos do próprio Backspace ficam excluídos. Cancelamento ou falha após selecionar fontes não autoriza fallback para o áudio inteiro do desktop. Áudio de chamadas reproduzido por **outros** aplicativos só fica fora se você não os selecionar.

Verificado: tipos TypeScript, 19 testes de roteamento, build Nix, janela real Electron e captura real do Chromium com dois tons sintéticos em uma saída virtual não padrão. O stream não selecionado ficou mais de 60 dB abaixo do selecionado. Não foi validada uma chamada LiveKit entre dois computadores; uma tentativa WebRTC local não estabeleceu recepção, portanto não é prova de chamada completa.

### Pop-out fixável de stream

No tile de uma stream que você está assistindo há um botão **Destacar**: abre a stream numa janela separada, com botões para fixar e fechar. No Hyprland, **Fixar** deixa a janela flutuante e fixada em todos os workspaces (o Wayland não tem "sempre no topo" padrão, então o cliente usa o `hyprctl`); ao desafixar, uma janela que estava tilada volta a ser tilada. Em outros ambientes o cliente usa `setAlwaysOnTop` do Electron, que o Wayland ignora. A janela de vídeo é silenciosa: o áudio continua vindo da stream no app.

O botão de destacar faz parte da **interface web**, servida pelo seu servidor. Ele só aparece se o servidor usar a imagem do fork (`ghcr.io/daviaaze/backspace`, veja abaixo); o cliente desktop sozinho não o adiciona. Verificado em janela real: criação do pop-out, bloqueio de outras janelas e fixar/desafixar no Hyprland 0.57. A tela do pop-out com vídeo LiveKit real ainda não foi exercitada.

### Código-fonte e licença do desktop

O módulo NixOS e o empacotamento usam a licença MIT da raiz. O desktop e a interface web são **AGPL-3.0-only** e vêm do fork público [`daviaaze/backspace`](https://github.com/daviaaze/backspace) (branch `community/linux-audio-popout`, baseado na `v1.11.0` do upstream), conforme a [licença upstream](https://github.com/TheZwiss/backspace/blob/cfa6ce43306f829f1c273f6402ef625362b793da/LICENSE). `desktop.nix` fixa o commit do fork e o AppImage pelos hashes e reconstrói o ASAR sem substituir os módulos nativos. Para um servidor com a interface modificada, a oferta de código-fonte (AGPL §13) do próprio app deve apontar para o fork: defina `BACKSPACE_SOURCE_URL`.

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

# PS1/2 Emulator

Central pessoal de jogos para macOS, feita em **SwiftUI + AppKit**, com visual inspirado no menu do PlayStation 2.

**Este projeto é um inicializador, não um emulador.** Ele abre o [DuckStation](https://www.duckstation.org/) para PS1 e o [PCSX2](https://pcsx2.net/) para PS2. Cada emulador precisa ser instalado e configurado separadamente. Jogos, BIOS e saves não estão incluídos.

O repositório chama-se `ps1-2-emulator`; o aplicativo se chama **PS1/2**. O bundle usa `PS1-2.app`, pois `/` é separador de pastas no macOS. Versão atual: **4.3, build 9**.

## Funcionalidades

- Menu PS1/PS2, controles correspondentes e logo PlayStation.
- Prévia animada ao passar o mouse sobre cada console: GIF em loop, sem som e **sem iniciar o emulador**. Ao sair, voltam os círculos azuis. Respeita a opção Reduzir movimento do macOS.
- Abertura com GIF do console antes de iniciar/focar o emulador.
- Catálogo por console, capas frontais, navegação por mouse, teclado e controle compatível.
- Indicador ligado/desligado, tempo desde a abertura do emulador e identificação do jogo carregado quando possível.
- Miniatura da capa ao lado do jogo carregado no menu principal: 36 px de altura, preservando a proporção de cada console. Usa as mesmas capas do catálogo; se não houver uma correspondência segura, mostra um ícone de disco. A consulta acontece em segundo plano quando o jogo muda, sem reler a biblioteca a cada segundo.
- Pedido de encerramento normal do emulador, com confirmação; não força o fechamento.
- Interface compacta, ajustada para MacBook de 14 polegadas, com tela cheia.

## Requisitos da central

| Dependência | Necessidade |
|---|---|
| Mac Apple Silicon — M1 ou posterior | O script compila para `arm64`; Intel não é alvo deste build. |
| macOS 14 ou posterior | Mínimo definido em `Info.plist` e no compilador. |
| Xcode Command Line Tools | Fornece `swiftc`, SDK do macOS e ferramentas de compilação. |
| Git | Para clonar o repositório; normalmente incluído nas Command Line Tools. |
| DuckStation e PCSX2 | Aplicativos externos usados para executar os jogos. |
| BIOS e imagens dos seus jogos | Configure nos próprios emuladores, conforme a documentação oficial. |

Não usa Node.js, npm, Python, Homebrew, CocoaPods ou pacotes Swift externos. AppKit, SwiftUI, Foundation, Combine, GameController e ImageIO são frameworks do sistema. `build.sh` também usa ferramentas do macOS: `sips`, `ditto`, `xattr`, `codesign` e `plutil`.

O código foi compilado e testado com Swift 6.4 em Apple Silicon. A compatibilidade mínima declarada é macOS 14; nem todas as versões de macOS/SDK foram testadas.

## 1. Preparar o ambiente

Caso ainda não tenha as ferramentas de desenvolvimento:

```bash
xcode-select --install
```

Conclua a instalação no macOS. Depois confira:

```bash
xcode-select -p
xcrun --find swiftc
xcrun swiftc --version
git --version
```

Referência: [instalação das Command Line Tools pela Apple](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools).

## 2. Clonar o repositório privado

É necessário estar autenticado no GitHub com uma conta que tenha acesso. Exemplo por HTTPS:

```bash
mkdir -p /Users/"$(whoami)"/Workspace/Personal
cd /Users/"$(whoami)"/Workspace/Personal
git clone https://github.com/rafaelferreiram/ps1-2-emulator.git
cd ps1-2-emulator
```

Também pode usar SSH se sua chave já estiver configurada. Não coloque tokens ou senhas no comando, no código ou no repositório. A pasta local sugerida é `~/Workspace/Personal/ps1-2-emulator`.

## 3. Compilar

Na raiz do repositório:

```bash
bash build.sh
```

O script gera o ícone, copia os recursos, compila o executável nativo, aplica uma **assinatura local ad hoc** e valida o bundle. Ao terminar, informa um caminho semelhante a:

```text
/private/tmp/ps12-build.ABC123/PS1-2.app
```

O nome da pasta temporária muda a cada build. Use o caminho real impresso no seu Terminal. Não é necessário certificado Apple Developer para o build local; a assinatura ad hoc não equivale à notarização da Apple.

O build padrão usa uma pasta temporária local para evitar metadados do Finder/iCloud que podem interferir na assinatura. `cache/`, `MakeIcon` e `AppIcon.iconset/` são gerados localmente e ignorados pelo Git.

## 4. Instalar e rodar

1. Feche somente a central PS1/2, se estiver aberta. Não é necessário fechar os emuladores para substituir a central, mas salve suas partidas antes de qualquer manutenção.
2. Faça uma cópia da central antiga se quiser preservar essa versão.
3. Abra no Finder a pasta temporária indicada pelo build e arraste **PS1-2.app** para **Aplicativos**. Confirme a substituição apenas se esse for o app que deseja atualizar.
4. Abra **Aplicativos → PS1-2**. Se quiser, mantenha o ícone no Dock.

Para abrir pelo Terminal depois da instalação:

```bash
open /Applications/PS1-2.app
```

O aplicativo não é executado com `swift run`: este projeto gera um bundle macOS diretamente com `build.sh`.

## 5. Preparar os emuladores

Veja [o guia de download e configuração do PS1/PS2](docs/EMULADORES.md), com fontes oficiais, BIOS, pastas e primeira execução. Os emuladores devem estar em:

```text
/Applications/DuckStation.app
/Applications/PCSX2.app
```

Teste primeiro um jogo diretamente no emulador. A central não configura BIOS, renderizador, memória ou mapeamento de controle automaticamente.

## Bibliotecas e capas

A configuração atual utiliza estas pastas, fora do repositório:

```text
/Volumes/Extreme SSD/Emulacao/
├── PS1/Jogos/
└── PS2/Jogos/
```

O nome do SSD e os caminhos estão definidos em `PS12.swift`, `GameCatalog.swift` e `EmulatorMonitor.swift`. **Ainda não existe uma tela de preferências ou arquivo `.env` para mudá-los.** Para usar outro volume/pasta, ajuste os caminhos nesses três arquivos e recompile; ajuste também os rótulos visuais de `Extreme SSD` em `PS12.swift` e `GameCatalogView.swift`. Alterar só o nome no README não muda o app.

As capas são lidas de `~/Library/Application Support/DuckStation/covers` e `~/Library/Application Support/PCSX2/covers`, com alternativas junto aos jogos. Três capas frontais incluídas em `assets/Covers/PS2` têm prioridade para padronizar a apresentação. Imagens deitadas ou quadradas são rejeitadas no PS2 para evitar capas completas de frente e verso; o filtro não reconhece automaticamente toda arte incorreta.

A listagem não copia jogos. ZIP/RAR/7z não aparecem. CUE/BIN válidos são agrupados, sem listar cada faixa como um jogo. Descritores incompletos são omitidos com aviso.

Se o macOS pedir acesso ao volume externo, escolha **Permitir** para listar os jogos. Enquanto o aviso aguarda uma resposta, pode aparecer “Lendo jogos e capas…”. Nenhuma permissão é contornada automaticamente.

## Controles

| Ação | Teclado | Controle compatível |
|---|---|---|
| Selecionar console/jogo | Setas | Direcional |
| Confirmar/abrir | Enter | X |
| Voltar/cancelar abertura | Esc | Círculo |
| Tela cheia/janela | F | Quadrado |
| Listar jogos do console / atualizar catálogo | T | Triângulo |
| Encerrar a central | ⌘Q | — |

No mouse, passar sobre PS1/PS2 mostra a prévia; clicar inicia a abertura. A prévia é silenciosa, usa os GIFs locais e não faz downloads. O mapeamento do controle dentro dos jogos continua sendo responsabilidade de cada emulador.

## Sessões e limites

- “Ligado” significa que o aplicativo do emulador está aberto; não garante que um jogo esteja rodando.
- O contador mede o tempo desde a abertura do emulador, incluindo pausas e tempo parado no menu.
- “Jogo carregado” é inferido a partir de imagens de disco abertas pelo processo. A central não distingue execução de pausa e não usa logs antigos para adivinhar.
- Imagens fora da biblioteca, arquivos integralmente em memória ou acesso negado podem impedir a identificação.
- Trocar de jogo com outra sessão carregada é bloqueado. Finalize a sessão no próprio emulador.
- Se DuckStation estiver aberto sem jogo identificado, a central pede confirmação para encerrá-lo normalmente e reabri-lo com o jogo escolhido. Nunca força a saída.
- Fechar a central não salva partidas e não encerra os emuladores automaticamente.

## Testes

Na raiz do projeto:

```bash
bash tests/run-monitor-tests.sh
bash tests/run-catalog-tests.sh
bash tests/run-hover-animation-tests.sh
bash tests/run-now-playing-tests.sh
```

Esses testes usam fixtures locais e os GIFs incluídos; não precisam baixar jogos ou BIOS, nem iniciam emuladores. As suítes cobrem o monitor de sessões, animações, catálogo, correspondência exata entre o disco aberto e a capa (incluindo CUE/CCD/M3U) e seis layouts compactos de miniatura. O teste de layout gera uma prévia temporária com dados fictícios para inspeção visual.

Opcional, somente na máquina com os emuladores/SSD configurados: inventário de leitura das bibliotecas reais:

```bash
bash tests/run-catalog-tests.sh --installed --front-covers "$PWD/assets/Covers"
```

Isso lista caminhos dos jogos no Terminal; não compartilhe a saída se contiver dados que não quer divulgar. Os testes não comprovam jogabilidade de cada título nem substituem um teste físico do controle.

## Estrutura

```text
PS12.swift                 Menu, janelas, estado e abertura de emuladores
ControllerInput.swift      Entrada pelo controle
EmulatorMonitor.swift      Monitor de processos e jogo carregado
GameCatalog.swift          Leitura das bibliotecas e seleção de capas
GameCatalogView.swift      Interface do catálogo
NowPlayingGameView.swift   Miniatura assíncrona do jogo carregado
StartupAnimation.swift     GIF antes de abrir o emulador
HoverAnimation.swift       Prévia decorativa em loop
MakeIcon.swift             Geração do ícone do app
Info.plist                 Identidade e versão do bundle
build.sh                   Compilação e assinatura local
assets/                    Logo, fotos, GIFs e três capas frontais
tests/                     Testes automatizados
docs/EMULADORES.md         Downloads e configuração inicial
Creditos.txt               Fontes e atribuição dos recursos visuais
```

## Créditos e uso

Projeto pessoal, sem vínculo oficial com Sony, DuckStation ou PCSX2. Os recursos de terceiros mantêm seus respectivos direitos; manter o repositório privado não altera esses direitos. Veja [Creditos.txt](Creditos.txt) para a origem dos controles, logo, GIFs e capas. Não foi atribuída uma licença aberta de redistribuição aos recursos de terceiros.

Não inclua ROMs, BIOS, saves, credenciais, backups pessoais ou builds dos emuladores neste repositório. O `.gitignore` ajuda a evitar inclusões acidentais, mas não substitui revisar os arquivos antes de um commit.

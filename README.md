# PS1/2 Emulator

Central pessoal de jogos para macOS, feita em **SwiftUI + AppKit**, com visual inspirado no menu do PlayStation 2.

**Este projeto é um inicializador, não um emulador.** Ele abre o [DuckStation](https://www.duckstation.org/) para PS1 e o [PCSX2](https://pcsx2.net/) para PS2. O instalador deste repositório compila a central e baixa os emuladores oficiais que estiverem faltando; a configuração inicial de cada emulador continua sendo manual. Jogos, BIOS e saves não estão incluídos.

O repositório chama-se `ps1-2-emulator`; o aplicativo se chama **PS1/2**. O bundle usa `PS1-2.app`, pois `/` é separador de pastas no macOS. Versão atual: **4.10, build 19**.

## Começar aqui: clonar, instalar e abrir

Em um **Mac Apple Silicon com macOS 14 ou posterior**, abra o Terminal. Este repositório é privado: sua conta do GitHub precisa ter acesso e estar autenticada para o clone.

```bash
git clone https://github.com/rafaelferreiram/ps1-2-emulator.git
cd ps1-2-emulator
bash install.sh
open /Applications/PS1-2.app
```

**Já clonou?** Entre na pasta `ps1-2-emulator` e execute apenas os dois últimos comandos. Também é possível abrir a pasta no Finder e dar duplo clique em **Instalar.command**, que executa o mesmo instalador no Terminal.

**Prefere baixar sem Git?** No GitHub, use **Code → Download ZIP**, extraia o ZIP no Finder, leia este README e execute **Instalar.command** na pasta extraída. As Command Line Tools continuam necessárias para compilar. Como o repositório é privado, apenas contas com acesso conseguem baixá-lo; o instalador não depende da presença de uma pasta `.git`.

Se o Git ou as ferramentas de compilação estiverem faltando, execute `xcode-select --install`, conclua o instalador da Apple e tente novamente. Se `/Applications` não permitir gravação, use a [instalação na sua pasta pessoal](#instalar-sem-permissão-de-gravação-em-applications).

O script pede confirmação, instala a central e baixa **DuckStation (PS1) e PCSX2 (PS2) apenas se estiverem ausentes**. Não precisa de Homebrew, não usa `sudo`, não reinicia o Mac e não abre aplicativos automaticamente. Depois:

1. Abra DuckStation e PCSX2 uma vez, forneça suas BIOS e configure o controle e as bibliotecas no assistente de cada um. Se o macOS pedir Rosetta para o PCSX2, a instalação e a aceitação ficam por sua conta.
2. Teste um jogo diretamente em cada emulador. O instalador **não baixa BIOS nem jogos** e não configura os emuladores por você.
3. Na central, abra **Pastas de jogos** (ou **⌘,**) e escolha a pasta PS1 e a pasta PS2 no Mac ou em um disco externo. A escolha carrega aquele catálogo; selecione o console e pressione **T / △** para ver os jogos. Dentro do catálogo, **T / △** atualiza a lista quando adicionar/remover arquivos. Veja [Bibliotecas e capas](#bibliotecas-e-capas).

**Atenção em outra máquina:** clonar ou baixar o repositório não copia catálogo, capas em cache, jogos, BIOS, saves ou configurações pessoais. Não é preciso editar código para escolher a biblioteca. A central abre sem SSD, mas uma máquina nova só terá catálogo offline depois de uma primeira carga com a pasta acessível. Além dos jogos, o usuário precisa fornecer as BIOS e concluir a configuração inicial dos emuladores; o instalador não elimina essa etapa.

## Funcionalidades

- Menu PS1/PS2, controles correspondentes e logo PlayStation.
- Marcador **P1** (Player 1) no console pré-selecionado, com visual arcade em azul-claro. Acompanha mouse, teclado e analógico; é apenas um cursor visual, não muda a porta do controle nos emuladores. Desenho vetorial local, sem novas imagens, fontes ou downloads.
- Prévia animada do console pré-selecionado: GIF em loop, sem som e **sem iniciar o emulador**. Acompanha mouse, teclado e controle; continua ao retirar o mouse do cartão. A prévia pausa quando a central sai de foco e respeita a opção Reduzir movimento do macOS.
- Abertura com GIF do console antes de iniciar/focar o emulador.
- Catálogo por console, capas frontais, navegação por mouse, teclado e controle compatível.
- **Pastas de jogos**: uma biblioteca independente por console, local ou externa, salva neste Mac. Mantém o SSD original como padrão e permite restaurá-lo sem mover arquivos.
- Cache local de catálogo e miniaturas, compartilhado com a capa do jogo carregado, para reduzir leituras repetidas do SSD.
- Catálogos salvos de PS1 e PS2 restaurados ao iniciar, inclusive sem o SSD; aviso visual no estilo console ao tentar jogar offline. O subtítulo é “Playstation Retro Emulator”, sem o rótulo “MENU PRINCIPAL”.
- Indicador ligado/desligado, tempo desde a abertura do emulador e identificação do jogo carregado quando possível.
- Miniatura da capa ao lado do jogo carregado no menu principal: 36 px de altura, preservando a proporção de cada console. Usa as mesmas capas do catálogo; se não houver uma correspondência segura, mostra um ícone de disco. A consulta acontece em segundo plano quando o jogo muda, sem reler a biblioteca a cada segundo.
- Pedido de encerramento normal do emulador, com confirmação; não força o fechamento.
- A interface acompanha o tamanho da janela e da tela em que ela está. No MacBook de 14 polegadas e em outros monitores, maximizar ou usar tela cheia aumenta o menu, a prévia e o catálogo para ocupar a área disponível.
- O ícone fixado no Dock continua sendo o logo atual depois de encerrar a central. A instalação registra essa cópia e deixa de usar o ícone de backups ou da Lixeira.
- O botão **PlayStation** do DualSense (PS5) traz a central para a frente e volta ao menu dos consoles. Funciona no catálogo, nas pastas de jogos e com DuckStation ou PCSX2 na frente. Não encerra o emulador nem altera o mapeamento dentro do jogo.

## Requisitos da central

| Dependência | Necessidade |
|---|---|
| Mac Apple Silicon — M1 ou posterior | O script compila para `arm64`; Intel não é alvo deste build. |
| macOS 14 ou posterior | Mínimo definido em `Info.plist` e no compilador. |
| Xcode Command Line Tools | Fornece `swiftc`, SDK do macOS e ferramentas de compilação. |
| Git | Para clonar o repositório; normalmente incluído nas Command Line Tools. |
| DuckStation e PCSX2 | Aplicativos externos usados para executar os jogos. |
| BIOS e imagens dos seus jogos | Configure nos próprios emuladores, conforme a documentação oficial. |

Não usa Node.js, npm, Python, Homebrew, CocoaPods ou pacotes Swift externos. AppKit, SwiftUI, Foundation, Combine, GameController, ImageIO e CryptoKit são frameworks do sistema. `build.sh` também usa ferramentas do macOS: `sips`, `ditto`, `xattr`, `codesign` e `plutil`.

O código foi compilado e testado com Swift 6.4 em Apple Silicon. A compatibilidade mínima declarada é macOS 14; nem todas as versões de macOS/SDK foram testadas.

## Instalação detalhada

### 1. Preparar o ambiente

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

### 2. Clonar o repositório privado

É necessário estar autenticado no GitHub com uma conta que tenha acesso. Exemplo por HTTPS:

```bash
mkdir -p /Users/"$(whoami)"/Workspace/Personal
cd /Users/"$(whoami)"/Workspace/Personal
git clone https://github.com/rafaelferreiram/ps1-2-emulator.git
cd ps1-2-emulator
```

Também pode usar SSH se sua chave já estiver configurada. Não coloque tokens ou senhas no comando, no código ou no repositório. A pasta local sugerida é `~/Workspace/Personal/ps1-2-emulator`.

### 3. Executar o instalador

Na raiz do repositório:

```bash
bash install.sh
```

O instalador verifica macOS, arquitetura e Command Line Tools, mostra o plano e pede confirmação. Em seguida compila a central com `build.sh` e instala em `/Applications`. Se faltarem os emuladores, consulta as releases oficiais do [DuckStation](https://github.com/stenzek/duckstation/releases/tag/latest) e do [PCSX2](https://github.com/PCSX2/pcsx2/releases/latest), baixa os pacotes macOS e os instala no mesmo destino. Para o PCSX2, usa a release estável, não uma prerelease/Nightly.

Antes de instalar um download, confere o **SHA-256 informado pela API oficial do GitHub**, a identidade do bundle e a assinatura. Se a verificação falhar ou o hash exigido não estiver disponível, interrompe essa instalação: não existe opção para ignorar essas verificações. Isso não dispensa os avisos de segurança e a primeira abertura do macOS.

A verificação de assinatura confere a integridade do app; não significa notarização ou aprovação da Apple. O DuckStation pode usar assinatura ad hoc, e a central é compilada com assinatura ad hoc local. Os emuladores baixados mantêm a quarentena para a verificação normal do macOS na primeira abertura.

- DuckStation e PCSX2 existentes em `/Applications`, `~/Applications` ou no destino escolhido são preservados quando têm o nome de app e bundle ID esperados. O instalador **não os atualiza nem sobrescreve**. Uma instalação com outro nome pode exigir conferência manual.
- Se a central já existir, feche-a antes de continuar. A versão anterior é guardada em uma subpasta oculta `.ps12-backup.*` no destino; o caminho do backup aparece no Terminal. Não se trata de backup das suas partidas.
- Para voltar à versão anterior, feche a central e mova o `PS1-2.app` do caminho de backup informado de volta para o destino de instalação. Os emuladores e os saves não precisam ser substituídos.
- Jogos, BIOS, saves, memory cards, configurações dos emuladores e SSD não são modificados. Pode executar novamente para reinstalar a central e completar dependências ausentes.
- Nenhum app é aberto automaticamente. Não há reboot, aceitação automática de licenças/Rosetta, instalação de Homebrew nem remoção automática de quarentena dos downloads.
- Em caso de falha, o Terminal informa a pasta temporária de diagnóstico. Em caso de sucesso, os downloads temporários são removidos; backups da central ficam preservados no destino. Se uma cópia falhar por falta de espaço/permissão, os apps já instalados com sucesso podem permanecer: corrija a causa e execute novamente.

Opções disponíveis:

| Comando | O que faz |
|---|---|
| `bash install.sh` | Compila/instala a central e baixa os emuladores ausentes, após confirmação. |
| `bash install.sh --check` | Diagnóstico sem compilar, baixar ou modificar arquivos. |
| `bash install.sh --no-emulators` | Compila/instala somente a central; não baixa emuladores. |
| `bash install.sh --destination "$HOME/Applications"` | Usa a pasta pessoal de aplicativos, que deve existir. |
| `bash install.sh --yes` | Dispensa a confirmação do script; não aceita licenças nem avisos do macOS. |

#### Instalar sem permissão de gravação em /Applications

Não execute o instalador com `sudo`. Crie sua pasta pessoal de aplicativos e escolha esse destino:

```bash
mkdir -p "$HOME/Applications"
bash install.sh --destination "$HOME/Applications"
open "$HOME/Applications/PS1-2.app"
```

Não mova a pasta do repositório para dentro de `PS1-2.app`. O app instalado contém o executável e os recursos necessários para abrir a central; a biblioteca e os emuladores permanecem externos.

### 4. Abrir e preparar os emuladores

Para o destino padrão, abra **Aplicativos → PS1-2**, ou execute:

```bash
open /Applications/PS1-2.app
```

Se quiser, mantenha o ícone no Dock. Depois de instalar, esse ícone permanece o logo atual mesmo com a central encerrada. Veja [o guia dos emuladores](docs/EMULADORES.md) para configurar BIOS, bibliotecas, controle e primeira execução. No destino padrão, os emuladores ficam em:

```text
/Applications/DuckStation.app
/Applications/PCSX2.app
```

Teste primeiro um jogo diretamente no emulador. A central não configura BIOS, renderizador, memória ou mapeamento de controle automaticamente.

### Compilar manualmente, sem instalar

Para desenvolvimento ou inspeção do bundle, use:

```bash
bash build.sh
```

O script gera o ícone, copia os recursos, compila o executável nativo, aplica uma **assinatura local ad hoc** e valida o bundle. Ele não baixa emuladores nem instala a central em Aplicativos. Ao terminar, informa um caminho semelhante a `/private/tmp/ps12-build.ABC123/PS1-2.app`; use o caminho real impresso para abrir ou copiar o app manualmente. Não é necessário certificado Apple Developer para o build local; assinatura ad hoc não equivale à notarização da Apple.

O build padrão usa uma pasta temporária local para evitar metadados do Finder/iCloud que podem interferir na assinatura. `cache/`, `MakeIcon` e `AppIcon.iconset/` são gerados localmente e ignorados pelo Git. O aplicativo não é executado com `swift run`: este projeto gera um bundle macOS diretamente com `build.sh`.

## Bibliotecas e capas

As pastas padrão continuam sendo estas, fora do repositório:

```text
/Volumes/Extreme SSD/Emulacao/
├── PS1/Jogos/
└── PS2/Jogos/
```

### Escolher outra pasta, sem editar código

1. Abra **Pastas de jogos** no cabeçalho da central ou do catálogo. Também está no menu **PS1/2 → Pastas de jogos…**, com atalho **⌘,**.
2. No cartão **PS1** ou **PS2**, clique em **Escolher pasta…**. Selecione qualquer pasta legível no armazenamento interno ou em um disco externo e confirme **Usar esta pasta**. O seletor de arquivos é o nativo do macOS; use mouse/teclado nele.
3. A central salva a escolha e faz uma carga completa **somente desse console**. Aceita uma pasta por console, incluindo subpastas; não procura automaticamente o Mac inteiro. Escolha a pasta dedicada aos jogos, não a raiz de um disco.
4. Clique em **Concluir** e abra o catálogo. Depois de adicionar jogos ou capas, pressione **T / △** dentro dele para atualizar.

Cancelar o seletor mantém tudo como estava. **Restaurar padrão** volta à pasta original do `Extreme SSD` e tenta recuperar seu catálogo salvo, inclusive com o disco desconectado; se necessário, atualize com **T / △** quando ele estiver conectado.

As escolhas ficam nas preferências locais do app, separadas para PS1 e PS2, e sobrevivem ao fechamento/reabertura e à atualização do aplicativo. A central não move/copia jogos nem altera BIOS, saves, memory cards ou as configurações dos emuladores. Se quiser a mesma biblioteca listada dentro do DuckStation/PCSX2, configure a pasta também nas preferências deles. `--destination` no instalador muda apenas onde os aplicativos são instalados.

As capas são lidas de `~/Library/Application Support/DuckStation/covers` e `~/Library/Application Support/PCSX2/covers`, com alternativas junto aos jogos. Três capas frontais incluídas em `assets/Covers/PS2` têm prioridade para padronizar a apresentação. Imagens deitadas ou quadradas são rejeitadas no PS2 para evitar capas completas de frente e verso; o filtro não reconhece automaticamente toda arte incorreta.

A listagem não copia jogos. ZIP/RAR/7z não aparecem. CUE/BIN válidos são agrupados, sem listar cada faixa como um jogo. Descritores incompletos são omitidos com aviso.

Se o macOS pedir acesso ao volume externo, escolha **Permitir** para realizar uma carga completa ou abrir um jogo. Enquanto o aviso aguarda uma resposta, pode aparecer “Carregando catálogo…”. Nenhuma permissão é contornada automaticamente.

## Controles

| Ação | Teclado | Controle compatível |
|---|---|---|
| Selecionar console/jogo | Setas | Direcional ou analógico esquerdo |
| Confirmar/abrir | Enter | X |
| Voltar/cancelar abertura | Esc | Círculo |
| Tela cheia/janela | F | Quadrado |
| Listar jogos do console / atualizar catálogo | T | Triângulo |
| Voltar ao menu da central | — | Botão PlayStation do DualSense |
| Configurar pastas de jogos | ⌘, ou botão no cabeçalho | Abra pelo botão; depois direcional/analógico escolhe PS1/PS2, X abre o seletor e Círculo volta |
| Encerrar a central | ⌘Q | — |

No mouse, passar sobre PS1/PS2 pré-seleciona o console; clicar inicia a abertura. A prévia do console pré-selecionado continua mesmo sem hover e também acompanha as setas do teclado ou controle. É silenciosa, usa os GIFs locais e não faz downloads. O mapeamento do controle dentro dos jogos continua sendo responsabilidade de cada emulador.

O analógico esquerdo seleciona em quatro direções. No menu, cada inclinação troca o console uma vez: solte ao centro antes de repetir na mesma direção. No catálogo, esquerda/direita move um jogo e cima/baixo move uma linha; segurar repete após 450 ms, com intervalo de 140 ms. A zona neutra e a estabilização de diagonais evitam movimentos por pequenas oscilações. Após trocar de tela, usar um botão ou voltar de outro aplicativo, solte o analógico ao centro para rearmar. O analógico direito não navega.

X, Círculo, Quadrado, Triângulo, direcional e analógico só agem com a central em foco. A exceção é o botão PlayStation do DualSense: ele traz a janela da central para a frente e abre o menu dos consoles, saindo do catálogo, das pastas de jogos ou da abertura. DuckStation e PCSX2 continuam abertos. O mapeamento do controle dentro dos jogos continua sendo responsabilidade de cada emulador. Em alguns sistemas o macOS consome o botão PlayStation e ele não chega ao aplicativo.

## Sessões e limites

- “Ligado” significa que o aplicativo do emulador está aberto; não garante que um jogo esteja rodando.
- O contador mede o tempo desde a abertura do emulador, incluindo pausas e tempo parado no menu.
- “Jogo carregado” é inferido a partir de imagens de disco abertas pelo processo. A central não distingue execução de pausa e não usa logs antigos para adivinhar.
- Imagens fora da biblioteca, arquivos integralmente em memória ou acesso negado podem impedir a identificação.
- Trocar de jogo com outra sessão carregada é bloqueado. Finalize a sessão no próprio emulador.
- Se DuckStation estiver aberto sem jogo identificado, a central pede confirmação para encerrá-lo normalmente e reabri-lo com o jogo escolhido. Nunca força a saída.
- Fechar a central não salva partidas e não encerra os emuladores automaticamente.

## Cache de jogos e capas

O cache fica em `~/Library/Caches/local.rafael.centraldejogos/`, no armazenamento interno do Mac. Guarda apenas o índice dos jogos e miniaturas de capas; não copia ISOs, BINs, BIOS ou saves e não usa espaço adicional no SSD dos jogos.

- `Catalog/`: salva a **última carga completa bem-sucedida**, com títulos, caminhos, capas e associação dos discos CUE/CCD/M3U. Abrir, fechar e reabrir o catálogo apenas reutiliza esse índice, da memória ou do disco local, **sem varrer nem conferir metadados dos jogos no SSD**. Mantém até oito índices em memória e até oito arquivos / 16 MiB em disco (máximo de 4 MiB por arquivo).
- Ao iniciar a central, ambos os catálogos são restaurados do cache local, mesmo sem o SSD. Se ainda não houver cache salvo, essa restauração não faz uma varredura; será necessário conectar o SSD e abrir/atualizar o catálogo uma primeira vez. Não apague o cache se quiser manter a consulta offline.
- Uma carga completa acontece na primeira abertura sem cache válido, ao confirmar uma pasta diferente ou ao pressionar **△ / T dentro do catálogo**. Jogos adicionados/removidos e capas substituídas só aparecem após essa atualização. Voltar ao app, conectar ou desconectar o SSD não dispara uma varredura. Se a atualização falhar, a última lista salva daquela biblioteca continua visível com um aviso.
- O índice é separado por **console e caminho da biblioteca**. Mudar de pasta remove imediatamente a lista anterior da tela; uma tarefa antiga não pode recolocá-la. Voltar à biblioteca padrão pode recuperar seu cache, sujeito aos limites acima. Nenhuma escolha apaga arquivos de jogos ou de capas.
- `Thumbnails/`: miniaturas de 320 px para o catálogo e 108 px para o menu, associadas à mesma carga salva. Os acertos em RAM/disco não consultam a capa original. O catálogo prepara as duas resoluções em segundo plano; se uma miniatura ainda não existir ou tiver sido removida pelo limite do cache, tenta ler apenas a capa correspondente, sem reler os jogos. Sem acesso à capa, mostra um espaço reservado.
- O cache de capas tem orçamento de 32 MiB de imagens retidas em memória e 64 MiB / 256 arquivos em disco. Views visíveis podem manter imagens adicionais; esse orçamento não é o consumo total do app. A limpeza automática remove apenas arquivos deste cache.
- Com o disco externo desconectado, é possível consultar a última lista e as capas já salvas. **Somente ao escolher “Abrir jogo”** a central valida os arquivos selecionados. Se o volume estiver desconectado, exibe um aviso com seu nome e o título do jogo, sem iniciar o emulador. X/Enter ou Círculo/Esc fecha o aviso e mantém o catálogo. Após reconectar, escolha o jogo novamente: não existe abertura automática. Jogos em uma pasta local não dependem do SSD de outro console. O cache não contém os jogos; arquivos removidos ou sem permissão recebem mensagem própria.
- Arquivos de cache corrompidos ou indisponíveis são ignorados/recriados. Se precisar limpar manualmente, feche a central e mova apenas essa pasta de cache para o Lixo; nunca apague as pastas de jogos, BIOS ou saves.

Essa otimização é da central e do catálogo: não altera a velocidade/FPS, configurações, saves ou funcionamento interno do DuckStation e do PCSX2.

## Testes

Na raiz do projeto:

```bash
bash tests/run-monitor-tests.sh
bash tests/run-catalog-tests.sh
bash tests/run-hover-animation-tests.sh
bash tests/run-now-playing-tests.sh
bash tests/run-launcher-preview-tests.sh
bash tests/run-controller-input-tests.sh
bash tests/run-launch-check-tests.sh
bash tests/run-cache-tests.sh
bash tests/run-cover-cache-tests.sh
bash tests/run-installer-tests.sh
bash tests/run-library-settings-tests.sh
bash tests/run-responsive-layout-tests.sh
```

Esses testes usam fixtures locais e os GIFs incluídos; não precisam baixar jogos ou BIOS, nem iniciam emuladores. As suítes cobrem o monitor de sessões, animações, catálogo, snapshots sem varredura, consulta offline, falha de atualização sem perder a lista salva, validação do jogo escolhido, correspondência exata entre o disco aberto e a capa (incluindo CUE/CCD/M3U) e seis layouts compactos de miniatura. O teste de layout gera uma prévia temporária com dados fictícios para inspeção visual.

Os testes de pastas usam preferências e diretórios temporários: cobrem persistência, validação, restauração offline, isolamento entre consoles/bibliotecas e resultados atrasados de cargas anteriores. Os testes do instalador usam cenários isolados, sem instalar emuladores reais ou substituir aplicativos em `/Applications`. O diagnóstico `bash install.sh --check` pode ser usado para conferir os pré-requisitos da sua máquina antes de instalar.

Opcional, somente na máquina com os emuladores/SSD configurados: inventário de leitura das bibliotecas reais:

```bash
bash tests/run-catalog-tests.sh --installed --front-covers "$PWD/assets/Covers"
```

Isso lista caminhos dos jogos no Terminal; não compartilhe a saída se contiver dados que não quer divulgar. Os testes não comprovam jogabilidade de cada título nem substituem um teste físico do controle.

Para comparar leitura completa, cache em memória e cache persistente com a biblioteca instalada:

```bash
bash tests/run-cache-benchmark.sh
```

O benchmark não inicia emuladores nem altera jogos; grava seu cache de teste numa pasta temporária, removida ao terminar. Os tempos variam com o SSD, a biblioteca e o cache do próprio macOS.

Medição local da versão 4.6 em 29/09/2026 (consulta do catálogo, não tempo total da interface; média de cinco consultas em memória):

| Biblioteca | Leitura completa | Cache em memória | Cache após recriar o carregador |
|---|---:|---:|---:|
| PS1, 5 jogos | 885 ms | 0,3 ms | 1,9 ms |
| PS2, 14 jogos | 416 ms | 0,5 ms | 2,2 ms |

As 19 capas, salvas nas duas resoluções (38 miniaturas), ocuparam 3,3 MB no cache de teste em disco e aproximadamente 6,7 MB decodificadas no cache de memória. As consultas em memória e a reabertura pelo cache persistente fizeram **zero novas varreduras e zero verificações de metadados da biblioteca**. A primeira leitura ainda monta o índice; o ganho é no reaproveitamento posterior. Nenhum jogo foi copiado.

## Estrutura

```text
PS12.swift                 Menu, janelas, estado e abertura de emuladores
ResponsiveLayout.swift     Escala da interface conforme a janela e a tela
ControllerInput.swift      Entrada pelo controle, inclusive o botão PlayStation
EmulatorMonitor.swift      Monitor de processos e jogo carregado
GameCatalog.swift          Leitura das bibliotecas e seleção de capas
GameLaunchCheck.swift      Validação apenas do jogo escolhido e seus arquivos de disco
StorageNoticeView.swift    Aviso de disco desconectado com visual inspirado no console
LibrarySettings.swift      Pastas PS1/PS2 persistentes e metadados do volume
LibrarySettingsView.swift  Painel de escolha/restauração das bibliotecas
CatalogCache.swift         Última carga completa persistente e consultas sem varrer o SSD
CoverImageCache.swift      Miniaturas compartilhadas com limites de RAM/disco
GameCatalogView.swift      Interface do catálogo
NowPlayingGameView.swift   Miniatura assíncrona do jogo carregado
StartupAnimation.swift     GIF antes de abrir o emulador
HoverAnimation.swift       Prévia decorativa em loop
MakeIcon.swift             Geração do ícone do app
Info.plist                 Identidade e versão do bundle
build.sh                   Compilação e assinatura local
install.sh                 Instalação da central e dependências oficiais ausentes
Instalar.command           Atalho do Finder para o instalador no Terminal
scripts/installer-lib.sh   Downloads oficiais, validação e publicação dos apps
scripts/MoveApp.swift      Renomeação exclusiva e segura durante a instalação
assets/                    Logo, fotos, GIFs e três capas frontais
tests/                     Testes automatizados
docs/EMULADORES.md         Downloads e configuração inicial
Creditos.txt               Fontes e atribuição dos recursos visuais
```

## Créditos e uso

Projeto pessoal, sem vínculo oficial com Sony, DuckStation ou PCSX2. Os recursos de terceiros mantêm seus respectivos direitos; manter o repositório privado não altera esses direitos. Veja [Creditos.txt](Creditos.txt) para a origem dos controles, logo, GIFs e capas. Não foi atribuída uma licença aberta de redistribuição aos recursos de terceiros.

Não inclua ROMs, BIOS, saves, credenciais, backups pessoais ou builds dos emuladores neste repositório. O `.gitignore` ajuda a evitar inclusões acidentais, mas não substitui revisar os arquivos antes de um commit.

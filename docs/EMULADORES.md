# Instalar DuckStation e PCSX2 no macOS

O PS1/2 deste repositório é somente a central de abertura e catálogo. DuckStation e PCSX2 são aplicativos independentes. O instalador baixa as dependências oficiais ausentes, mas você ainda precisa fornecer BIOS/jogos e concluir a configuração de cada emulador. Links e requisitos consultados em **29/09/2026**; confira as fontes oficiais ao atualizar, pois os pacotes e requisitos podem mudar.

## Caminho recomendado: usar o instalador da central

Depois de clonar o repositório, abra o Terminal na pasta `ps1-2-emulator`:

```bash
bash install.sh --check
bash install.sh
```

O primeiro comando somente diagnostica os pré-requisitos, sem baixar, compilar ou modificar arquivos. O segundo pede confirmação, compila a central e baixa **somente os emuladores que não encontrar**. Também pode dar duplo clique em `Instalar.command` no Finder para executar a instalação no Terminal.

- Destino padrão: `/Applications`. Para instalar na pasta pessoal, primeiro execute `mkdir -p "$HOME/Applications"` e depois `bash install.sh --destination "$HOME/Applications"`.
- Fontes: release `latest` oficial de `stenzek/duckstation` e release estável mais recente de `PCSX2/pcsx2`, via API do GitHub. O instalador confere o SHA-256 fornecido pela API, bundle ID e assinatura antes de instalar; não ignora falhas de verificação.
- Apps com nome padrão e identidade esperada em `/Applications`, `~/Applications` ou no destino escolhido são preservados. O script não atualiza emuladores existentes nem altera suas configurações.
- Não instala Homebrew, não usa `sudo`, não reinicia o Mac, não aceita licenças/Rosetta, não baixa jogos/BIOS e não remove quarentena dos downloads. Também não abre aplicativos por você.

Depois de instalar, abra **DuckStation** e **PCSX2** pelo Finder, conclua os assistentes abaixo e teste um jogo em cada um. Para instruções de clone, requisitos da central, opções e backup da versão anterior, consulte [Instalação detalhada no README](../README.md#instalação-detalhada).

Se preferir instalar os emuladores manualmente, use as fontes oficiais abaixo e rode `bash install.sh --no-emulators` para instalar somente a central.

## PS1 — DuckStation

### Download manual (pule se o instalador já instalou)

1. Acesse o [site oficial](https://www.duckstation.org/) ou a [distribuição estável oficial no GitHub](https://github.com/stenzek/duckstation/releases/tag/latest).
2. Baixe `duckstation-mac-release.zip` para macOS.
3. Extraia o ZIP no Finder e mova **DuckStation.app** para **Aplicativos**, ficando em `/Applications/DuckStation.app`.

### Primeira configuração (também necessária após o instalador)

1. Abra o emulador uma vez e conclua o assistente. Indique sua BIOS e a pasta da biblioteca PS1.
2. Em configurações de controles, selecione/mapeie seu controle. O mapeamento dentro do DuckStation é separado dos botões da central.
3. Abra um jogo diretamente no DuckStation para conferir a configuração; depois utilize o catálogo da central.

A distribuição documentada é universal, para Intel e Apple Silicon, e exige **macOS Ventura 13.3 ou posterior**. A BIOS não acompanha o emulador e deve ser extraída do próprio console. BIN/CUE, CHD, CCD e PBP não criptografado estão entre os formatos documentados. Preserve todos os arquivos associados de um mesmo disco. [Instalação macOS e requisitos no README oficial](https://github.com/stenzek/duckstation#macos).

O mínimo do DuckStation não muda o mínimo da central: o build deste repositório exige **macOS 14+ e Apple Silicon**.

## PS2 — PCSX2

### Download manual (pule se o instalador já instalou)

1. Abra a [página oficial de downloads](https://pcsx2.net/downloads/) e escolha **macOS**. Para começar, prefira **Stable**; Nightly recebe mudanças mais frequentes.
2. Extraia o arquivo `.tar.xz` pelo Finder e mova o app para **Aplicativos**.
3. Se o pacote vier com a versão no nome, use **PCSX2.app** para corresponder a `/Applications/PCSX2.app`, que é o caminho esperado pela central.

### Primeira configuração (também necessária após o instalador)

1. Abra o PCSX2 e conclua o assistente: pasta da BIOS, biblioteca PS2 e controles.
2. Se o macOS solicitar **Rosetta**, leia e aceite manualmente o instalador apresentado pelo próprio sistema, caso concorde. O script deste repositório não faz essa aceitação por você.
3. Teste um jogo diretamente no PCSX2 antes de usar a central.

Esses passos seguem o [guia oficial de instalação macOS](https://pcsx2.net/docs/setup/running/). A documentação lista **macOS 11 e 8 GB de RAM como mínimos**; níveis superiores indicam 16 GB. A versão documentada para Macs M-series utiliza Rosetta 2. O desempenho depende do jogo, da resolução e das configurações: atender ao mínimo não garante velocidade total em todos os títulos. [Requisitos oficiais do PCSX2](https://pcsx2.net/docs/setup/requirements/).

Rosetta é um componente da Apple para executar aplicativos Intel em Apple Silicon; não é necessária para o binário ARM64 da central. Confira a [orientação atual da Apple sobre Rosetta](https://support.apple.com/102527) antes de atualizar o sistema, especialmente em versões futuras do macOS.

## BIOS e jogos

Não há jogos ou BIOS neste repositório. Utilize arquivos que você tenha autorização para usar, como BIOS extraída do próprio console, cópias dos seus discos quando permitido e homebrew autorizado.

- PS1: siga as instruções sobre BIOS no [projeto oficial DuckStation](https://github.com/stenzek/duckstation).
- PS2: siga o [guia oficial de extração da BIOS](https://pcsx2.net/docs/setup/bios/) e o [guia de cópia dos discos](https://pcsx2.net/docs/setup/discs/), que inclui informações para CDs/DVDs no macOS.

Não é necessário formatar o SSD para instalar a central. Mantenha BIOS, memory cards, saves e jogos fora da pasta do Git. Nem a central nem o instalador baixam ou fornecem bibliotecas prontas. O instalador não altera esses arquivos, mas o backup da central também não os inclui: mantenha seu próprio backup das partidas.

## Pastas e formatos do catálogo

As pastas padrão são:

```text
/Volumes/Extreme SSD/Emulacao/PS1/Jogos
/Volumes/Extreme SSD/Emulacao/PS2/Jogos
```

Para manter essas pastas, conecte o SSD e permita o acesso quando o macOS solicitar. Para usar outro local, abra **Pastas de jogos** na central (ou **⌘,**) e escolha uma pasta para PS1 e outra para PS2, no Mac ou em qualquer disco externo. A escolha é salva neste Mac e carrega apenas o catálogo daquele console, incluindo subpastas. Não é preciso editar código nem reinstalar. **Restaurar padrão** volta ao caminho original acima, inclusive offline. Veja [Bibliotecas e capas no README](../README.md#bibliotecas-e-capas).

`--destination` muda o destino dos aplicativos, não a pasta dos jogos. A central lê os arquivos onde estão, sem duplicar sua biblioteca, e não altera a biblioteca configurada dentro do DuckStation/PCSX2. Configure também os emuladores se quiser que suas próprias listas usem a mesma pasta.

Em uma nova máquina, o cache começa vazio; clonar o Git não importa o catálogo de outro Mac. Com a pasta acessível, selecione PS1 ou PS2 e pressione **T / △** para abrir o catálogo. Dentro do catálogo, pressione **T / △** para atualizar a lista e as capas. Só depois da primeira carga bem-sucedida haverá uma lista local para consulta offline. Para jogar, os arquivos precisam estar acessíveis; jogos no disco interno não precisam de SSD externo.

| Console | Extensões consideradas pelo catálogo da central |
|---|---|
| PS1 | `.cue`, `.ccd`, `.chd`, `.iso`, `.pbp`, `.img`, `.bin`, `.m3u` |
| PS2 | `.iso`, `.chd`, `.cso`, `.zso`, `.gz`, `.bin`, `.img`, `.mdf` |

Essa tabela descreve o scanner da central, não uma garantia de compatibilidade do emulador. Aparecer no catálogo não comprova integridade ou jogabilidade.

- ZIP, RAR e 7z precisam ser extraídos antes e não aparecem como jogos.
- CUE/CCD/M3U só entram quando seus componentes existem dentro da biblioteca.
- Para PS1, mantenha CUE e faixas BIN juntos; use a entrada do disco/playlist, não uma faixa de áudio isolada. Uma pasta só com faixas BIN, sem CUE, aparece como um jogo: a faixa 1.
- Para PS2, o PCSX2 não lê CUE/TOC diretamente: consulte o [guia oficial de discos](https://pcsx2.net/docs/setup/discs/) para os arquivos corretos de cada método de cópia.
- Para a capa, coloque um PNG, JPG ou WebP na pasta do jogo. O nome `capa` serve, e a única imagem da pasta também. Se o disco estiver em `GAME`, a imagem pode ficar na pasta acima. **Atualizar**, **R** ou **R2 + L2** relê jogos e capas. Pastas como Futebol ou Luta, criadas no catálogo, só organizam a lista: nenhum arquivo é movido.

## Problemas comuns

- **`swiftc`/SDK não encontrado:** execute `xcode-select --install`, conclua a instalação e rode `bash install.sh --check` novamente.
- **Sem permissão para instalar em `/Applications`:** use a pasta pessoal com `--destination "$HOME/Applications"`, depois de criá-la. Não use `sudo` como atalho.
- **Falha de download, SHA-256 ou assinatura:** não contorne a verificação. Confira sua conexão, consulte a release oficial e tente novamente; uma mudança no pacote pode exigir atualizar o instalador. Em caso de limite da API do GitHub, aguarde ou faça a instalação manual pela fonte oficial.
- **“Não encontrei DuckStation/PCSX2”:** confira nomes e caminhos em `/Applications` ou `~/Applications`. Abra cada emulador uma vez pelo Finder; a central prioriza o caminho padrão e também procura o app pelo bundle ID registrado no macOS.
- **“Lendo jogos e capas…” por muito tempo:** confira se o macOS está aguardando uma resposta ao pedido de acesso ao SSD.
- **Biblioteca vazia ou desatualizada:** confira o caminho em **Pastas de jogos**, o acesso ao disco e se os jogos já foram extraídos para essa pasta. Se moveu os jogos ou renomeou o volume, escolha a pasta novamente. Abra o catálogo e pressione **T / △** para uma carga completa. Em uma máquina nova, não existe cache anterior para mostrar offline.
- **Jogo não inicia diretamente no emulador:** revise BIOS, arquivos do disco e configuração no próprio emulador primeiro. A central não corrige esses problemas.
- **Controle funciona na central, mas não no jogo:** configure-o separadamente dentro do DuckStation ou PCSX2.
- **Aviso de segurança inesperado:** confirme a origem do arquivo. Não desative proteções do macOS nem remova avisos de arquivos de origem desconhecida como solução genérica.

Para compilar/instalar a central e executar os testes, volte ao [README](../README.md).

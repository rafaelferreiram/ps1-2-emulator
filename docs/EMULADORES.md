# Instalar DuckStation e PCSX2 no macOS

O PS1/2 deste repositório é somente a central de abertura e catálogo. Os emuladores são projetos independentes, instalados separadamente. Links e requisitos consultados em **29/09/2026**; confira as fontes oficiais ao atualizar, pois os pacotes e requisitos podem mudar.

## PS1 — DuckStation

1. Acesse o [site oficial](https://www.duckstation.org/) ou a [distribuição estável oficial no GitHub](https://github.com/stenzek/duckstation/releases/tag/latest).
2. Baixe `duckstation-mac-release.zip` para macOS.
3. Extraia o ZIP no Finder e mova **DuckStation.app** para **Aplicativos**, ficando em `/Applications/DuckStation.app`.
4. Abra o emulador uma vez e conclua o assistente. Indique sua BIOS e a pasta da biblioteca PS1.
5. Em configurações de controles, selecione/mapeie seu controle. O mapeamento dentro do DuckStation é separado dos botões da central.
6. Abra um jogo diretamente no DuckStation para conferir a configuração; depois utilize o catálogo da central.

A distribuição documentada é universal, para Intel e Apple Silicon, e exige **macOS Ventura 13.3 ou posterior**. A BIOS não acompanha o emulador e deve ser extraída do próprio console. BIN/CUE, CHD, CCD e PBP não criptografado estão entre os formatos documentados. Preserve todos os arquivos associados de um mesmo disco. [Instalação macOS e requisitos no README oficial](https://github.com/stenzek/duckstation#macos).

O mínimo do DuckStation não muda o mínimo da central: o build deste repositório exige **macOS 14+ e Apple Silicon**.

## PS2 — PCSX2

1. Abra a [página oficial de downloads](https://pcsx2.net/downloads/) e escolha **macOS**. Para começar, prefira **Stable**; Nightly recebe mudanças mais frequentes.
2. Extraia o arquivo `.tar.xz` pelo Finder e mova o app para **Aplicativos**.
3. Se o pacote vier com a versão no nome, use **PCSX2.app** para corresponder a `/Applications/PCSX2.app`, que é o caminho esperado pela central.
4. Abra o PCSX2 e conclua o assistente: pasta da BIOS, biblioteca PS2 e controles. Se o macOS solicitar **Rosetta**, siga o instalador apresentado pelo próprio sistema.
5. Teste um jogo diretamente no PCSX2 antes de usar a central.

Esses passos seguem o [guia oficial de instalação macOS](https://pcsx2.net/docs/setup/running/). A documentação lista **macOS 11 e 8 GB de RAM como mínimos**; níveis superiores indicam 16 GB. A versão documentada para Macs M-series utiliza Rosetta 2. O desempenho depende do jogo, da resolução e das configurações: atender ao mínimo não garante velocidade total em todos os títulos. [Requisitos oficiais do PCSX2](https://pcsx2.net/docs/setup/requirements/).

Rosetta é um componente da Apple para executar aplicativos Intel em Apple Silicon; não é necessária para o binário ARM64 da central. Confira a [orientação atual da Apple sobre Rosetta](https://support.apple.com/102527) antes de atualizar o sistema, especialmente em versões futuras do macOS.

## BIOS e jogos

Não há jogos ou BIOS neste repositório. Utilize arquivos que você tenha autorização para usar, como BIOS extraída do próprio console, cópias dos seus discos quando permitido e homebrew autorizado.

- PS1: siga as instruções sobre BIOS no [projeto oficial DuckStation](https://github.com/stenzek/duckstation).
- PS2: siga o [guia oficial de extração da BIOS](https://pcsx2.net/docs/setup/bios/) e o [guia de cópia dos discos](https://pcsx2.net/docs/setup/discs/), que inclui informações para CDs/DVDs no macOS.

Não é necessário formatar o SSD para instalar a central. Mantenha BIOS, memory cards, saves e jogos fora da pasta do Git. A central não baixa nem fornece bibliotecas prontas.

## Pastas e formatos do catálogo

A configuração atual espera:

```text
/Volumes/Extreme SSD/Emulacao/PS1/Jogos
/Volumes/Extreme SSD/Emulacao/PS2/Jogos
```

Conecte o SSD e permita o acesso ao volume quando o macOS solicitar. Para mudar esses caminhos, veja [Bibliotecas e capas no README](../README.md#bibliotecas-e-capas). A central lê os arquivos onde estão, sem duplicar sua biblioteca no disco interno.

| Console | Extensões consideradas pelo catálogo da central |
|---|---|
| PS1 | `.cue`, `.ccd`, `.chd`, `.iso`, `.pbp`, `.img`, `.bin`, `.m3u` |
| PS2 | `.iso`, `.chd`, `.cso`, `.zso`, `.gz`, `.bin`, `.img`, `.mdf` |

Essa tabela descreve o scanner da central, não uma garantia de compatibilidade do emulador. Aparecer no catálogo não comprova integridade ou jogabilidade.

- ZIP, RAR e 7z precisam ser extraídos antes e não aparecem como jogos.
- CUE/CCD/M3U só entram quando seus componentes existem dentro da biblioteca.
- Para PS1, mantenha CUE e faixas BIN juntos; use a entrada do disco/playlist, não uma faixa de áudio isolada.
- Para PS2, o PCSX2 não lê CUE/TOC diretamente: consulte o [guia oficial de discos](https://pcsx2.net/docs/setup/discs/) para os arquivos corretos de cada método de cópia.

## Problemas comuns

- **“Não encontrei DuckStation/PCSX2”:** confira os nomes e caminhos em `/Applications`.
- **“Lendo jogos e capas…” por muito tempo:** confira se o macOS está aguardando uma resposta ao pedido de acesso ao SSD.
- **Biblioteca vazia:** confira se o volume está conectado, se o nome é `Extreme SSD` e se os jogos já foram extraídos para as pastas configuradas.
- **Jogo não inicia diretamente no emulador:** revise BIOS, arquivos do disco e configuração no próprio emulador primeiro. A central não corrige esses problemas.
- **Controle funciona na central, mas não no jogo:** configure-o separadamente dentro do DuckStation ou PCSX2.
- **Aviso de segurança inesperado:** confirme a origem do arquivo. Não desative proteções do macOS nem remova avisos de arquivos de origem desconhecida como solução genérica.

Para compilar/instalar a central e executar os testes, volte ao [README](../README.md).

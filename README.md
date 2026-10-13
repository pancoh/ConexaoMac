<p align="center">
  <img src="Assets/readme-icon.png" alt="Ícone do Conexão" width="112" height="112">
</p>

<h1 align="center">Conexão</h1>

<p align="center">Monitoramento da internet no Mac, com histórico local e interface nativa.</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-F05138?style=flat&amp;logo=swift&amp;logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/AppKit-263746?style=flat&amp;logo=apple&amp;logoColor=white" alt="AppKit">
  <img src="https://img.shields.io/badge/SQLite-003B57?style=flat&amp;logo=sqlite&amp;logoColor=white" alt="SQLite">
  <img src="https://img.shields.io/badge/macOS-13%2B-172B3A?style=flat&amp;logo=apple&amp;logoColor=white" alt="macOS 13 ou superior">
</p>

<p align="center">
  <a href="https://github.com/pancoh/ConexaoMac/actions/workflows/release.yml"><img src="https://github.com/pancoh/ConexaoMac/actions/workflows/release.yml/badge.svg" alt="Status dos testes e publicação"></a>
  <a href="https://github.com/pancoh/ConexaoMac/releases/latest"><img src="https://img.shields.io/github/v/release/pancoh/ConexaoMac?style=flat&amp;label=vers%C3%A3o&amp;color=167D8D" alt="Versão publicada"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/pancoh/ConexaoMac/releases/latest/download/ConexaoMac.zip">Baixar para Mac</a></strong>
  &nbsp;·&nbsp;
  <a href="https://github.com/pancoh/ConexaoMac/releases">Todas as versões</a>
  &nbsp;·&nbsp;
  <a href="#como-atualizar">Como atualizar</a>
</p>

---

## Instalação

Requisitos: **Mac com Apple Silicon (M1 ou posterior) e macOS 13 ou superior**. O pacote atual não é compatível com Macs Intel.

1. Clique em **Baixar para Mac**. Se o download já aparecer como `Conexão.app`, ele está pronto para instalar. Se aparecer como `ConexaoMac.zip`, abra o arquivo para descompactar.
2. Arraste `Conexão.app` para **Aplicativos**.
3. Abra o aplicativo. O ícone aparece na barra de menus.

O aplicativo tem assinatura local e ainda não foi notarizado pela Apple. Se houver bloqueio e você confirmar a origem do arquivo, consulte **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**. [Orientação da Apple](https://support.apple.com/pt-br/102445).

## Como atualizar

A atualização é manual. O aplicativo não baixa nem instala versões novas automaticamente.

1. Consulte **Sobre** no resumo compacto para verificar sua versão.
2. [Baixe a versão mais recente](https://github.com/pancoh/ConexaoMac/releases/latest/download/ConexaoMac.zip). Se receber um ZIP, abra o arquivo para obter `Conexão.app`.
3. Use **Opções → Encerrar Conexão** antes de substituir o aplicativo.
4. Arraste a nova cópia para **Aplicativos**, confirme a substituição e abra novamente.

O histórico fica separado do aplicativo, em `~/Library/Application Support/ConexaoMac/historico.sqlite`. Substituir o aplicativo preserva os registros. Não exclua essa pasta durante a atualização.

Para receber avisos pelo GitHub, use **Watch → Custom → Releases** no repositório.

## Recursos

| Recurso | O que oferece |
|---|---|
| Conexão atual | Estado da internet e resumo compacto na barra de menus. |
| Histórico diário | Disponibilidade, quedas, sessões, testes e eventos, com retenção de 90 dias. |
| Linha do tempo | Visão do dia com agregação limitada a 288 intervalos. |
| Velocidade | Testes manuais ou automáticos pelo `networkQuality` do macOS. |
| Exportação | Três arquivos CSV, com proteção contra sobrescrita. |
| Interface nativa | AppKit, fontes do sistema e cores semânticas em claro e escuro. |

O acesso é verificado aproximadamente a cada 10 segundos, por requisições para Apple e Google. Uma resposta válida confirma acesso. Falhas podem indicar indisponibilidade ou bloqueio desses destinos. A disponibilidade considera apenas o tempo observado. Repouso, pausa e lacunas ficam separados das quedas.

Não há conta, sincronização ou servidor próprio. A verificação usa a internet, e os testes de velocidade consomem banda. A coleta não registra páginas visitadas, senhas ou conteúdo da navegação.

A tabela mostra até 200 quedas, testes ou eventos e 100 sessões por dia. Um aviso informa quando existem registros além do limite de exibição.

## Desenvolvimento

No macOS, instale as ferramentas de linha de comando do Xcode e execute:

```sh
./test.sh
./build.sh
```

O pacote gerado é `ConexaoMac.zip`. Backups, bancos, prévias com histórico real e relatórios locais de validação ficam fora do Git.

## Publicar uma nova versão

1. Faça a alteração e atualize `VERSION`, por exemplo de `1.1.3` para `1.1.4`.
2. Aumente `BUILD_NUMBER`, por exemplo de `7` para `8`.
3. Faça commit e push para `main`.

O GitHub Actions executa os testes, compila, verifica a assinatura local e publica uma Release com o ZIP e `SHA256SUMS.txt`. A Release só aparece se os testes e a compilação passarem. Confira a execução na aba **Actions**.

Uma alteração sem aumentar `VERSION` passa pela validação, mas não substitui uma Release já publicada. Isso preserva a correspondência entre versão e download. Para testar uma alteração ainda não publicada, use o artefato da execução na aba **Actions**.

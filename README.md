# ConexaoMac

Aplicativo nativo para acompanhar a conexão de internet no Mac. Usa Swift, AppKit e SQLite local.

## Download e instalação

[Baixar a versão mais recente](https://github.com/pancoh/ConexaoMac/releases/latest/download/ConexaoMac.zip) · [Ver todas as versões](https://github.com/pancoh/ConexaoMac/releases)

Requisitos: **Mac com Apple Silicon (M1 ou posterior) e macOS 13 ou superior**. O pacote atual não é compatível com Macs Intel.

1. Baixe e descompacte `ConexaoMac.zip`.
2. Arraste `Conexão.app` para **Aplicativos**.
3. Abra o aplicativo. O ícone aparece na barra de menus.

O aplicativo tem assinatura local e ainda não foi notarizado pela Apple. Se houver bloqueio e você confirmar a origem do arquivo, consulte **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**. [Orientação da Apple](https://support.apple.com/pt-br/102445).

## Como atualizar

A atualização é manual. O aplicativo não baixa nem instala versões novas automaticamente.

1. Consulte **Sobre** no resumo compacto para verificar sua versão.
2. Abra a [página da versão mais recente](https://github.com/pancoh/ConexaoMac/releases/latest) e baixe o ZIP.
3. Use **Opções → Encerrar Conexão** antes de substituir o aplicativo.
4. Arraste a nova cópia para **Aplicativos**, confirme a substituição e abra novamente.

O histórico fica separado do aplicativo, em `~/Library/Application Support/ConexaoMac/historico.sqlite`. Substituir o aplicativo preserva os registros. Não exclua essa pasta durante a atualização.

Para receber avisos pelo GitHub, use **Watch → Custom → Releases** no repositório.

## Recursos

- Estado atual da internet e resumo compacto na barra de menus.
- Histórico diário de disponibilidade, quedas, sessões, testes e eventos.
- Linha do tempo com agregação limitada a 288 intervalos.
- Testes de velocidade manuais ou automáticos pelo `networkQuality` do macOS.
- Exportação de intervalos, testes e quedas em três arquivos CSV, com proteção contra sobrescrita.
- Retenção local de 90 dias e interface com cores semânticas em claro e escuro.

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

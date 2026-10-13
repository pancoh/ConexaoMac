# Conexão

Aplicativo local para macOS 13 ou superior, em Swift e AppKit, sem dependências externas.

## Requisitos e verificação

- [x] Ícone na barra de menus e painel aberto sob demanda.
- [x] Verificação de internet a cada 10 segundos, com dois destinos independentes.
- [x] Histórico por sessão e por dia: disponibilidade, quedas, duração, interface, tráfego e testes de velocidade.
- [x] Repouso, encerramento e lacunas de execução separados do tempo sem internet.
- [x] Teste de velocidade manual e automático a cada hora, com opção de desativar.
- [x] SQLite local, consultas limitadas e exportação CSV.
- [x] Resumo compacto ao clicar no ícone, com acesso ao histórico e às opções.
- [x] Painel com destaque para conexão atual e disponibilidade do dia, detalhes expansíveis e cores semânticas.
- [x] Linha do tempo do dia com agregação limitada a 288 intervalos, consulta em streaming e descarte ao fechar a janela.
- [x] Compilação, testes dos cálculos, execução real e medição de memória.

## Regras

Uma resposta válida de pelo menos um destino confirma acesso à internet. A falha de ambos indica indisponibilidade observada, que pode incluir bloqueio dos destinos. O estado da rede do macOS distingue ausência de rede de rede sem internet. O tempo de queda tem precisão aproximada de 10 segundos, mais o tempo limite das requisições (5 segundos).

Uma sessão é um período com acesso confirmado. Mudanças de interface não encerram uma sessão se o acesso continua. Intervalos são atribuídos ao último estado observado. Lacunas superiores a 25 segundos não são contabilizadas como tempo conectado ou desconectado. Repouso e encerramento terminam a observação. Uma queda em andamento nesses momentos tem duração limitada ao período observado e é marcada como interrompida.

A disponibilidade usa somente o tempo observado. A média de capacidade é a média aritmética dos testes bem-sucedidos, acompanhada da quantidade de testes. Tráfego médio divide os bytes medidos pelo tempo conectado com contadores válidos. O painel apresenta a cobertura dessa medição. Ausência de contadores, reset, troca de interface e suspensão sem contador final produzem tráfego indisponível, sem afetar a disponibilidade. Os testes entram no tráfego total do Mac. A interface se refere ao caminho padrão informado pelo macOS; VPN e múltiplas rotas podem impedir atribuição inequívoca, exibida como outra ou múltipla.

O nome do CSV usa o dia no fuso local. Campos de tráfego indisponível ficam vazios no CSV. Falhas de leitura do SQLite devem ser informadas e não podem retornar resultados parciais como válidos. A tabela distingue falha de consulta de histórico vazio. O estado de erro é renovado por atualização, sem esconder falhas intermediárias. A exportação preserva os três arquivos existentes e prepara os CSVs antes de publicar os resultados.

O histórico completo fica em disco. O painel consulta um dia e até 200 quedas, testes ou eventos e 100 sessões. A interface informa quando existem outros registros além do limite de exibição. Retenção inicial de 90 dias. A meta de 30 MB em repouso será verificada e documentada, sem garantia antes da medição. O programa não executa captura de conteúdo, páginas visitadas ou senhas.

A linha do tempo mostra proporções de tempo com e sem internet em cada intervalo. A posição dentro de um intervalo agregado não representa a ordem exata das mudanças. O eixo usa o horário local e respeita dias de duração diferente. Os períodos restantes ficam como não observados. Cores são acompanhadas de legendas, texto acessível e detalhes ao passar o cursor.

Os elementos do painel e do resumo compacto são criados sob demanda. Ao fechar a janela ou o resumo, as referências aos elementos, às linhas da tabela e aos intervalos agregados são descartadas. O monitoramento continua em modos comuns do run loop, inclusive durante a interação com menus. Não há animações contínuas nem novas dependências.

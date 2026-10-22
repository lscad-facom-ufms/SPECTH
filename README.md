# SPECTH: Script de Plotagem Educacional para Contadores de Hardware

![Bash](https://img.shields.io/badge/Script-Bash-4EAA25?style=flat-square&logo=gnu-bash&logoColor=white)
![Python](https://img.shields.io/badge/Gráficos-Python-3776AB?style=flat-square&logo=python&logoColor=white)
![Linux](https://img.shields.io/badge/OS-Linux-FCC624?style=flat-square&logo=linux&logoColor=black)
![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg?style=flat-square)

O **SPECTH** é uma ferramenta educacional desenvolvida para abstrair a complexidade do utilitário Linux `perf`. Ele automatiza a execução de múltiplos executáveis em diferentes linguagens de programação, extrai contadores de desempenho de hardware (HPCs) e gera relatórios gráficos com cálculos estatísticos de forma totalmente automatizada.

O projeto foi concebido para mitigar a barreira de entrada operacional no ensino de Arquitetura de Computadores, permitindo que estudantes e professores concentrem-se exclusivamente na análise do impacto do código-fonte sobre os recursos da CPU.

## Diferenciais e Funcionalidades

Em contraste com o uso nativo do `perf`, o SPECTH introduz recursos otimizados para o ambiente educacional e de pesquisa:

* **Extração Automatizada em Lote (*Batch*):** Dispensa a configuração manual de *flags* para cada executável. O script varre pastas e avalia múltiplos algoritmos simultaneamente.
* **Saída Gráfica Vetorizada:** Substitui os logs textuais densos do `perf` por relatórios gráficos em PDF limpos e prontos para análise comparativa.
* **Tratamento Estatístico Integrado:** Calcula automaticamente as médias e insere barras de Desvio Padrão diretamente nos gráficos, a partir de *N* repetições.
* **Suporte Inteligente a Processadores Híbridos:** Identifica a topologia do hardware e separa automaticamente os resultados de métricas entre **P-Cores** (desempenho) e **E-Cores** (eficiência).
* **Sinalização Didática de Multiplexação:** Traduz a ausência de registradores físicos e limitações de hardware (geralmente reportadas como `<not counted>` ou `<not supported>`) em hachuras visuais explícitas rotuladas como **N/C** ou **N/S**, evitando interpretações errôneas pelos alunos.

## Pré-requisitos

Para executar o SPECTH, o sistema Linux necessita das seguintes dependências:
* `perf` (subsistema oficial do kernel Linux para acesso à PMU)
* Privilégios de superusuário (`sudo`) para coleta de métricas físicas
* `python3`
* Biblioteca `matplotlib` (para a renderização dos gráficos em PDF)

## Como Usar

1. Clone o repositório:
   ```bash
   git clone https://github.com/lscad-facom-ufms/SPECTH.git
   cd SPECTH
   chmod +x benchmark.sh

2. Organize os executáveis que deseja avaliar dentro de um diretório (ex: `Sorts/`).
3. Execute o script apontando para o diretório alvo:
```bash
# Executar coletando todos os eventos disponíveis com 10 repetições (padrão)
./benchmark.sh --all Sorts/

# Executar coletando apenas métricas de cache e branches com 50 repetições
./benchmark.sh --cache --branches --run 50 Sorts/
```

### Opções de Linha de Comando

* `--cache`: Mede eventos de cache L1 e LLC.
* `--branches`: Mede predições e falhas de desvios (*Branch*).
* `--all`: Mede todos os eventos de hardware disponíveis.
* `--plot-only`: Apenas gera os gráficos em PDF a partir de arquivos `.txt` já existentes na pasta, pulando a etapa de execução.
* `-r` ou `--run N`: Define a quantidade de execuções do `perf` para cálculo de média e desvio padrão (Padrão: 10).

> **Dica para CPUs Híbridas:** Caso deseje restringir a execução a um único tipo de núcleo, utilize o utilitário `taskset` nativo do Linux:
> `taskset --cpu-list 1 ./benchmark.sh --all Sorts/`

## 📝 Licença

Este projeto é disponibilizado sob a licença [GNU AGPL v3](https://www.google.com/search?q=LICENSE) - veja o arquivo LICENSE para mais detalhes. O uso, modificação e distribuição são livres, desde que os projetos derivados mantenham a mesma licença aberta.

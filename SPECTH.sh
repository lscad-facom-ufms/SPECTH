#!/bin/bash
 '
SPECTH
Copyright (C) 2026 Universidade Federal de Mato Grosso do Sul

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
'
#Configuração
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
NOME_PASTA="resultados" 

ALVOS=()
APENAS_GRAFICOS=false
MEDIR_CACHE=false
MEDIR_BRANCHES=false
MEDIR_TUDO=false
NUM_RUNS=10 #Default de 10 runs

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --cache) MEDIR_CACHE=true ;;
        --branches) MEDIR_BRANCHES=true ;;
        --all) MEDIR_TUDO=true ;;
        --plot-only) APENAS_GRAFICOS=true ;;
        -r|--run)
            if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                NUM_RUNS="$2"
                shift 
            else
                echo "[ERRO] A flag -r ou --run requer um número inteiro como argumento."
                exit 1
            fi
            ;;
        -h|--help)
            echo "Uso: ./benchmark.sh [OPÇÕES] [DIRETÓRIOS...]"
            echo "Opções:"
            echo "  --cache      Mede eventos de L1 e LLC Cache"
            echo "  --branches   Mede predições e falhas de Branch"
            echo "  --all        Mede todos os eventos disponíveis"
            echo "  --plot-only  Apenas gera gráficos a partir de arquivos .txt existentes na pasta"
            echo "  -r, --run N Define a quantidade de execuções do perf (default: 10)"
            echo ""
            echo "Exemplos:"
            echo "  Rodar testes: ./benchmark.sh --all -r 50 Bubble"
            echo "  Apenas plotar: ./benchmark.sh --plot-only resultados_20260226_125343"
            echo "Caso seu processador tenha núcleos híbridos, experimente usar taskset."
            echo "Exemplo: taskset --cpu-list 1 ./benchmark.sh --all Bubble"
            exit 0
            ;;
        -*)
            echo "[ERRO] Flag desconhecida: $1. Se precisar de ajuda utilize -h ou --help."
            exit 1
            ;;
        *)
            ALVOS+=("$1")
            ;;
    esac
    shift 
done

#Checagem de dependencias
check_dependencies() {
    echo "=== Verificando Dependências ==="

    if [ "$APENAS_GRAFICOS" = false ]; then
        if ! sudo -v; then 
            echo "[ERRO] Privilégios de superusuário (sudo) são necessários para rodar o perf."
            exit 1
        fi
        if ! command -v perf &> /dev/null; then
            echo "[ERRO] O comando 'perf' não foi encontrado."
            exit 1
        fi
    fi

    if ! command -v python3 &> /dev/null; then 
        echo "[ERRO] 'python3' não encontrado."
        exit 1
    fi
    if ! python3 -c "import matplotlib" &> /dev/null; then 
        echo "[ERRO] A biblioteca 'matplotlib' não está instalada no Python."
        exit 1
    fi
    echo "  [OK] Todas as dependências foram atendidas."
    echo ""
}

check_dependencies

# --- FUNÇÃO GERADORA DE GRÁFICOS (PYTHON) ---
graph_gen() {
export NUM_RUNS
python3 - << 'EOF'
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import glob
import re
import os
import datetime

print("  [Python] Iniciando processamento de dados...")
arquivos = glob.glob("*.txt")

if not arquivos:
    print("  [Python] Nenhum arquivo .txt encontrado para gerar gráficos.")
    exit()

num_runs = os.environ.get('NUM_RUNS', '10') 

NOMES_METRICAS = {
    "ipc": "Instruções por Ciclo (IPC)",
    "task-clock:u": "Tempo de Execução (ms)",
    "page-faults": "Page Faults",
    "cycles": "Ciclos de CPU",
    "instructions": "Instruções Executadas",
    "cache-misses": "Cache Misses (Geral)",
    "branches": "Branches (Total)",
    "branch-misses": "Branch Misses",
    "L1-dcache-loads": "L1 Cache Loads",
    "L1-dcache-load-misses": "L1 Cache Misses",
    "LLC-loads": "LLC Loads",
    "LLC-load-misses": "LLC Misses"
}

# ORDENAÇÃO FIXA DAS MÉTRICAS
ORDEM_METRICAS = [
    "task-clock:u",
    "cycles",
    "instructions",
    "ipc",
    "branches",
    "branch-misses",
    "L1-dcache-loads",
    "LLC-loads",
    "L1-dcache-load-misses",
    "LLC-load-misses",
    "cache-misses",
    "page-faults"
]

def formata_numero(valor, metrica):
    if metrica in ["ipc", "task-clock:u"]:
        return f"{valor:.2f}"
    if valor >= 1_000_000:
        texto_sci = f"{valor:.2e}"
        base, exp = texto_sci.split('e')
        return f"$\\mathbf{{{float(base):.2f} \\times 10^{{{int(exp)}}}}}$"
    return f"{int(valor):,}"

for arquivo in arquivos:
    partes = arquivo.split('_')
    algoritmo = partes[1].capitalize() if len(partes) > 1 else "Geral"
    
    with open(arquivo, 'r') as f:
        linhas = f.readlines()

    dados = {}  
    erros = {}  
    indisponivel = {}
    metricas_encontradas = set()
    otimizacao_atual = None
    alvo_customizado = None

    for linha in linhas:
        match_alvo = re.search(r"^### ALVO_BARRA: (.+) ###", linha)
        if match_alvo:
            alvo_customizado = match_alvo.group(1)
            continue

        match_app = re.search(r"Performance counter stats for '([^']+)'", linha)
        if match_app:
            arquivo_exec = match_app.group(1)
            nome_limpo = arquivo_exec.split('/')[-1]

            if alvo_customizado:
                otimizacao_atual = alvo_customizado
                alvo_customizado = None
            elif "_" in nome_limpo:
                otimizacao_atual = "-" + nome_limpo.split("_")[-1]
            else:
                otimizacao_atual = nome_limpo
                
            if otimizacao_atual not in dados:
                dados[otimizacao_atual] = {}
                erros[otimizacao_atual] = {}
                indisponivel[otimizacao_atual] = {}
            continue
        
        if not otimizacao_atual:
            continue

        # Detecta eventos que o perf não conseguiu contar (multiplexação) ou
        # que a CPU não suporta. Essas linhas NÃO começam com um número, então
        # o regex numérico abaixo nunca as captura
        match_indisponivel = re.search(r"^\s*<(not counted|not supported)>\s+([a-zA-Z0-9_/\-:]+)", linha)
        if match_indisponivel:
            motivo = match_indisponivel.group(1)
            nome_bruto = match_indisponivel.group(2)

            if "cpu_core" in nome_bruto:
                tipo_nucleo = "P-Core"
                metrica_base = nome_bruto.replace("cpu_core/", "").strip("/")
            elif "cpu_atom" in nome_bruto:
                tipo_nucleo = "E-Core"
                metrica_base = nome_bruto.replace("cpu_atom/", "").strip("/")
            else:
                tipo_nucleo = "Total"
                metrica_base = nome_bruto.strip("/")

            if metrica_base in NOMES_METRICAS:
                if metrica_base not in indisponivel[otimizacao_atual]:
                    indisponivel[otimizacao_atual][metrica_base] = {}
                indisponivel[otimizacao_atual][metrica_base][tipo_nucleo] = motivo
                metricas_encontradas.add(metrica_base)
            continue


        match_metrica = re.search(r"^\s*([\d\.,]+)(?:\s+(msec))?\s+([a-zA-Z0-9_/\-:]+)(?:.*?\(\s*\+-\s*([\d\.,]+)%\s*\))?", linha)
        
        if match_metrica:
            valor_str = match_metrica.group(1).replace('.', '').replace(',', '.')
            try:
                valor = float(valor_str)
            except ValueError:
                continue
                
            nome_bruto = match_metrica.group(3)
            is_msec = match_metrica.group(2) is not None
            erro_str_index = 4
            
            if "cpu_core" in nome_bruto:
                tipo_nucleo = "P-Core"
                metrica_base = nome_bruto.replace("cpu_core/", "").strip("/")
            elif "cpu_atom" in nome_bruto:
                tipo_nucleo = "E-Core"
                metrica_base = nome_bruto.replace("cpu_atom/", "").strip("/")
            else:
                tipo_nucleo = "Total"
                metrica_base = nome_bruto.strip("/")
            
            desvio_absoluto = 0.0
            if match_metrica.group(erro_str_index):
                erro_pct_str = match_metrica.group(erro_str_index).replace(',', '.')
                erro_pct = float(erro_pct_str)
                desvio_absoluto = valor * (erro_pct / 100.0)

            if metrica_base == "task-clock:u":
                if not is_msec:
                    valor = valor / 1000000.0
                    desvio_absoluto = desvio_absoluto / 1000000.0

            if metrica_base in NOMES_METRICAS:
                if metrica_base not in dados[otimizacao_atual]:
                    dados[otimizacao_atual][metrica_base] = {}
                    erros[otimizacao_atual][metrica_base] = {}
                
                dados[otimizacao_atual][metrica_base][tipo_nucleo] = valor
                erros[otimizacao_atual][metrica_base][tipo_nucleo] = desvio_absoluto
                metricas_encontradas.add(metrica_base)

    # Um núcleo (P-Core/E-Core) só é considerado "parte do experimento" se tiver
    # pelo menos um valor real em ALGUM lugar deste arquivo. Isso distingue:
    #   - multiplexação esporádica (o núcleo tem dados reais na maioria das métricas,
    #     faltando só pontualmente) -> mantém a barra hachurada.
    #   - núcleo inteiramente ausente (ex: taskset restringiu a execução a um só tipo
    #     de núcleo, então o outro nunca roda nada) -> remove o núcleo do gráfico
    #     inteiramente, em vez de hachurar 100% das barras dele.
    nucleos_com_dados_reais = set()
    for opt in dados:
        for metrica in dados[opt]:
            nucleos_com_dados_reais.update(dados[opt][metrica].keys())

    for opt in dados:
        for nucleo in ["Total", "P-Core", "E-Core"]:
            inst_disponivel = "instructions" in dados[opt] and nucleo in dados[opt]["instructions"]
            cyc_disponivel = "cycles" in dados[opt] and nucleo in dados[opt]["cycles"]

            if inst_disponivel and cyc_disponivel:
                inst = dados[opt]["instructions"][nucleo]
                cyc = dados[opt]["cycles"][nucleo]
                if cyc > 0:
                    if "ipc" not in dados[opt]:
                        dados[opt]["ipc"] = {}
                        erros[opt]["ipc"] = {}
                    
                    ipc = inst / cyc
                    dados[opt]["ipc"][nucleo] = ipc
                    
                    err_inst_pct = (erros[opt]["instructions"][nucleo] / inst) if inst > 0 else 0
                    err_cyc_pct = (erros[opt]["cycles"][nucleo] / cyc) if cyc > 0 else 0
                    erros[opt]["ipc"][nucleo] = ipc * (err_inst_pct + err_cyc_pct)
                    
                    metricas_encontradas.add("ipc")
            else:
                # O IPC não pôde ser calculado porque instructions e/ou cycles
                # estava indisponível (not counted/not supported) para este núcleo.
                # Em vez de deixar o IPC simplesmente ausente e sem explicação,
                # propaga o mesmo motivo para que o painel de IPC também exiba
                # a barra hachurada, igual aos demais painéis.
                motivo = (indisponivel.get(opt, {}).get("instructions", {}).get(nucleo)
                          or indisponivel.get(opt, {}).get("cycles", {}).get(nucleo))
                if motivo:
                    if "ipc" not in indisponivel[opt]:
                        indisponivel[opt]["ipc"] = {}
                    indisponivel[opt]["ipc"][nucleo] = motivo
                    metricas_encontradas.add("ipc")

    if not dados:
        continue

    def chave_ordenacao(x):
        ordem_c = {'-O0': 0, '-O1': 1, '-O2': 2, '-O3': 3, '-Os': 4, '-Ofast': 5}
        if x in ordem_c:
            return (0, ordem_c[x])
        return (1, x)
        
    opts_encontradas = sorted(dados.keys(), key=chave_ordenacao)
    
    metricas_lista = sorted(list(metricas_encontradas), key=lambda x: ORDEM_METRICAS.index(x) if x in ORDEM_METRICAS else 999)
    num_metricas = len(metricas_lista)
    
    cols = 2 if num_metricas > 1 else 1
    rows = (num_metricas + cols - 1) // cols
    
    fig, axs = plt.subplots(rows, cols, figsize=(8 * cols, 5 * rows))
    
    fig.suptitle(f'{algoritmo} (Média e SD - {num_runs} Runs)', fontsize=22, fontweight='bold')
    
    if num_metricas == 1:
        axs = [axs]
    else:
        axs = axs.flatten()

    cores_grafico = {"Total": "#2ca02c", "P-Core": "#1f77b4", "E-Core": "#ff7f0e"}
    posicoes_x = list(range(len(opts_encontradas)))

    for i, metrica in enumerate(metricas_lista):
        ax = axs[i]
        
        nucleos_presentes = set()
        for opt in opts_encontradas:
            if metrica in dados[opt]:
                nucleos_presentes.update(dados[opt][metrica].keys())
            if metrica in indisponivel.get(opt, {}):
                nucleos_presentes.update(
                    n for n in indisponivel[opt][metrica].keys()
                    if n in nucleos_com_dados_reais
                )
        
        nucleos_ordenados = [n for n in ["Total", "P-Core", "E-Core"] if n in nucleos_presentes]
        qtd_nucleos = len(nucleos_ordenados)
        largura_barra = 0.8 / qtd_nucleos if qtd_nucleos > 0 else 0.8

        teto_maximo = 1
        todos_valores_grafico = []

        for idx, nucleo in enumerate(nucleos_ordenados):
            deslocamento = (idx - (qtd_nucleos - 1) / 2.0) * largura_barra
            x_barras = [pos + deslocamento for pos in posicoes_x]
            
            valores = [dados[opt][metrica].get(nucleo, 0) if metrica in dados[opt] else 0 for opt in opts_encontradas]
            erros_val = [erros[opt][metrica].get(nucleo, 0) if metrica in erros[opt] else 0 for opt in opts_encontradas]
            
            todos_valores_grafico.extend([v for v in valores if v > 0])
            
            bars = ax.bar(x_barras, valores, largura_barra, yerr=erros_val, capsize=4, 
                          color=cores_grafico.get(nucleo), edgecolor='black', alpha=0.8, 
                          ecolor='red', error_kw={'linewidth': 1.2}, label=nucleo)
            
            teto_maximo = max(teto_maximo, max([v + e for v, e in zip(valores, erros_val)]) if valores else 1)
            
            for bar, erro_atual in zip(bars, erros_val):
                yval = bar.get_height()
                if yval > 0:
                    erro_pct = (erro_atual / yval) * 100 if yval > 0 else 0
                    
                    texto_valor = formata_numero(yval, metrica)
                    tamanho_fonte = 8 if qtd_nucleos > 1 else 9
                    
                    if metrica != "ipc":
                        y_text = (yval + erro_atual) * 1.5 
                    else:
                        y_text = yval + erro_atual + (teto_maximo * 0.05)
                        
                    ax.text(bar.get_x() + bar.get_width()/2, y_text, 
                            f"{texto_valor}\n(±{erro_pct:.1f}%)", ha='center', va='bottom', 
                            fontsize=tamanho_fonte, fontweight='bold', color='#222222', rotation=30)

        if metrica != "ipc":
            ax.set_yscale('log')
            min_nonzero = min(todos_valores_grafico) if todos_valores_grafico else 1
            ax.set_ylim(bottom=min_nonzero * 0.1, top=teto_maximo * 30.0) 
        else:
            ax.set_ylim(0, teto_maximo * 1.4) 

        # --- Marca visualmente as métricas indisponíveis (not counted / not supported) ---
        # Sem isso, a ausência de uma barra é indistinguível de um valor real igual a zero
        # (limitação identificada na revisão do artigo). Desenha uma barra hachurada
        # ocupando toda a altura do eixo, com um rótulo curto indicando o motivo.
        bottom_lim, top_lim = ax.get_ylim()
        algum_indisponivel = False
        for idx, nucleo in enumerate(nucleos_ordenados):
            deslocamento = (idx - (qtd_nucleos - 1) / 2.0) * largura_barra
            for pos, opt in zip(posicoes_x, opts_encontradas):
                motivo = indisponivel.get(opt, {}).get(metrica, {}).get(nucleo)
                if not motivo:
                    continue
                algum_indisponivel = True
                x_barra = pos + deslocamento
                base = 0 if metrica == "ipc" else bottom_lim
                ax.bar(x_barra, top_lim - base, largura_barra, bottom=base,
                       color='none', edgecolor='#999999', hatch='////',
                       linewidth=1.0, zorder=1)
                rotulo = "N/S" if motivo == "not supported" else "N/C"
                ax.text(x_barra, 0.5, rotulo, transform=ax.get_xaxis_transform(),
                        ha='center', va='center', fontsize=8, fontweight='bold',
                        color='#666666', rotation=90)

        ax.set_title(NOMES_METRICAS.get(metrica, metrica), fontsize=13, pad=15)
        ax.set_xticks(posicoes_x)
        ax.set_xticklabels(opts_encontradas, rotation=15, ha='center')
        ax.grid(axis='y', linestyle='--', alpha=0.6)
        
        if algum_indisponivel:
            handles, labels = ax.get_legend_handles_labels()
            proxy = mpatches.Patch(facecolor='none', edgecolor='#999999', hatch='////',
                                    label='Indisponível (N/C=não contado, N/S=não suportado)')
            handles.append(proxy)
            ax.legend(handles=handles, loc="upper right", fontsize=7, framealpha=0.9)
        else:
            ax.legend(loc="upper right", fontsize=8, framealpha=0.9)

    for j in range(num_metricas, len(axs)):
        fig.delaxes(axs[j])

    plt.tight_layout()
    fig.subplots_adjust(top=0.96)
    
    agora = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    nome_img = f"Grafico_{algoritmo}_{agora}.pdf"
    
    plt.savefig(nome_img, format='pdf', bbox_inches='tight')
    plt.close()
    
    print(f"  [OK] Gráfico PDF gerado: {nome_img}")

EOF
}

# --- MODO APENAS GRÁFICOS (--plot-only) ---
if [ "$APENAS_GRAFICOS" = true ]; then
    echo "=== Modo Plot-Only ==="
    if [ ${#ALVOS[@]} -eq 0 ]; then
        echo "[ERRO] Você precisa especificar a pasta que contém os arquivos .txt."
        exit 1
    fi

    for dir in "${ALVOS[@]}"; do
        dir_limpo=${dir%/}
        if [ -d "$dir_limpo" ]; then 
            echo "-> Analisando arquivos na pasta: $dir_limpo"
            (cd "$dir_limpo" && graph_gen) 
        else
            echo "[AVISO] Pasta não encontrada: $dir_limpo"
        fi
    done
    echo "Processamento de gráficos finalizado!"
    exit 0
fi

# --- SELEÇÃO DE ALVOS E DEFINIÇÃO DINÂMICA DA PASTA ---
if [ ${#ALVOS[@]} -eq 0 ]; then
    for d in */; do ALVOS+=("$d"); done
    NOME_PASTA_COMPLETO="${NOME_PASTA}_${TIMESTAMP}"
else
    if [ ${#ALVOS[@]} -eq 1 ]; then
        ALVO_LIMPO=${ALVOS[0]%/}
        NOME_PASTA_COMPLETO="${NOME_PASTA}_${ALVO_LIMPO}_${TIMESTAMP}"
    else
        NOME_PASTA_COMPLETO="${NOME_PASTA}_${TIMESTAMP}"
    fi
fi

if [ ! -d "$NOME_PASTA_COMPLETO" ]; then
    mkdir -p "$NOME_PASTA_COMPLETO"
fi

# --- PREPARAÇÃO DOS EVENTOS ---
EVENTOS="task-clock:u,page-faults,cycles,instructions"
if [ "$MEDIR_TUDO" = true ]; then
    MEDIR_CACHE=true
    MEDIR_BRANCHES=true
fi
if [ "$MEDIR_CACHE" = true ]; then EVENTOS="$EVENTOS,cache-misses,L1-dcache-loads,L1-dcache-load-misses,LLC-loads,LLC-load-misses"; fi
if [ "$MEDIR_BRANCHES" = true ]; then EVENTOS="$EVENTOS,branches,branch-misses"; fi

# Traduzindo as flags do bash para linguagem natural
EVENTOS_PT=$(echo "$EVENTOS" | sed \
    -e 's/task-clock:u/Tempo de Execução (ms)/g' \
    -e 's/page-faults/Page Faults/g' \
    -e 's/cycles/Ciclos de CPU/g' \
    -e 's/instructions/Instruções Executadas/g' \
    -e 's/L1-dcache-load-misses/L1 Cache Misses/g' \
    -e 's/L1-dcache-loads/L1 Cache Loads/g' \
    -e 's/LLC-load-misses/LLC Misses/g' \
    -e 's/LLC-loads/LLC Loads/g' \
    -e 's/cache-misses/Cache Misses (Geral)/g' \
    -e 's/branch-misses/Branch Misses/g' \
    -e 's/branches/Branches (Total)/g' \
    -e 's/,/, /g')

echo "=========================================================="
echo "                  RESUMO DA EXECUÇÃO                      "
echo "=========================================================="
echo "[*] Pastas alvo: ${ALVOS[*]}"
echo "[*] Repetições por teste (-r): $NUM_RUNS"
echo "[*] Diretório de saída: $NOME_PASTA_COMPLETO"
echo "[*] Eventos que serão coletados:"
echo "    -> $EVENTOS_PT"
echo ""
echo "[*] Códigos mapeados para o profiling:"

for dir in "${ALVOS[@]}"; do
    dir_limpo=${dir%/}
    if [[ "$dir_limpo" == "${NOME_PASTA}"* ]]; then continue; fi
    
    echo "    📂 $dir_limpo/"
    achou_codigo=false
    
    if [ -d "$dir_limpo" ]; then
        for app in "$dir_limpo"/*; do
            if [ -f "$app" ] && [ -x "$app" ] && [[ "$app" != *".cpp" ]] && [[ "$app" != *".c" ]]; then
                nome_exec=$(basename "$app")
                echo "       ⚙️  $nome_exec"
                achou_codigo=true
            fi
        done
    fi
    
    if [ "$achou_codigo" = false ]; then
        echo "       (Nenhum executável válido encontrado)"
    fi
done
echo "=========================================================="
echo "Iniciando a bateria de testes em 3 segundos..."
sleep 3
echo ""

GEROU_ARQUIVOS=false

for dir in "${ALVOS[@]}"; do
    dir_limpo=${dir%/}

    if [[ "$dir_limpo" == "${NOME_PASTA}"* ]]; then continue; fi

    echo "Processando diretório: $dir_limpo"
    cd "$dir" || continue

    ARQUIVO_SAIDA="resultado_${dir_limpo}_${TIMESTAMP}.txt"
    ARQUIVO_CRIADO=false

    for app in ./*; do
        if [ -f "$app" ] && [ -x "$app" ] && [[ "$app" != *".cpp" ]] && [[ "$app" != *".c" ]]; then
            nome_exec=$(basename "$app")

            if [[ "$nome_exec" == *".sh" ]]; then
                # Varre a última linha do script, ignorando interpretadores e flags
                ALVO_REAL=$(grep -v '^\s*#' "$app" | grep -v '^\s*$' | tail -n 1 | awk '{
                    for(i=1; i<=NF; i++) {
                        if ($i ~ /(^|\/)(python[0-9]*|java|node|ruby|bash|sh)$/) continue;
                        if ($i ~ /^-/) continue;
                        
                        n=split($i, a, "/");
                        print a[n];
                        exit;
                    }
                }')
                
                # Se por acaso o awk falhar em achar algo, usa o nome do próprio arquivo .sh como fallback de segurança
                NOME_BARRA=${ALVO_REAL:-$nome_exec}
            else
                NOME_BARRA=$nome_exec
            fi

            echo "  -> Profiling: $nome_exec (Alvo: $NOME_BARRA) ..."
            
            echo "### ALVO_BARRA: $NOME_BARRA ###" >> "$ARQUIVO_SAIDA"
            
            sudo perf stat -r "$NUM_RUNS" -e "$EVENTOS" "$app" 2>> "$ARQUIVO_SAIDA"
            ARQUIVO_CRIADO=true
        fi
    done

    if [ "$ARQUIVO_CRIADO" = true ]; then
        mv "$ARQUIVO_SAIDA" "../$NOME_PASTA_COMPLETO/"
        echo "     [OK] Arquivo consolidado salvo."
        GEROU_ARQUIVOS=true
    else
        echo "     [AVISO] Nenhum executável encontrado nesta pasta."
        rm -f "$ARQUIVO_SAIDA" 2>/dev/null
    fi

    cd ..
done

echo ""
echo "Processamento finalizado."

if [ "$GEROU_ARQUIVOS" = true ]; then
    echo "Gerando gráficos na pasta $NOME_PASTA_COMPLETO..."
    (cd "$NOME_PASTA_COMPLETO" && graph_gen)
    echo "Tudo pronto!"
else
    echo "[AVISO] Nenhuma métrica foi coletada. Gráficos não gerados."
    rmdir "$NOME_PASTA_COMPLETO" 2>/dev/null 
fi

#!/bin/bash

# ===============================================
# 🐳 DOCKER MONITOR - VERSÃO RESPONSIVA ASCII
# Interface adaptativa com bordas compatíveis
# ===============================================

# Cores e estilos
declare -A COLORS=(
    ["RED"]='\033[0;31m'
    ["GREEN"]='\033[0;32m'
    ["YELLOW"]='\033[1;33m'
    ["BLUE"]='\033[0;34m'
    ["PURPLE"]='\033[0;35m'
    ["CYAN"]='\033[0;36m'
    ["WHITE"]='\033[1;37m'
    ["GRAY"]='\033[0;90m'
    ["BOLD"]='\033[1m'
    ["NC"]='\033[0m'
    ["DIM"]='\033[2m'
)

# Configurações
REFRESH_INTERVAL=3
SHOW_STOPPED=true
SHOW_STATS=true
DEBUG_MODE=false

# Variáveis para dimensões do terminal
TERMINAL_WIDTH=0
TERMINAL_HEIGHT=0

print_color() {
    printf "${COLORS[$1]}%s${COLORS[NC]}\n" "$2"
}

print_inline() {
    printf "${COLORS[$1]}%s${COLORS[NC]}" "$2"
}

clear_screen() {
    clear
    tput cup 0 0
}

# Função para obter dimensões do terminal
get_terminal_size() {
    TERMINAL_WIDTH=$(tput cols 2>/dev/null || echo 100)
    TERMINAL_HEIGHT=$(tput lines 2>/dev/null || echo 30)
    
    # Garantir largura mínima e máxima
    [ $TERMINAL_WIDTH -lt 80 ] && TERMINAL_WIDTH=80
    [ $TERMINAL_WIDTH -gt 200 ] && TERMINAL_WIDTH=200
}

# Função para calcular espaçamentos baseado na largura do terminal
calculate_widths() {
    local base_width=$((TERMINAL_WIDTH - 4))
    
    # Distribuição inteligente baseada no tamanho disponível
    if [ $TERMINAL_WIDTH -lt 100 ]; then
        # Terminal pequeno - layout compacto
        STATUS_WIDTH=8
        NAME_WIDTH=18
        IMAGE_WIDTH=15
        CPU_WIDTH=6
        MEMORY_WIDTH=8
        NET_WIDTH=8
        UPTIME_WIDTH=10
    elif [ $TERMINAL_WIDTH -lt 140 ]; then
        # Terminal médio - layout balanceado
        STATUS_WIDTH=10
        NAME_WIDTH=25
        IMAGE_WIDTH=20
        CPU_WIDTH=8
        MEMORY_WIDTH=12
        NET_WIDTH=10
        UPTIME_WIDTH=12
    else
        # Terminal grande - layout completo
        STATUS_WIDTH=12
        NAME_WIDTH=$((base_width * 30 / 100))
        IMAGE_WIDTH=$((base_width * 25 / 100))
        CPU_WIDTH=10
        MEMORY_WIDTH=15
        NET_WIDTH=12
        UPTIME_WIDTH=$((base_width - STATUS_WIDTH - NAME_WIDTH - IMAGE_WIDTH - CPU_WIDTH - MEMORY_WIDTH - NET_WIDTH))
    fi
    
    # Garantir larguras mínimas
    [ $NAME_WIDTH -lt 12 ] && NAME_WIDTH=12
    [ $IMAGE_WIDTH -lt 10 ] && IMAGE_WIDTH=10
    [ $UPTIME_WIDTH -lt 8 ] && UPTIME_WIDTH=8
}

# Função melhorada para status
get_status_info() {
    local status="$1"
    local color="GRAY"
    local emoji="●"
    local short_status=""
    
    if [[ "$status" =~ ^Up ]]; then
        color="GREEN"
        emoji="●"
        short_status="Running"
    elif [[ "$status" =~ ^Exited ]]; then
        color="RED"  
        emoji="●"
        short_status="Stopped"
    elif [[ "$status" =~ ^Restarting ]]; then
        color="YELLOW"
        emoji="●"
        short_status="Restart"
    elif [[ "$status" =~ ^Paused ]]; then
        color="PURPLE"
        emoji="●"
        short_status="Paused"
    elif [[ "$status" =~ ^Created ]]; then
        color="CYAN"
        emoji="●"
        short_status="Created"
    else
        short_status="Unknown"
    fi
    
    echo "$color|$emoji|$short_status"
}

# Função melhorada para uptime
get_uptime_from_status() {
    local status="$1"
    
    # Extrair tempo do status de forma mais robusta
    if [[ "$status" =~ Up[[:space:]]+([0-9]+)[[:space:]]+day ]]; then
        local days=$(echo "$status" | grep -oE '[0-9]+' | head -1)
        echo "${days}d"
    elif [[ "$status" =~ Up[[:space:]]+([0-9]+)[[:space:]]+hour ]]; then
        local hours=$(echo "$status" | grep -oE '[0-9]+' | head -1)
        echo "${hours}h"
    elif [[ "$status" =~ Up[[:space:]]+([0-9]+)[[:space:]]+minute ]]; then
        local minutes=$(echo "$status" | grep -oE '[0-9]+' | head -1)
        echo "${minutes}m"
    elif [[ "$status" =~ Up[[:space:]]+([0-9]+)[[:space:]]+second ]]; then
        local seconds=$(echo "$status" | grep -oE '[0-9]+' | head -1)
        echo "${seconds}s"
    elif [[ "$status" =~ ^Up ]]; then
        # Tentar extrair qualquer número do status
        local time_part=$(echo "$status" | grep -oE '[0-9]+ [a-z]+' | head -1)
        if [ -n "$time_part" ]; then
            local num=$(echo "$time_part" | grep -oE '[0-9]+')
            local unit=$(echo "$time_part" | grep -oE '[a-z]+' | head -c1)
            echo "${num}${unit}"
        else
            echo "Up"
        fi
    else
        echo "--"
    fi
}

# Função para obter stats de forma mais robusta
get_container_stats_safe() {
    local container_id="$1"
    
    # Verificar se container_id não está vazio
    if [ -z "$container_id" ]; then
        echo "N/A|N/A|N/A"
        return
    fi
    
    # Método 1: Tentar com formato simplificado
    local stats=""
    if command -v timeout >/dev/null 2>&1; then
        stats=$(timeout 2s docker stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}} {{.NetIO}}" "$container_id" 2>/dev/null)
    else
        stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}} {{.NetIO}}" "$container_id" 2>/dev/null)
    fi
    
    # Se conseguir stats com espaços, processar
    if [ -n "$stats" ] && [[ "$stats" != *"N/A"* ]]; then
        local cpu=$(echo "$stats" | awk '{print $1}')
        local mem_full=$(echo "$stats" | awk '{print $2}')
        local net_full=$(echo "$stats" | awk '{print $3}')
        
        # Extrair apenas a parte antes da barra para memória e rede
        local mem=$(echo "$mem_full" | cut -d'/' -f1 | xargs)
        local net=$(echo "$net_full" | cut -d'/' -f1 | xargs)
        
        # Tratar casos especiais
        [ "$cpu" = "0.00%" ] && cpu="~0%"
        [ "$mem" = "0B" ] && mem="~0MB"  
        [ "$net" = "0B" ] && net="~0KB"
        [ -z "$net" ] || [ "$net" = "" ] && net="~0KB"
        
        # Debug se ativado
        if [ "$DEBUG_MODE" = true ]; then
            echo "DEBUG: Raw stats='$stats' | CPU='$cpu' | MEM='$mem' | NET='$net'" >&2
        fi
        
        # Verificar se os valores não estão vazios
        [ -z "$cpu" ] && cpu="N/A"
        [ -z "$mem" ] && mem="N/A"  
        [ -z "$net" ] && net="N/A"
        
        echo "$cpu|$mem|$net"
        return
    fi
    
    # Método 2: Tentar com chamadas individuais se o primeiro falhar
    local cpu_individual=$(docker stats --no-stream --format "{{.CPUPerc}}" "$container_id" 2>/dev/null)
    local mem_individual=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_id" 2>/dev/null | cut -d'/' -f1)
    local net_individual=$(docker stats --no-stream --format "{{.NetIO}}" "$container_id" 2>/dev/null | cut -d'/' -f1)
    
    if [ -n "$cpu_individual" ] && [ -n "$mem_individual" ] && [ -n "$net_individual" ]; then
        echo "$cpu_individual|$mem_individual|$net_individual"
        return
    fi
    
    # Se tudo falhar, retornar N/A
    echo "N/A|N/A|N/A"
}

draw_header() {
    local total="$1"
    local running="$2" 
    local stopped="$3"
    
    get_terminal_size
    calculate_widths
    
    # Borda superior ASCII
    print_color "CYAN" "+$(printf '%*s' $((TERMINAL_WIDTH - 2)) '' | tr ' ' '-')+"
    
    # Linha do título
    local title="🐳 DOCKER CONTAINER MONITOR"
    local stats_info="Running: $running | Stopped: $stopped | Total: $total"
    local title_padding=$((TERMINAL_WIDTH - ${#title} - ${#stats_info} - 4))
    
    if [ $title_padding -gt 0 ]; then
        print_inline "CYAN" "| "
        print_inline "WHITE" "$title"
        printf "%*s" $title_padding ""
        print_inline "GREEN" "Running: $running"
        print_inline "CYAN" " | "
        print_inline "RED" "Stopped: $stopped"
        print_inline "CYAN" " | "
        print_inline "YELLOW" "Total: $total"
        print_color "CYAN" " |"
    else
        # Layout compacto para terminais pequenos
        print_inline "CYAN" "| "
        print_inline "WHITE" "🐳 DOCKER MONITOR"
        printf "%*s" $((TERMINAL_WIDTH - 20)) ""
        print_color "CYAN" " |"
        print_inline "CYAN" "| "
        print_inline "GREEN" "R:$running"
        print_inline "CYAN" " | "
        print_inline "RED" "S:$stopped"
        print_inline "CYAN" " | "
        print_inline "YELLOW" "T:$total"
        printf "%*s" $((TERMINAL_WIDTH - 18)) ""
        print_color "CYAN" " |"
    fi
    
    # Separador
    print_color "CYAN" "+$(printf '%*s' $((TERMINAL_WIDTH - 2)) '' | tr ' ' '-')+"
    
    # Header das colunas
    print_inline "CYAN" "| "
    
    # STATUS
    print_inline "BOLD" "STATUS"
    printf "%*s" $((STATUS_WIDTH - 6)) ""
    
    # NAME
    print_inline "BOLD" "NAME"
    printf "%*s" $((NAME_WIDTH - 4)) ""
    
    # IMAGE
    print_inline "BOLD" "IMAGE"
    printf "%*s" $((IMAGE_WIDTH - 5)) ""
    
    if [ "$SHOW_STATS" = true ]; then
        print_inline "BOLD" "CPU"
        printf "%*s" $((CPU_WIDTH - 3)) ""
        
        print_inline "BOLD" "MEMORY"
        printf "%*s" $((MEMORY_WIDTH - 6)) ""
        
        print_inline "BOLD" "NET I/O"
        printf "%*s" $((NET_WIDTH - 7)) ""
    fi
    
    print_inline "BOLD" "UPTIME"
    printf "%*s" $((UPTIME_WIDTH - 6)) ""
    
    print_color "CYAN" "|"
    
    # Separador do header
    print_color "CYAN" "+$(printf '%*s' $((TERMINAL_WIDTH - 2)) '' | tr ' ' '-')+"
}

draw_container_line() {
    local status="$1"
    local name="$2"
    local image="$3"
    local container_id="$4"
    
    # Obter informações processadas
    local status_info=$(get_status_info "$status")
    local color=$(echo "$status_info" | cut -d'|' -f1)
    local emoji=$(echo "$status_info" | cut -d'|' -f2)
    local clean_status=$(echo "$status_info" | cut -d'|' -f3)
    local uptime=$(get_uptime_from_status "$status")
    
    # Truncar baseado nas larguras calculadas
    local max_name=$((NAME_WIDTH - 1))
    local max_image=$((IMAGE_WIDTH - 1))
    
    [ ${#name} -gt $max_name ] && name="${name:0:$((max_name-3))}..."
    [ ${#image} -gt $max_image ] && image="${image:0:$((max_image-3))}..."
    
    print_inline "CYAN" "| "
    
    # STATUS
    local status_display="$emoji $clean_status"
    print_inline "$color" "$status_display"
    printf "%*s" $((STATUS_WIDTH - ${#status_display})) ""
    
    # NAME
    print_inline "WHITE" "$name"
    printf "%*s" $((NAME_WIDTH - ${#name})) ""
    
    # IMAGE
    print_inline "GRAY" "$image"
    printf "%*s" $((IMAGE_WIDTH - ${#image})) ""
    
    # STATS (apenas para containers rodando)
    if [ "$SHOW_STATS" = true ] && [[ "$status" =~ ^Up ]]; then
        local stats=$(get_container_stats_safe "$container_id")
        local cpu=$(echo "$stats" | cut -d'|' -f1)
        local mem=$(echo "$stats" | cut -d'|' -f2)
        local net=$(echo "$stats" | cut -d'|' -f3)
        
        # Melhorar apresentação de valores baixos
        [ "$cpu" = "N/A" ] && cpu="--"
        [ "$mem" = "N/A" ] && mem="--"
        [ "$net" = "N/A" ] && net="0B"
        
        # CPU
        if [ "$cpu" = "--" ]; then
            print_inline "DIM" "$cpu"
        else
            print_inline "YELLOW" "$cpu"
        fi
        printf "%*s" $((CPU_WIDTH - ${#cpu})) ""
        
        # MEMORY  
        if [ "$mem" = "--" ]; then
            print_inline "DIM" "$mem"
        else
            print_inline "PURPLE" "$mem"
        fi
        printf "%*s" $((MEMORY_WIDTH - ${#mem})) ""
        
        # NET I/O
        if [ "$net" = "0B" ] || [ "$net" = "~0KB" ]; then
            print_inline "DIM" "$net"
        elif [ "$net" = "--" ]; then
            print_inline "DIM" "$net"
        else
            print_inline "BLUE" "$net"
        fi
        printf "%*s" $((NET_WIDTH - ${#net})) ""
    elif [ "$SHOW_STATS" = true ]; then
        # Espaços vazios para containers parados
        local na_text="--"
        print_inline "DIM" "$na_text"
        printf "%*s" $((CPU_WIDTH - ${#na_text})) ""
        
        print_inline "DIM" "$na_text"
        printf "%*s" $((MEMORY_WIDTH - ${#na_text})) ""
        
        print_inline "DIM" "$na_text"
        printf "%*s" $((NET_WIDTH - ${#na_text})) ""
    fi
    
    # UPTIME
    print_inline "GREEN" "$uptime"
    printf "%*s" $((UPTIME_WIDTH - ${#uptime})) ""
    
    print_color "CYAN" "|"
}

draw_footer() {
    # Borda inferior
    print_color "CYAN" "+$(printf '%*s' $((TERMINAL_WIDTH - 2)) '' | tr ' ' '-')+"
    
    echo
    print_color "DIM" "💡 [q] Quit  [s] Stats  [h] Hidden  [r] Refresh"
    print_color "DIM" "   Updating every ${REFRESH_INTERVAL}s | Terminal: ${TERMINAL_WIDTH}x${TERMINAL_HEIGHT}"
}

monitor_containers() {
    while true; do
        clear_screen
        
        # Obter dados dos containers
        local container_data=""
        if [ "$SHOW_STOPPED" = true ]; then
            container_data=$(docker ps -a --format "{{.Status}}\t{{.Names}}\t{{.Image}}\t{{.ID}}" 2>/dev/null)
        else
            container_data=$(docker ps --format "{{.Status}}\t{{.Names}}\t{{.Image}}\t{{.ID}}" 2>/dev/null)
        fi
        
        if [ -z "$container_data" ]; then
            print_color "YELLOW" "⚠️  No containers found or Docker unavailable"
            print_color "DIM" "   Press 'q' to quit or wait for refresh..."
            sleep $REFRESH_INTERVAL
            continue
        fi
        
        # Contar containers
        local total_containers=$(echo "$container_data" | wc -l)
        local running_containers=$(echo "$container_data" | grep -c "^Up")
        local stopped_containers=$((total_containers - running_containers))
        
        draw_header "$total_containers" "$running_containers" "$stopped_containers"
        
        # Processar containers
        echo "$container_data" | while IFS=$'\t' read -r status name image container_id; do
            draw_container_line "$status" "$name" "$image" "$container_id"
        done
        
        draw_footer
        
        # Input handling
        if read -t $REFRESH_INTERVAL -n 1 key; then
            case "$key" in
                'q'|'Q') 
                    clear
                    print_color "GREEN" "👋 Docker Monitor stopped!"
                    exit 0 
                    ;;
                's'|'S') 
                    SHOW_STATS=$( [ "$SHOW_STATS" = true ] && echo false || echo true )
                    ;;
                'h'|'H') 
                    SHOW_STOPPED=$( [ "$SHOW_STOPPED" = true ] && echo false || echo true )
                    ;;
                'r'|'R') 
                    continue
                    ;;
            esac
        fi
    done
}

check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        print_color "RED" "❌ Docker command not found!"
        print_color "YELLOW" "💡 Please install Docker first"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_color "RED" "❌ Docker daemon not running!"
        print_color "YELLOW" "💡 Try: sudo systemctl start docker"
        exit 1
    fi
    
    # Teste rápido de stats
    if [ "$DEBUG_MODE" = true ]; then
        print_color "CYAN" "🔍 Testing docker stats capability..."
        local test_container=$(docker ps --format "{{.ID}}" | head -1)
        if [ -n "$test_container" ]; then
            local test_stats=$(docker stats --no-stream --format "{{.CPUPerc}} {{.MemUsage}} {{.NetIO}}" "$test_container" 2>/dev/null)
            print_color "WHITE" "Test stats: $test_stats"
        fi
    fi
}

show_help() {
    get_terminal_size
    
    print_color "CYAN" "🐳 DOCKER CONTAINER MONITOR - RESPONSIVE ASCII VERSION"
    echo
    print_color "WHITE" "FEATURES:"
    echo "  ✅ Responsive interface adapts to terminal size"
    echo "  ✅ ASCII borders for better compatibility"
    echo "  ✅ Real-time container monitoring"
    echo "  ✅ Smart column width distribution"
    echo "  ✅ Live statistics (CPU, Memory, Network)"
    echo
    print_color "WHITE" "CURRENT TERMINAL:"
    echo "  📐 Size: ${TERMINAL_WIDTH}x${TERMINAL_HEIGHT} characters"
    echo "  📏 Recommended minimum: 80 columns"
    echo "  🎯 Optimal width: 120+ columns"
    echo
    print_color "WHITE" "USAGE:"
    echo "  $0 [options]"
    echo
    print_color "WHITE" "OPTIONS:"
    echo "  -i, --interval SECONDS   Update interval (default: 3s)"
    echo "  -n, --no-stats          Disable performance stats"
    echo "  -a, --all               Show stopped containers"
    echo "  -d, --debug             Enable debug mode"  
    echo "  -h, --help              Show this help"
    echo
    print_color "WHITE" "INTERACTIVE COMMANDS:"
    echo "  q - Quit monitor"
    echo "  s - Toggle statistics display"
    echo "  h - Toggle stopped containers visibility"
    echo "  r - Force refresh"
    echo
    print_color "WHITE" "TIPS:"
    echo "  💡 Resize terminal window to see adaptive layout"
    echo "  💡 Use fullscreen for best experience"
    echo "  💡 Wider terminals show complete container names"
    echo
}

# Argument processing
while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        -n|--no-stats)
            SHOW_STATS=false
            shift
            ;;
        -a|--all)
            SHOW_STOPPED=true
            shift
            ;;
        -d|--debug)
            DEBUG_MODE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            print_color "RED" "❌ Unknown option: $1"
            echo "Use -h or --help for available options."
            exit 1
            ;;
    esac
done

# Traps for cleanup and resize handling
trap 'clear; print_color "GREEN" "👋 Monitor stopped!"; exit 0' INT TERM
trap 'get_terminal_size; calculate_widths' WINCH

# Main function
main() {
    print_color "CYAN" "🚀 Starting Docker Container Monitor..."
    
    check_docker
    
    print_color "GREEN" "✅ Docker detected! Starting monitor..."
    sleep 1
    
    monitor_containers
}

# Execute only if called directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

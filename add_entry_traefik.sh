#!/bin/bash

# ===============================================
# 🚀 TRAEFIK ENTRY CREATOR
# Script para criar configurações do Traefik
# Autor: Sistema Automatizado
# Data: $(date +"%Y-%m-%d")
# ===============================================

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Função para imprimir com cores
print_color() {
    printf "${!1}%s${NC}\n" "$2"
}

# Função para imprimir cabeçalho
print_header() {
    echo
    print_color "CYAN" "========================================"
    print_color "WHITE" "🚀 TRAEFIK ENTRY CREATOR"
    print_color "CYAN" "========================================"
    echo
}

# Função para imprimir erro
print_error() {
    print_color "RED" "❌ ERRO: $1"
}

# Função para imprimir sucesso
print_success() {
    print_color "GREEN" "✅ $1"
}

# Função para imprimir info
print_info() {
    print_color "BLUE" "ℹ️  $1"
}

# Função para imprimir warning
print_warning() {
    print_color "YELLOW" "⚠️  $1"
}

# === CONFIGURAÇÕES ===
TRAEFIK_CONFIG_DIR="/srv/docker/traefik/dynamic"
TRAEFIK_SERVICE="traefik"
CERT_RESOLVER="cloudflare"
ENTRYPOINT="https"
DEFAULT_PORT=80
BACKUP_DIR="${TRAEFIK_CONFIG_DIR}/backup"

# Configurações do AdGuard Home
ADGUARD_CONFIG_FILE="/srv/docker/adguard/config/AdGuardHome.yaml"
ADGUARD_INTERNAL_IP="10.15.1.2"

# Para teste local (descomente a linha abaixo para usar o arquivo de exemplo)
# ADGUARD_CONFIG_FILE="$PWD/exemplo_AdGuardHome.yaml"

# Função para mostrar ajuda
show_help() {
    print_header
    print_color "WHITE" "DESCRIÇÃO:"
    echo "  Este script cria configurações do Traefik para expor serviços."
    echo
    print_color "WHITE" "USO:"
    echo "  $0 <nome> <ip> [porta]"
    echo
    print_color "WHITE" "PARÂMETROS:"
    echo "  nome     Nome do serviço (será usado como subdomínio)"
    echo "  ip       Endereço IP do serviço"
    echo "  porta    Porta do serviço (padrão: $DEFAULT_PORT)"
    echo
    print_color "WHITE" "EXEMPLOS:"
    echo "  $0 grafana 192.168.1.100 3000"
    echo "  $0 nextcloud 192.168.1.101"
    echo "  $0 portainer 10.0.0.50 9000"
    echo
    print_color "WHITE" "OPÇÕES:"
    echo "  -h, --help    Mostra esta ajuda"
    echo "  -l, --list    Lista configurações existentes"
    echo "  -r, --remove  Remove uma configuração"
    echo "  -b, --backup  Cria backup das configurações"
    echo "  -a, --adguard Gerencia entradas DNS no AdGuard Home"
    echo
    print_color "WHITE" "COMANDOS ADGUARD:"
    echo "  $0 --adguard list                Lista rewrites DNS"
    echo "  $0 --adguard add <nome>          Adiciona rewrite DNS"
    echo "  $0 --adguard remove <nome>       Remove rewrite DNS"
    echo
}

# Função para validar IP
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

# Função para validar nome
validate_name() {
    local name=$1
    if [[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] || [[ $name =~ ^[a-zA-Z0-9]$ ]]; then
        return 0
    fi
    return 1
}

# Função para listar configurações
list_configs() {
    print_header
    print_info "Configurações existentes:"
    echo
    
    if [ ! -d "$TRAEFIK_CONFIG_DIR" ]; then
        print_warning "Diretório $TRAEFIK_CONFIG_DIR não encontrado!"
        return
    fi
    
    local count=0
    for file in "$TRAEFIK_CONFIG_DIR"/*.yaml; do
        if [ -f "$file" ]; then
            local basename=$(basename "$file" .yaml)
            local ip=$(grep -o 'http://[^:]*' "$file" | cut -d'/' -f3)
            local port=$(grep -o ':[0-9]*' "$file" | cut -d':' -f2)
            printf "  📄 %-20s → %s:%s\n" "$basename" "$ip" "$port"
            ((count++))
        fi
    done
    
    if [ $count -eq 0 ]; then
        print_info "Nenhuma configuração encontrada."
    else
        echo
        print_success "$count configuração(ões) encontrada(s)."
    fi
}

# Função para remover configuração
remove_config() {
    local name=$1
    local config_file="${TRAEFIK_CONFIG_DIR}/${name}.yaml"
    
    if [ ! -f "$config_file" ]; then
        print_error "Configuração '$name' não encontrada!"
        return 1
    fi
    
    print_warning "Tem certeza que deseja remover a configuração '$name'? (s/N)"
    read -r response
    if [[ "$response" =~ ^[Ss]$ ]]; then
        # Criar backup antes de remover
        create_backup
        backup_adguard
        
        # Remover configuração do Traefik
        rm "$config_file"
        print_success "Configuração Traefik '$name' removida com sucesso!"
        
        # Remover rewrite DNS do AdGuard
        remove_adguard_rewrite "$name"
        
        # Reiniciar serviços
        restart_traefik
    else
        print_info "Operação cancelada."
    fi
}

# Função para criar backup
create_backup() {
    print_info "Criando backup das configurações..."
    mkdir -p "$BACKUP_DIR"
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="${BACKUP_DIR}/traefik_configs_${timestamp}.tar.gz"
    
    if tar -czf "$backup_file" -C "$TRAEFIK_CONFIG_DIR" --exclude=backup *.yaml 2>/dev/null; then
        print_success "Backup criado: $backup_file"
    else
        print_warning "Nenhuma configuração para backup ou erro ao criar backup."
    fi
}

# Função para reiniciar Traefik
restart_traefik() {
    print_info "Reiniciando serviço Traefik..."
    if docker compose -f "/srv/docker/traefik/docker-compose.yml" restart 2>/dev/null; then
        print_success "Traefik reiniciado com sucesso!"
    else
        print_warning "Não foi possível reiniciar o Traefik automaticamente."
        print_info "Execute manualmente: docker compose -f /srv/docker/traefik/docker-compose.yml restart"
    fi
}

# Função para criar backup do AdGuard
backup_adguard() {
    if [ -f "$ADGUARD_CONFIG_FILE" ]; then
        local backup_file="${ADGUARD_CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$ADGUARD_CONFIG_FILE" "$backup_file"
        print_success "Backup do AdGuard criado: $backup_file"
    fi
}

# Função para adicionar rewrite no AdGuard Home
add_adguard_rewrite() {
    local service_name=$1
    local domain="${service_name}.homelab.felipecncloud.com"
    
    print_info "Adicionando rewrite DNS no AdGuard Home..."
    
    # Verificar se o arquivo existe
    if [ ! -f "$ADGUARD_CONFIG_FILE" ]; then
        print_error "Arquivo do AdGuard não encontrado: $ADGUARD_CONFIG_FILE"
        return 1
    fi
    
    # Criar backup antes de modificar
    backup_adguard
    
    # Verificar se a entrada já existe
    if grep -q "domain: $domain" "$ADGUARD_CONFIG_FILE"; then
        print_warning "Entrada DNS para '$domain' já existe no AdGuard!"
        return 0
    fi
    
    # Verificar se existe a seção filtering: e rewrites: dentro dela
    if grep -q "^filtering:" "$ADGUARD_CONFIG_FILE" && grep -A 50 "^filtering:" "$ADGUARD_CONFIG_FILE" | grep -q "rewrites:"; then
        # Adicionar na seção rewrites existente
        # Encontrar a linha com rewrites: dentro de filtering: e adicionar depois
        awk -v domain="$domain" -v ip="$ADGUARD_INTERNAL_IP" '
        /^filtering:/ { in_filtering = 1 }
        in_filtering && /^  rewrites:/ { 
            print $0
            print "    - domain: " domain
            print "      answer: " ip
            next
        }
        /^[a-zA-Z]/ && !/^filtering:/ { in_filtering = 0 }
        { print }
        ' "$ADGUARD_CONFIG_FILE" > "${ADGUARD_CONFIG_FILE}.tmp" && mv "${ADGUARD_CONFIG_FILE}.tmp" "$ADGUARD_CONFIG_FILE"
    else
        print_error "Seção filtering: e/ou rewrites: não encontrada no arquivo do AdGuard!"
        print_info "Certifique-se de que o arquivo está no formato correto."
        return 1
    fi
    
    print_success "Rewrite DNS adicionado: $domain → $ADGUARD_INTERNAL_IP"
    
    # Reiniciar AdGuard Home
    restart_adguard
}

# Função para remover rewrite do AdGuard Home
remove_adguard_rewrite() {
    local service_name=$1
    local domain="${service_name}.homelab.felipecncloud.com"
    
    print_info "Removendo rewrite DNS do AdGuard Home..."
    
    if [ ! -f "$ADGUARD_CONFIG_FILE" ]; then
        print_error "Arquivo do AdGuard não encontrado: $ADGUARD_CONFIG_FILE"
        return 1
    fi
    
    # Criar backup antes de modificar
    backup_adguard
    
    # Remover as linhas relacionadas ao domínio (domain + answer)
    awk -v domain="$domain" '
    BEGIN { skip = 0 }
    /domain: / && $0 ~ domain { skip = 2; next }
    skip > 0 { skip--; next }
    { print }
    ' "$ADGUARD_CONFIG_FILE" > "${ADGUARD_CONFIG_FILE}.tmp" && mv "${ADGUARD_CONFIG_FILE}.tmp" "$ADGUARD_CONFIG_FILE"
    
    print_success "Rewrite DNS removido: $domain"
    
    # Reiniciar AdGuard Home
    restart_adguard
}

# Função para reiniciar AdGuard Home
restart_adguard() {
    print_info "Reiniciando serviço AdGuard Home..."
    if docker compose -f "/srv/docker/adguard/docker-compose.yml" restart 2>/dev/null; then
        print_success "AdGuard Home reiniciado com sucesso!"
    else
        print_warning "Não foi possível reiniciar o AdGuard automaticamente."
        print_info "Execute manualmente: docker compose -f /srv/docker/adguard/docker-compose.yml restart"
    fi
}

# Função para listar rewrites do AdGuard
list_adguard_rewrites() {
    print_header
    print_info "Rewrites DNS no AdGuard Home:"
    echo
    
    if [ ! -f "$ADGUARD_CONFIG_FILE" ]; then
        print_error "Arquivo do AdGuard não encontrado: $ADGUARD_CONFIG_FILE"
        return 1
    fi
    
    # Usar uma abordagem diferente: ler todo o arquivo em array
    local lines=()
    while IFS= read -r line; do
        lines+=("$line")
    done < "$ADGUARD_CONFIG_FILE"
    
    local in_filtering=false
    local in_rewrites=false
    local count=0
    local i=0
    
    while [ $i -lt ${#lines[@]} ]; do
        local line="${lines[$i]}"
        
        # Detectar início da seção filtering
        if [[ "$line" =~ ^filtering: ]]; then
            in_filtering=true
        # Se estamos em filtering e encontramos rewrites
        elif [ "$in_filtering" = true ] && [[ "$line" =~ ^[[:space:]]*rewrites: ]]; then
            in_rewrites=true
        # Se saímos da seção filtering (nova seção no nível raiz)
        elif [[ "$line" =~ ^[a-zA-Z] ]] && [ "$in_filtering" = true ]; then
            in_filtering=false
            in_rewrites=false
        # Se estamos em rewrites e encontramos uma entrada
        elif [ "$in_rewrites" = true ] && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*domain: ]]; then
            local domain=$(echo "$line" | sed 's/^[[:space:]]*-[[:space:]]*domain:[[:space:]]*//' | tr -d '\r')
            # Pegar a próxima linha para o answer
            ((i++))
            if [ $i -lt ${#lines[@]} ]; then
                local next_line="${lines[$i]}"
                if [[ "$next_line" =~ ^[[:space:]]+answer: ]]; then
                    local answer=$(echo "$next_line" | sed 's/^[[:space:]]*answer:[[:space:]]*//' | sed 's/[[:space:]]*#.*//' | tr -d '\r')
                    printf "  🌐 %-40s → %s\n" "$domain" "$answer"
                    ((count++))
                fi
            fi
        # Se saímos da seção rewrites (nova propriedade em filtering)
        elif [ "$in_rewrites" = true ] && [[ "$line" =~ ^[[:space:]]+[a-zA-Z] ]] && [[ ! "$line" =~ ^[[:space:]]*-[[:space:]]*domain: ]] && [[ ! "$line" =~ ^[[:space:]]+answer: ]]; then
            in_rewrites=false
        fi
        
        ((i++))
    done
    
    if [ $count -eq 0 ]; then
        print_info "Nenhum rewrite DNS encontrado."
    else
        echo
        print_success "$count rewrite(s) DNS encontrado(s)."
    fi
}

# === PROCESSAMENTO DE ARGUMENTOS ===

# Processar opções
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    -l|--list)
        list_configs
        exit 0
        ;;
    -r|--remove)
        if [ -z "$2" ]; then
            print_error "Nome da configuração não fornecido!"
            echo "Uso: $0 --remove <nome>"
            exit 1
        fi
        remove_config "$2"
        exit 0
        ;;
    -b|--backup)
        create_backup
        exit 0
        ;;
    -a|--adguard)
        case "$2" in
            list)
                list_adguard_rewrites
                exit 0
                ;;
            add)
                if [ -z "$3" ]; then
                    print_error "Nome do serviço não fornecido!"
                    echo "Uso: $0 --adguard add <nome_servico>"
                    exit 1
                fi
                add_adguard_rewrite "$3"
                exit 0
                ;;
            remove)
                if [ -z "$3" ]; then
                    print_error "Nome do serviço não fornecido!"
                    echo "Uso: $0 --adguard remove <nome_servico>"
                    exit 1
                fi
                remove_adguard_rewrite "$3"
                exit 0
                ;;
            *)
                print_error "Opção inválida para --adguard"
                echo "Uso: $0 --adguard {list|add|remove} [nome_servico]"
                exit 1
                ;;
        esac
        ;;
esac

# Validar número de argumentos
if [[ $# -lt 2 || $# -gt 3 ]]; then
    print_header
    print_error "Número incorreto de argumentos!"
    echo
    print_color "WHITE" "USO: $0 <nome> <ip> [porta]"
    echo
    print_info "Use '$0 --help' para mais informações."
    exit 1
fi

NAME=$1
IP=$2
PORT=${3:-$DEFAULT_PORT}
FQDN1="${NAME}.felipecncloud.com"
FQDN2="${NAME}.homelab.felipecncloud.com"

print_header

# === VALIDAÇÕES ===

print_info "Validando parâmetros..."

# Validar nome
if ! validate_name "$NAME"; then
    print_error "Nome inválido: '$NAME'"
    print_info "O nome deve conter apenas letras, números e hífens, não pode começar/terminar com hífen."
    exit 1
fi

# Validar IP
if ! validate_ip "$IP"; then
    print_error "Endereço IP inválido: '$IP'"
    exit 1
fi

# Validar porta
if ! [[ "$PORT" =~ ^[0-9]+$ ]] || (( PORT < 1 || PORT > 65535 )); then
    print_error "Porta inválida: '$PORT' (deve ser entre 1-65535)"
    exit 1
fi

print_success "Parâmetros validados com sucesso!"

# === VERIFICAÇÕES DE SISTEMA ===

print_info "Verificando sistema..."

# Verificar se o diretório existe
if [ ! -d "$TRAEFIK_CONFIG_DIR" ]; then
    print_warning "Diretório $TRAEFIK_CONFIG_DIR não encontrado!"
    print_info "Criando diretório..."
    sudo mkdir -p "$TRAEFIK_CONFIG_DIR"
    if [ $? -eq 0 ]; then
        print_success "Diretório criado com sucesso!"
    else
        print_error "Falha ao criar diretório!"
        exit 1
    fi
fi

# Verificar se já existe configuração
TRAEFIK_FILE="${TRAEFIK_CONFIG_DIR}/${NAME}.yaml"
if [ -f "$TRAEFIK_FILE" ]; then
    print_warning "Configuração para '$NAME' já existe!"
    print_info "Deseja sobrescrever? (s/N)"
    read -r response
    if [[ ! "$response" =~ ^[Ss]$ ]]; then
        print_info "Operação cancelada."
        exit 0
    fi
    # Criar backup antes de sobrescrever
    create_backup
fi

# === CRIAÇÃO DA CONFIGURAÇÃO ===

print_info "Criando configuração do Traefik..."

# Mostrar informações do que será criado
echo
print_color "PURPLE" "📋 RESUMO DA CONFIGURAÇÃO:"
echo "  🏷️  Nome: $NAME"
echo "  🌐 IP: $IP"
echo "  🔌 Porta: $PORT"
echo "  📜 Arquivo: $TRAEFIK_FILE"
echo "  🔗 URLs:"
echo "     • https://$FQDN1"
echo "     • https://$FQDN2"
echo

TRAEFIK_FILE="${TRAEFIK_CONFIG_DIR}/${NAME}.yaml"

# Criar arquivo de configuração com comentários
cat <<EOF > "$TRAEFIK_FILE"
# ===============================================
# Configuração Traefik para: $NAME
# Criado em: $(date)
# IP: $IP:$PORT
# ===============================================
http:
  routers:
    ${NAME}:
      rule: "Host(\`${FQDN1}\`) || Host(\`${FQDN2}\`)"
      entryPoints:
        - ${ENTRYPOINT}
      service: ${NAME}
      tls:
        certResolver: ${CERT_RESOLVER}

  services:
    ${NAME}:
      loadBalancer:
        servers:
          - url: "http://${IP}:${PORT}"
        healthCheck:
          path: "/"
          interval: "30s"
          timeout: "3s"
EOF

# Verificar se o arquivo foi criado com sucesso
if [ -f "$TRAEFIK_FILE" ]; then
    print_success "Configuração criada com sucesso!"
    
    # Adicionar rewrite DNS no AdGuard Home automaticamente
    print_info "Configurando DNS no AdGuard Home..."
    add_adguard_rewrite "$NAME"
    
    # === FINALIZAÇÃO ===
    echo
    print_color "CYAN" "🎉 CONFIGURAÇÃO CONCLUÍDA!"
    echo
    print_info "Próximos passos:"
    echo "  1. Verifique se o serviço está rodando em $IP:$PORT"
    echo "  2. O Traefik será reiniciado para aplicar as mudanças"
    echo "  3. DNS interno configurado: $FQDN2 → $ADGUARD_INTERNAL_IP"
    echo "  4. Aguarde alguns minutos para o certificado SSL ser gerado"
    echo "  5. Acesse: https://$FQDN1 ou https://$FQDN2"
    echo
    
    # Reiniciar Traefik
    restart_traefik
    
    echo
    print_color "GREEN" "✨ Tudo pronto! Sua aplicação estará disponível em alguns minutos."
    
else
    print_error "Falha ao criar o arquivo de configuração!"
    exit 1
fi
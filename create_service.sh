#!/bin/bash

# ===============================================
# 🐳 DOCKER SERVICE CREATOR
# Script para criar serviços Docker Compose
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
    print_color "WHITE" "🐳 DOCKER SERVICE CREATOR"
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
DEFAULT_BASE_PATH="/srv/docker"
DEFAULT_PORT=80
DEFAULT_IMAGE="nginx:alpine"
TRAEFIK_ENTRYPOINT="https"

# Templates de serviços comuns
declare -A SERVICE_TEMPLATES
SERVICE_TEMPLATES[nginx]="nginx:alpine|80|web"
SERVICE_TEMPLATES[apache]="httpd:alpine|80|web"
SERVICE_TEMPLATES[grafana]="grafana/grafana:latest|3000|monitoring"
SERVICE_TEMPLATES[prometheus]="prom/prometheus:latest|9090|monitoring"
SERVICE_TEMPLATES[portainer]="portainer/portainer-ce:latest|9000|management"
SERVICE_TEMPLATES[jellyfin]="jellyfin/jellyfin:latest|8096|media"
SERVICE_TEMPLATES[nextcloud]="nextcloud:latest|80|productivity"
SERVICE_TEMPLATES[wordpress]="wordpress:latest|80|cms"
SERVICE_TEMPLATES[mariadb]="mariadb:latest|3306|database"
SERVICE_TEMPLATES[postgres]="postgres:latest|5432|database"
SERVICE_TEMPLATES[redis]="redis:alpine|6379|cache"
# Função para mostrar ajuda
show_help() {
    print_header
    print_color "WHITE" "DESCRIÇÃO:"
    echo "  Este script cria estruturas completas de serviços Docker Compose."
    echo
    print_color "WHITE" "USO:"
    echo "  $0 <nome_servico> [opções]"
    echo
    print_color "WHITE" "PARÂMETROS:"
    echo "  nome_servico  Nome do serviço (será usado como diretório e container)"
    echo
    print_color "WHITE" "OPÇÕES:"
    echo "  -i, --image <imagem>      Imagem Docker a ser usada"
    echo "  -p, --port <porta>        Porta do serviço (padrão: $DEFAULT_PORT)"
    echo "  -t, --template <tipo>     Usar template pré-definido"
    echo "  -b, --base-path <path>    Caminho base (padrão: $DEFAULT_BASE_PATH)"
    echo "  -e, --env-file            Criar arquivo .env"
    echo "  -s, --ssl                 Configurar SSL/HTTPS"
    echo "  -n, --no-traefik          Não configurar Traefik"
    echo "  -h, --help                Mostra esta ajuda"
    echo "  -l, --list-templates      Lista templates disponíveis"
    echo
    print_color "WHITE" "EXEMPLOS:"
    echo "  $0 grafana -t grafana"
    echo "  $0 meuapp -i nginx:alpine -p 8080"
    echo "  $0 nextcloud -t nextcloud -e -s"
    echo
    print_color "WHITE" "TEMPLATES DISPONÍVEIS:"
    echo "  Use '$0 --list-templates' para ver todos os templates"
    echo
}

# Função para listar templates
list_templates() {
    print_header
    print_info "Templates de serviços disponíveis:"
    echo
    
    for template in "${!SERVICE_TEMPLATES[@]}"; do
        IFS='|' read -r image port category <<< "${SERVICE_TEMPLATES[$template]}"
        printf "  📦 %-15s → %-30s (porta: %s) [%s]\n" "$template" "$image" "$port" "$category"
    done | sort
    
    echo
    print_success "${#SERVICE_TEMPLATES[@]} templates disponíveis."
    echo
    print_info "Use: $0 <nome> -t <template>"
}

# Função para validar nome do serviço
validate_service_name() {
    local name=$1
    if [[ $name =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]$ ]] || [[ $name =~ ^[a-zA-Z0-9]$ ]]; then
        if [ ${#name} -le 63 ]; then
            return 0
        fi
    fi
    return 1
}

# Função para validar porta
validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
        return 0
    fi
    return 1
}

# Função para criar arquivo .env
create_env_file() {
    local service_path=$1
    local service_name=$2
    
    print_info "Criando arquivo .env..."
    
    cat > "$service_path/.env" <<EOF
# ===============================================
# Variáveis de Ambiente para: $service_name
# Criado em: $(date)
# ===============================================

# Configurações do Serviço
SERVICE_NAME=$service_name
COMPOSE_PROJECT_NAME=$service_name

# Timezone
TZ=America/Sao_Paulo

# Usuário e Grupo (ajuste conforme necessário)
PUID=1000
PGID=1000

# Portas
# PORT_INTERNAL=$DEFAULT_PORT
# PORT_EXTERNAL=8080

# Volumes
DATA_DIR=./data
CONFIG_DIR=./config
LOGS_DIR=./logs

# Adicione suas variáveis específicas aqui
# DATABASE_URL=
# API_KEY=
# SECRET_KEY=
EOF

    print_success "Arquivo .env criado!"
}

# Função para criar docker-compose com template
create_compose_from_template() {
    local service_name=$1
    local template=$2
    local service_path=$3
    local use_ssl=$4
    local use_traefik=$5
    
    if [[ ! -v SERVICE_TEMPLATES[$template] ]]; then
        print_error "Template '$template' não encontrado!"
        return 1
    fi
    
    IFS='|' read -r image port category <<< "${SERVICE_TEMPLATES[$template]}"
    
    print_info "Usando template: $template ($image)"
    
    local entrypoint="web"
    if [ "$use_ssl" = true ]; then
        entrypoint="websecure"
    fi
    
    # Criar docker-compose específico para o template
    case $template in
        "grafana")
            create_grafana_compose "$service_name" "$service_path" "$image" "$port" "$entrypoint" "$use_traefik"
            ;;
        "nextcloud")
            create_nextcloud_compose "$service_name" "$service_path" "$image" "$port" "$entrypoint" "$use_traefik"
            ;;
        "mariadb"|"postgres")
            create_database_compose "$service_name" "$service_path" "$image" "$port" "$use_traefik"
            ;;
        *)
            create_generic_compose "$service_name" "$service_path" "$image" "$port" "$entrypoint" "$use_traefik"
            ;;
    esac
}

# Função para criar compose genérico
create_generic_compose() {
    local service_name=$1
    local service_path=$2
    local image=$3
    local port=$4
    local entrypoint=$5
    local use_traefik=$6
    
    local traefik_labels=""
    if [ "$use_traefik" = true ]; then
        traefik_labels="    labels:
      - \"traefik.enable=true\"
      - \"traefik.http.routers.$service_name.rule=Host(\\\`$service_name.felipecncloud.com\\\`) || Host(\\\`$service_name.homelab.felipecncloud.com\\\`)\"
      - \"traefik.http.routers.$service_name.entrypoints=$entrypoint\"
      - \"traefik.http.services.$service_name.loadbalancer.server.port=$port\""
        
        if [ "$entrypoint" = "websecure" ]; then
            traefik_labels="$traefik_labels
      - \"traefik.http.routers.$service_name.tls=true\"
      - \"traefik.http.routers.$service_name.tls.certresolver=cloudflare\""
        fi
    fi
    
    local networks_section=""
    if [ "$use_traefik" = true ]; then
        networks_section="    networks:
      - traefik"
    fi
    
    cat > "$service_path/docker-compose.yml" <<EOF
# ===============================================
# Docker Compose para: $service_name
# Imagem: $image
# Criado em: $(date)
# ===============================================

services:
  $service_name:
    image: $image
    container_name: $service_name
    restart: unless-stopped
    volumes:
      - ./data:/data
      - ./config:/config
      - ./logs:/logs
$networks_section
$traefik_labels

$(if [ "$use_traefik" = true ]; then echo "networks:
  traefik:
    external: true"; fi)
EOF
}

# Função para criar compose do Grafana
create_grafana_compose() {
    local service_name=$1
    local service_path=$2
    local image=$3
    local port=$4
    local entrypoint=$5
    local use_traefik=$6
    
    local traefik_labels=""
    if [ "$use_traefik" = true ]; then
        traefik_labels="    labels:
      - \"traefik.enable=true\"
      - \"traefik.http.routers.$service_name.rule=Host(\\\`$service_name.felipecncloud.com\\\`) || Host(\\\`$service_name.homelab.felipecncloud.com\\\`)\"
      - \"traefik.http.routers.$service_name.entrypoints=$entrypoint\"
      - \"traefik.http.services.$service_name.loadbalancer.server.port=$port\""
        
        if [ "$entrypoint" = "websecure" ]; then
            traefik_labels="$traefik_labels
      - \"traefik.http.routers.$service_name.tls=true\"
      - \"traefik.http.routers.$service_name.tls.certresolver=cloudflare\""
        fi
    fi
    
    cat > "$service_path/docker-compose.yml" <<EOF
# ===============================================
# Grafana Service: $service_name
# Criado em: $(date)
# ===============================================

services:
  $service_name:
    image: $image
    container_name: $service_name
    restart: unless-stopped
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=\${GRAFANA_ADMIN_PASSWORD:-admin123}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_SERVER_ROOT_URL=https://$service_name.felipecncloud.com
    volumes:
      - ./data:/var/lib/grafana
      - ./config:/etc/grafana
      - ./logs:/var/log/grafana
$(if [ "$use_traefik" = true ]; then echo "    networks:
      - traefik"; fi)
$traefik_labels

$(if [ "$use_traefik" = true ]; then echo "networks:
  traefik:
    external: true"; fi)
EOF

    # Criar arquivo .env específico para Grafana
    cat >> "$service_path/.env" <<EOF

# Configurações específicas do Grafana
GRAFANA_ADMIN_PASSWORD=admin123
GF_SECURITY_SECRET_KEY=\$(openssl rand -base64 32)
EOF
}

# Função para criar compose do Nextcloud
create_nextcloud_compose() {
    local service_name=$1
    local service_path=$2
    local image=$3
    local port=$4
    local entrypoint=$5
    local use_traefik=$6
    
    local traefik_labels=""
    if [ "$use_traefik" = true ]; then
        traefik_labels="    labels:
      - \"traefik.enable=true\"
      - \"traefik.http.routers.$service_name.rule=Host(\\\`$service_name.felipecncloud.com\\\`) || Host(\\\`$service_name.homelab.felipecncloud.com\\\`)\"
      - \"traefik.http.routers.$service_name.entrypoints=$entrypoint\"
      - \"traefik.http.services.$service_name.loadbalancer.server.port=$port\""
        
        if [ "$entrypoint" = "websecure" ]; then
            traefik_labels="$traefik_labels
      - \"traefik.http.routers.$service_name.tls=true\"
      - \"traefik.http.routers.$service_name.tls.certresolver=cloudflare\""
        fi
    fi
    
    cat > "$service_path/docker-compose.yml" <<EOF
# ===============================================
# Nextcloud Service: $service_name
# Criado em: $(date)
# ===============================================

services:
  $service_name:
    image: $image
    container_name: $service_name
    restart: unless-stopped
    environment:
      - NEXTCLOUD_ADMIN_USER=\${NEXTCLOUD_ADMIN_USER:-admin}
      - NEXTCLOUD_ADMIN_PASSWORD=\${NEXTCLOUD_ADMIN_PASSWORD:-admin123}
      - NEXTCLOUD_TRUSTED_DOMAINS=\${NEXTCLOUD_TRUSTED_DOMAINS:-$service_name.felipecncloud.com $service_name.homelab.felipecncloud.com}
    volumes:
      - ./data:/var/www/html
      - ./config:/var/www/html/config
      - ./logs:/var/log
$(if [ "$use_traefik" = true ]; then echo "    networks:
      - traefik"; fi)
$traefik_labels

  ${service_name}-db:
    image: mariadb:latest
    container_name: ${service_name}-db
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD:-rootpassword}
      - MYSQL_DATABASE=\${MYSQL_DATABASE:-nextcloud}
      - MYSQL_USER=\${MYSQL_USER:-nextcloud}
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD:-nextcloudpass}
    volumes:
      - ./database:/var/lib/mysql

$(if [ "$use_traefik" = true ]; then echo "networks:
  traefik:
    external: true"; fi)
EOF

    # Criar diretório para banco de dados
    mkdir -p "$service_path/database"
    
    # Adicionar variáveis específicas do Nextcloud
    cat >> "$service_path/.env" <<EOF

# Configurações específicas do Nextcloud
NEXTCLOUD_ADMIN_USER=admin
NEXTCLOUD_ADMIN_PASSWORD=admin123
NEXTCLOUD_TRUSTED_DOMAINS=$service_name.felipecncloud.com,$service_name.homelab.felipecncloud.com

# Configurações do Banco de Dados
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=nextcloud
MYSQL_USER=nextcloud
MYSQL_PASSWORD=nextcloudpass
EOF
}

# Função para criar compose de banco de dados
create_database_compose() {
    local service_name=$1
    local service_path=$2
    local image=$3
    local port=$4
    local use_traefik=$5
    
    cat > "$service_path/docker-compose.yml" <<EOF
# ===============================================
# Database Service: $service_name
# Imagem: $image
# Criado em: $(date)
# ===============================================

services:
  $service_name:
    image: $image
    container_name: $service_name
    restart: unless-stopped
    environment:
      - MYSQL_ROOT_PASSWORD=\${MYSQL_ROOT_PASSWORD:-rootpassword}
      - MYSQL_DATABASE=\${MYSQL_DATABASE:-mydb}
      - MYSQL_USER=\${MYSQL_USER:-user}
      - MYSQL_PASSWORD=\${MYSQL_PASSWORD:-password}
    volumes:
      - ./data:/var/lib/mysql
      - ./config:/etc/mysql/conf.d
      - ./logs:/var/log/mysql
    ports:
      - "\${DB_PORT:-$port}:$port"
EOF

    # Adicionar variáveis específicas de banco
    cat >> "$service_path/.env" <<EOF

# Configurações do Banco de Dados
MYSQL_ROOT_PASSWORD=rootpassword
MYSQL_DATABASE=mydb
MYSQL_USER=user
MYSQL_PASSWORD=password
DB_PORT=$port
EOF
}

# === PROCESSAMENTO DE ARGUMENTOS ===
# === PROCESSAMENTO DE ARGUMENTOS ===

# Variáveis padrão
SERVICE_NAME=""
DOCKER_IMAGE=""
SERVICE_PORT=""
BASE_PATH="$DEFAULT_BASE_PATH"
USE_TEMPLATE=""
CREATE_ENV=false
USE_SSL=false
USE_TRAEFIK=true

# Processar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -l|--list-templates)
            list_templates
            exit 0
            ;;
        -i|--image)
            DOCKER_IMAGE="$2"
            shift 2
            ;;
        -p|--port)
            SERVICE_PORT="$2"
            shift 2
            ;;
        -t|--template)
            USE_TEMPLATE="$2"
            shift 2
            ;;
        -b|--base-path)
            BASE_PATH="$2"
            shift 2
            ;;
        -e|--env-file)
            CREATE_ENV=true
            shift
            ;;
        -s|--ssl)
            USE_SSL=true
            shift
            ;;
        -n|--no-traefik)
            USE_TRAEFIK=false
            shift
            ;;
        -*)
            print_error "Opção desconhecida: $1"
            echo "Use '$0 --help' para ajuda."
            exit 1
            ;;
        *)
            if [ -z "$SERVICE_NAME" ]; then
                SERVICE_NAME="$1"
            else
                print_error "Muitos argumentos fornecidos!"
                exit 1
            fi
            shift
            ;;
    esac
done

# Verificar se o nome do serviço foi fornecido
if [ -z "$SERVICE_NAME" ]; then
    print_header
    print_error "Nome do serviço não fornecido!"
    echo
    print_color "WHITE" "USO: $0 <nome_servico> [opções]"
    echo
    print_info "Use '$0 --help' para mais informações."
    exit 1
fi

print_header

# === VALIDAÇÕES ===

print_info "Validando parâmetros..."

# Validar nome do serviço
if ! validate_service_name "$SERVICE_NAME"; then
    print_error "Nome de serviço inválido: '$SERVICE_NAME'"
    print_info "O nome deve conter apenas letras, números e hífens, máximo 63 caracteres."
    exit 1
fi

# Definir valores baseados no template ou padrões
if [ -n "$USE_TEMPLATE" ]; then
    if [[ ! -v SERVICE_TEMPLATES[$USE_TEMPLATE] ]]; then
        print_error "Template '$USE_TEMPLATE' não encontrado!"
        print_info "Use '$0 --list-templates' para ver templates disponíveis."
        exit 1
    fi
    
    IFS='|' read -r template_image template_port template_category <<< "${SERVICE_TEMPLATES[$USE_TEMPLATE]}"
    
    # Usar valores do template se não foram especificados
    DOCKER_IMAGE="${DOCKER_IMAGE:-$template_image}"
    SERVICE_PORT="${SERVICE_PORT:-$template_port}"
    
    print_info "Usando template: $USE_TEMPLATE ($template_category)"
else
    # Usar valores padrão se não foram especificados
    DOCKER_IMAGE="${DOCKER_IMAGE:-$DEFAULT_IMAGE}"
    SERVICE_PORT="${SERVICE_PORT:-$DEFAULT_PORT}"
fi

# Validar porta
if ! validate_port "$SERVICE_PORT"; then
    print_error "Porta inválida: '$SERVICE_PORT' (deve ser entre 1-65535)"
    exit 1
fi

print_success "Parâmetros validados com sucesso!"

# === CRIAÇÃO DO SERVIÇO ===

SERVICE_PATH="$BASE_PATH/$SERVICE_NAME"

print_info "Configurando serviço..."
echo
print_color "PURPLE" "📋 RESUMO DA CONFIGURAÇÃO:"
echo "  🏷️  Nome: $SERVICE_NAME"
echo "  🐳 Imagem: $DOCKER_IMAGE"
echo "  🔌 Porta: $SERVICE_PORT"
echo "  📁 Caminho: $SERVICE_PATH"
echo "  🌐 Traefik: $([ "$USE_TRAEFIK" = true ] && echo "Habilitado" || echo "Desabilitado")"
echo "  🔒 SSL: $([ "$USE_SSL" = true ] && echo "Habilitado" || echo "Desabilitado")"
if [ -n "$USE_TEMPLATE" ]; then
    echo "  📦 Template: $USE_TEMPLATE"
fi
echo
# Verificar se o diretório já existe
if [ -d "$SERVICE_PATH" ]; then
    print_warning "Diretório $SERVICE_PATH já existe!"
    print_info "Deseja continuar e sobrescrever? (s/N)"
    read -r response
    if [[ ! "$response" =~ ^[Ss]$ ]]; then
        print_info "Operação cancelada."
        exit 0
    fi
fi

print_info "Criando estrutura de diretórios..."

# Criar estrutura de diretórios (tentar sem sudo primeiro)
if mkdir -p "$SERVICE_PATH"/{data,config,logs} 2>/dev/null; then
    print_success "Estrutura de diretórios criada!"
else
    print_warning "Permissões necessárias, tentando com sudo..."
    if sudo mkdir -p "$SERVICE_PATH"/{data,config,logs}; then
        print_success "Estrutura de diretórios criada com sudo!"
    else
        print_error "Erro ao criar o diretório $SERVICE_PATH"
        print_info "Verifique se você tem permissões adequadas"
        exit 1
    fi
fi

# Verificar se a criação foi bem-sucedida
if [ ! -d "$SERVICE_PATH" ]; then
    print_error "Erro ao criar o diretório $SERVICE_PATH"
    print_info "Verifique se você tem permissões adequadas"
    exit 1
fi

# Navegar para o diretório do serviço
cd "$SERVICE_PATH"

print_info "Gerando arquivos de configuração..."

# Criar arquivo .env se solicitado ou se usando template específico
if [ "$CREATE_ENV" = true ] || [ -n "$USE_TEMPLATE" ]; then
    create_env_file "$SERVICE_PATH" "$SERVICE_NAME"
fi

# Criar docker-compose baseado no template ou genérico
if [ -n "$USE_TEMPLATE" ]; then
    create_compose_from_template "$SERVICE_NAME" "$USE_TEMPLATE" "$SERVICE_PATH" "$USE_SSL" "$USE_TRAEFIK"
else
    create_generic_compose "$SERVICE_NAME" "$SERVICE_PATH" "$DOCKER_IMAGE" "$SERVICE_PORT" "$([ "$USE_SSL" = true ] && echo "websecure" || echo "web")" "$USE_TRAEFIK"
fi

print_success "Docker Compose criado!"

# Criar script de inicialização
print_info "Criando scripts auxiliares..."

# Função para criar script com tratamento de erro
create_script() {
    local script_name=$1
    local script_content=$2
    local script_path="$SERVICE_PATH/$script_name"
    
    # Tentar criar o script normalmente
    if echo "$script_content" > "$script_path" 2>/dev/null; then
        chmod +x "$script_path" 2>/dev/null
        return 0
    else
        # Se falhar, tentar com sudo
        if echo "$script_content" | sudo tee "$script_path" > /dev/null 2>&1; then
            sudo chmod +x "$script_path" 2>/dev/null
            return 0
        else
            print_warning "Falha ao criar $script_name"
            return 1
        fi
    fi
}

# Conteúdo do start.sh
START_SCRIPT='#!/bin/bash
# Script para iniciar o serviço '"$SERVICE_NAME"'

echo "🚀 Iniciando '"$SERVICE_NAME"'..."
docker compose up -d

echo "📊 Status dos containers:"
docker compose ps

echo "📋 Logs (últimas 20 linhas):"
docker compose logs --tail=20'

# Conteúdo do stop.sh
STOP_SCRIPT='#!/bin/bash
# Script para parar o serviço '"$SERVICE_NAME"'

echo "🛑 Parando '"$SERVICE_NAME"'..."
docker compose down

echo "🧹 Removendo containers órfãos..."
docker compose down --remove-orphans'

# Conteúdo do update.sh
UPDATE_SCRIPT='#!/bin/bash
# Script para atualizar o serviço '"$SERVICE_NAME"'

echo "📥 Atualizando imagens..."
docker compose pull

echo "🔄 Reiniciando serviço..."
docker compose down
docker compose up -d

echo "✅ Atualização concluída!"'

# Criar os scripts
scripts_created=0
if create_script "start.sh" "$START_SCRIPT"; then
    ((scripts_created++))
fi

if create_script "stop.sh" "$STOP_SCRIPT"; then
    ((scripts_created++))
fi

if create_script "update.sh" "$UPDATE_SCRIPT"; then
    ((scripts_created++))
fi

# Verificar quantos scripts foram criados
if [ $scripts_created -eq 3 ]; then
    print_success "Scripts auxiliares criados com sucesso!"
elif [ $scripts_created -gt 0 ]; then
    print_warning "$scripts_created de 3 scripts criados com sucesso"
else
    print_error "Não foi possível criar nenhum script auxiliar"
    print_info "Verifique as permissões do diretório $SERVICE_PATH"
fi

# === FINALIZAÇÃO ===

echo
print_color "CYAN" "🎉 SERVIÇO CRIADO COM SUCESSO!"
echo

# Mostrar estrutura criada
print_info "Estrutura criada:"
echo "📁 $SERVICE_PATH/"
echo "├── � docker-compose.yml"
if [ "$CREATE_ENV" = true ] || [ -n "$USE_TEMPLATE" ]; then
    echo "├── ⚙️  .env"
fi
echo "├── 📂 data/"
echo "├── 📂 config/"
echo "├── 📂 logs/"
if [ "$USE_TEMPLATE" = "nextcloud" ]; then
    echo "├── 📂 database/"
fi
echo "├── 🚀 start.sh"
echo "├── 🛑 stop.sh"
echo "└── 🔄 update.sh"

echo
print_info "URLs de acesso:"
if [ "$USE_TRAEFIK" = true ]; then
    protocol="http"
    if [ "$USE_SSL" = true ]; then
        protocol="https"
    fi
    echo "  🌐 Externa: $protocol://$SERVICE_NAME.felipecncloud.com"
    echo "  🏠 Interna: $protocol://$SERVICE_NAME.homelab.felipecncloud.com"
else
    echo "  🔌 Local: http://localhost:$SERVICE_PORT"
fi

echo
print_info "Próximos passos:"
echo "  1. Ajustar configurações em docker-compose.yml"
if [ "$CREATE_ENV" = true ] || [ -n "$USE_TEMPLATE" ]; then
    echo "  2. Configurar variáveis no arquivo .env"
fi
echo "  3. Iniciar o serviço: cd $SERVICE_PATH && ./start.sh"
if [ "$USE_TRAEFIK" = true ]; then
    echo "  4. Configurar DNS: $PWD/add_entry_traefik.sh -a add $SERVICE_NAME"
fi

echo
print_color "GREEN" "✨ Pronto para usar!"

exit 0

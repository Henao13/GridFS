#!/bin/bash

# GridDFS Master Deployment Script for AWS EC2
# Este script despliega todo el sistema GridDFS en AWS EC2 de forma automatizada
# 
# Uso: ./deploy-griddfs-aws.sh [opciones]
#
# Requiere: AWS CLI configurado, keypair disponible, VPC configurado

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_input() { echo -e "${BLUE}[INPUT]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }

# Banner
echo -e "${PURPLE}"
cat << "EOF"
┌─────────────────────────────────────────┐
│         GridDFS AWS Deployment          │
│     Sistema de Archivos Distribuido     │
└─────────────────────────────────────────┘
EOF
echo -e "${NC}"

# Configuración por defecto
AMI_ID="ami-0c02fb55956c7d316"  # Ubuntu 22.04 LTS
KEYPAIR_NAME=""
SECURITY_GROUP="griddfs-sg"
NAMENODE_INSTANCE_TYPE="t3.small"
DATANODE_INSTANCE_TYPE="t3.medium"
CLIENT_INSTANCE_TYPE="t3.micro"
NUM_DATANODES=2
REPO_URL=""

# Función para mostrar ayuda
show_help() {
cat << EOF
GridDFS AWS Deployment Script

Uso: $0 [opciones]

Opciones:
  -k, --keypair NAME          Nombre del keypair de AWS (obligatorio)
  -r, --repo URL              URL del repositorio Git del proyecto
  -s, --security-group NAME   Nombre del security group (default: griddfs-sg)
  -n, --num-datanodes N       Número de DataNodes a crear (default: 2)
  --namenode-type TYPE        Tipo de instancia NameNode (default: t3.small)
  --datanode-type TYPE        Tipo de instancia DataNode (default: t3.medium)
  --client-type TYPE          Tipo de instancia Cliente (default: t3.micro)
  -h, --help                  Mostrar esta ayuda

Ejemplos:
  $0 -k mi-keypair -r https://github.com/usuario/griddfs.git
  $0 -k mi-keypair -n 3 -s mi-security-group

Prerrequisitos:
  - AWS CLI configurado (aws configure)
  - Keypair disponible en la región
  - VPC configurado
EOF
}

# Parsear argumentos
while [[ $# -gt 0 ]]; do
  case $1 in
    -k|--keypair)
      KEYPAIR_NAME="$2"
      shift 2
      ;;
    -r|--repo)
      REPO_URL="$2"
      shift 2
      ;;
    -s|--security-group)
      SECURITY_GROUP="$2"
      shift 2
      ;;
    -n|--num-datanodes)
      NUM_DATANODES="$2"
      shift 2
      ;;
    --namenode-type)
      NAMENODE_INSTANCE_TYPE="$2"
      shift 2
      ;;
    --datanode-type)
      DATANODE_INSTANCE_TYPE="$2"
      shift 2
      ;;
    --client-type)
      CLIENT_INSTANCE_TYPE="$2"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      log_error "Opción desconocida: $1"
      show_help
      exit 1
      ;;
  esac
done

# Validar parámetros requeridos
if [[ -z "$KEYPAIR_NAME" ]]; then
  log_error "El keypair es obligatorio. Usa -k nombre-keypair"
  exit 1
fi

# Verificar AWS CLI
if ! command -v aws &> /dev/null; then
  log_error "AWS CLI no está instalado. Instálalo con: pip install awscli"
  exit 1
fi

# Verificar configuración AWS
if ! aws sts get-caller-identity &> /dev/null; then
  log_error "AWS CLI no está configurado. Ejecuta: aws configure"
  exit 1
fi

# Mostrar configuración
log_info "📋 Configuración del despliegue:"
log_info "  Keypair: $KEYPAIR_NAME"
log_info "  Security Group: $SECURITY_GROUP"
log_info "  NameNode: $NAMENODE_INSTANCE_TYPE"
log_info "  DataNodes: $NUM_DATANODES x $DATANODE_INSTANCE_TYPE"
log_info "  Cliente: $CLIENT_INSTANCE_TYPE"
log_info "  Repositorio: ${REPO_URL:-"Manual upload"}"
echo

# Confirmar despliegue
log_input "¿Continuar con el despliegue? (y/N): "
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  log_info "Despliegue cancelado"
  exit 0
fi

# Variables para tracking de instancias
NAMENODE_INSTANCE_ID=""
DATANODE_INSTANCE_IDS=()
CLIENT_INSTANCE_ID=""

# Función de limpieza en caso de error
cleanup() {
  log_warning "🧹 Limpiando recursos creados..."
  
  # Terminar instancias creadas
  INSTANCES_TO_TERMINATE=()
  [[ -n "$NAMENODE_INSTANCE_ID" ]] && INSTANCES_TO_TERMINATE+=("$NAMENODE_INSTANCE_ID")
  [[ -n "$CLIENT_INSTANCE_ID" ]] && INSTANCES_TO_TERMINATE+=("$CLIENT_INSTANCE_ID")
  for instance_id in "${DATANODE_INSTANCE_IDS[@]}"; do
    INSTANCES_TO_TERMINATE+=("$instance_id")
  done
  
  if [[ ${#INSTANCES_TO_TERMINATE[@]} -gt 0 ]]; then
    log_warning "Terminando instancias: ${INSTANCES_TO_TERMINATE[*]}"
    aws ec2 terminate-instances --instance-ids "${INSTANCES_TO_TERMINATE[@]}" || true
  fi
}

# Configurar trap para cleanup
trap cleanup EXIT

# Paso 1: Crear o verificar Security Group
log_step "1️⃣  Configurando Security Group..."

if aws ec2 describe-security-groups --group-names "$SECURITY_GROUP" &> /dev/null; then
  log_info "Security Group '$SECURITY_GROUP' ya existe"
else
  log_info "Creando Security Group '$SECURITY_GROUP'..."
  aws ec2 create-security-group \
    --group-name "$SECURITY_GROUP" \
    --description "Security group for GridDFS distributed file system"
  
  # Obtener IP pública actual
  MY_IP=$(curl -s http://checkip.amazonaws.com)/32
  
  # Agregar reglas SSH
  aws ec2 authorize-security-group-ingress \
    --group-name "$SECURITY_GROUP" \
    --protocol tcp --port 22 --cidr 0.0.0.0/0
  
  # Agregar reglas gRPC internas
  aws ec2 authorize-security-group-ingress \
    --group-name "$SECURITY_GROUP" \
    --protocol tcp --port 50050 --source-group "$SECURITY_GROUP"
  
  aws ec2 authorize-security-group-ingress \
    --group-name "$SECURITY_GROUP" \
    --protocol tcp --port 50051 --source-group "$SECURITY_GROUP"
  
  # Agregar reglas de acceso externo
  aws ec2 authorize-security-group-ingress \
    --group-name "$SECURITY_GROUP" \
    --protocol tcp --port 50050 --cidr "$MY_IP"
  
  aws ec2 authorize-security-group-ingress \
    --group-name "$SECURITY_GROUP" \
    --protocol tcp --port 50051 --cidr "$MY_IP"
  
  log_info "Security Group configurado para IP: $MY_IP"
fi

# Paso 2: Crear instancia NameNode
log_step "2️⃣  Creando instancia NameNode..."

NAMENODE_RESULT=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$NAMENODE_INSTANCE_TYPE" \
  --key-name "$KEYPAIR_NAME" \
  --security-groups "$SECURITY_GROUP" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=griddfs-namenode}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

NAMENODE_INSTANCE_ID="$NAMENODE_RESULT"
log_info "NameNode creado: $NAMENODE_INSTANCE_ID"

# Paso 3: Crear instancias DataNode
log_step "3️⃣  Creando $NUM_DATANODES instancias DataNode..."

for i in $(seq 1 "$NUM_DATANODES"); do
  DATANODE_RESULT=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --count 1 \
    --instance-type "$DATANODE_INSTANCE_TYPE" \
    --key-name "$KEYPAIR_NAME" \
    --security-groups "$SECURITY_GROUP" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=griddfs-datanode-$i}]" \
    --query 'Instances[0].InstanceId' \
    --output text)
  
  DATANODE_INSTANCE_IDS+=("$DATANODE_RESULT")
  log_info "DataNode $i creado: $DATANODE_RESULT"
done

# Paso 4: Crear instancia Cliente
log_step "4️⃣  Creando instancia Cliente..."

CLIENT_RESULT=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --count 1 \
  --instance-type "$CLIENT_INSTANCE_TYPE" \
  --key-name "$KEYPAIR_NAME" \
  --security-groups "$SECURITY_GROUP" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=griddfs-client}]" \
  --query 'Instances[0].InstanceId' \
  --output text)

CLIENT_INSTANCE_ID="$CLIENT_RESULT"
log_info "Cliente creado: $CLIENT_INSTANCE_ID"

# Paso 5: Esperar a que las instancias estén ejecutándose
log_step "5️⃣  Esperando a que las instancias estén listas..."

ALL_INSTANCES=("$NAMENODE_INSTANCE_ID" "${DATANODE_INSTANCE_IDS[@]}" "$CLIENT_INSTANCE_ID")

log_info "Esperando a que las instancias estén en estado 'running'..."
aws ec2 wait instance-running --instance-ids "${ALL_INSTANCES[@]}"

log_info "Esperando a que las verificaciones de estado pasen..."
aws ec2 wait instance-status-ok --instance-ids "${ALL_INSTANCES[@]}"

log_info "✅ Todas las instancias están listas!"

# Paso 6: Obtener IPs
log_step "6️⃣  Obteniendo direcciones IP..."

NAMENODE_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$NAMENODE_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

NAMENODE_PRIVATE_IP=$(aws ec2 describe-instances \
  --instance-ids "$NAMENODE_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

CLIENT_PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$CLIENT_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

DATANODE_PUBLIC_IPS=()
DATANODE_PRIVATE_IPS=()

for instance_id in "${DATANODE_INSTANCE_IDS[@]}"; do
  public_ip=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  
  private_ip=$(aws ec2 describe-instances \
    --instance-ids "$instance_id" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text)
  
  DATANODE_PUBLIC_IPS+=("$public_ip")
  DATANODE_PRIVATE_IPS+=("$private_ip")
done

# Mostrar información de las instancias
log_info "📊 Instancias creadas:"
log_info "  NameNode:    $NAMENODE_INSTANCE_ID ($NAMENODE_PUBLIC_IP | $NAMENODE_PRIVATE_IP)"
for i in "${!DATANODE_INSTANCE_IDS[@]}"; do
  log_info "  DataNode $((i+1)): ${DATANODE_INSTANCE_IDS[i]} (${DATANODE_PUBLIC_IPS[i]} | ${DATANODE_PRIVATE_IPS[i]})"
done
log_info "  Cliente:     $CLIENT_INSTANCE_ID ($CLIENT_PUBLIC_IP)"

# Paso 7: Desplegar NameNode
log_step "7️⃣  Desplegando NameNode..."

log_info "Conectando a NameNode y ejecutando instalación..."
ssh -i "$HOME/.ssh/$KEYPAIR_NAME.pem" -o StrictHostKeyChecking=no ubuntu@"$NAMENODE_PUBLIC_IP" << EOF
export REPO_URL="$REPO_URL"
curl -sSL https://raw.githubusercontent.com/tu-usuario/griddfs/main/scripts/install-namenode.sh | bash
sudo systemctl start griddfs-namenode
sleep 5
sudo systemctl status griddfs-namenode
EOF

log_info "✅ NameNode desplegado y iniciado"

# Paso 8: Desplegar DataNodes
log_step "8️⃣  Desplegando DataNodes..."

for i in "${!DATANODE_INSTANCE_IDS[@]}"; do
  log_info "Desplegando DataNode $((i+1))..."
  
  ssh -i "$HOME/.ssh/$KEYPAIR_NAME.pem" -o StrictHostKeyChecking=no ubuntu@"${DATANODE_PUBLIC_IPS[i]}" << EOF
export REPO_URL="$REPO_URL"
export NAMENODE_HOST="$NAMENODE_PRIVATE_IP"
curl -sSL https://raw.githubusercontent.com/tu-usuario/griddfs/main/scripts/install-datanode.sh | bash
sudo systemctl start griddfs-datanode
sleep 5
sudo systemctl status griddfs-datanode
EOF
  
  log_info "✅ DataNode $((i+1)) desplegado y iniciado"
done

# Paso 9: Desplegar Cliente
log_step "9️⃣  Desplegando Cliente..."

ssh -i "$HOME/.ssh/$KEYPAIR_NAME.pem" -o StrictHostKeyChecking=no ubuntu@"$CLIENT_PUBLIC_IP" << EOF
export REPO_URL="$REPO_URL"
export NAMENODE_HOST="$NAMENODE_PUBLIC_IP"
export DATANODE_HOST="${DATANODE_PUBLIC_IPS[0]}"
curl -sSL https://raw.githubusercontent.com/tu-usuario/griddfs/main/scripts/install-client.sh | bash
EOF

log_info "✅ Cliente desplegado"

# Paso 10: Verificación final
log_step "🔍 Verificación final del sistema..."

# Crear archivo de configuración local
cat > griddfs-deployment.txt << EOF
GridDFS Deployment Information
==============================
Deployment Date: $(date)
Keypair: $KEYPAIR_NAME
Security Group: $SECURITY_GROUP

NameNode:
  Instance ID: $NAMENODE_INSTANCE_ID
  Public IP: $NAMENODE_PUBLIC_IP
  Private IP: $NAMENODE_PRIVATE_IP
  Port: 50050

DataNodes:
EOF

for i in "${!DATANODE_INSTANCE_IDS[@]}"; do
  cat >> griddfs-deployment.txt << EOF
  DataNode $((i+1)):
    Instance ID: ${DATANODE_INSTANCE_IDS[i]}
    Public IP: ${DATANODE_PUBLIC_IPS[i]}
    Private IP: ${DATANODE_PRIVATE_IPS[i]}
    Port: 50051
EOF
done

cat >> griddfs-deployment.txt << EOF

Client:
  Instance ID: $CLIENT_INSTANCE_ID
  Public IP: $CLIENT_PUBLIC_IP

Connection Commands:
  ssh -i ~/.ssh/$KEYPAIR_NAME.pem ubuntu@$NAMENODE_PUBLIC_IP    # NameNode
  ssh -i ~/.ssh/$KEYPAIR_NAME.pem ubuntu@$CLIENT_PUBLIC_IP      # Cliente

Test Commands (run on client):
  griddfs register testuser testpass
  griddfs login testuser testpass
  griddfs put /etc/hostname /test.txt
  griddfs list /
  griddfs get /test.txt downloaded.txt

Monitoring Commands:
  sudo journalctl -u griddfs-namenode -f    # NameNode logs
  sudo journalctl -u griddfs-datanode -f    # DataNode logs
EOF

# Desactivar trap de limpieza (despliegue exitoso)
trap - EXIT

log_info "🎉 ¡Despliegue de GridDFS completado exitosamente!"
echo
log_info "📄 Información del despliegue guardada en: griddfs-deployment.txt"
echo
log_info "🚀 Próximos pasos:"
log_info "1. Conectar al cliente: ssh -i ~/.ssh/$KEYPAIR_NAME.pem ubuntu@$CLIENT_PUBLIC_IP"
log_info "2. Probar el sistema:"
log_info "   griddfs register usuario password"
log_info "   griddfs login usuario password"
log_info "   griddfs put archivo.txt /archivo.txt"
log_info "   griddfs list /"
echo
log_info "🔧 Para monitoreo:"
log_info "   NameNode logs: ssh ubuntu@$NAMENODE_PUBLIC_IP 'sudo journalctl -u griddfs-namenode -f'"
log_info "   DataNode logs: ssh ubuntu@${DATANODE_PUBLIC_IPS[0]} 'sudo journalctl -u griddfs-datanode -f'"
echo
log_warning "💰 Recuerda terminar las instancias cuando no las necesites para evitar costos:"
log_warning "   aws ec2 terminate-instances --instance-ids ${ALL_INSTANCES[*]}"
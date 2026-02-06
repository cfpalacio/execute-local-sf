#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PARENT_DIR="$(dirname "$PROJECT_ROOT")"

LOCALSTACK_ENDPOINT="http://localhost:4566"
AWS_REGION="us-east-1"
DYNAMODB_TABLE_CHUNKS="smartpay-chunks"
DYNAMODB_TABLE_RESULTS="smartpay-resultados"

echo -e "${YELLOW}=== SmartPay Liquidacion - Despliegue Local ===${NC}"

echo -e "${YELLOW}Verificando LocalStack...${NC}"
if ! curl -s "$LOCALSTACK_ENDPOINT/_localstack/health" > /dev/null 2>&1; then
    echo -e "${RED}Error: LocalStack no esta corriendo. Ejecute: docker-compose up -d${NC}"
    exit 1
fi
echo -e "${GREEN}LocalStack esta activo${NC}"

# Create DynamoDB tables
echo -e "${YELLOW}Creando tabla DynamoDB de chunks...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb create-table \
    --table-name "$DYNAMODB_TABLE_CHUNKS" \
    --attribute-definitions \
        AttributeName=PK,AttributeType=S \
        AttributeName=SK,AttributeType=S \
    --key-schema \
        AttributeName=PK,KeyType=HASH \
        AttributeName=SK,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION" 2>/dev/null || echo -e "${GREEN}Tabla chunks ya existe${NC}"
echo -e "${GREEN}Tabla DynamoDB chunks creada/verificada${NC}"

echo -e "${YELLOW}Creando tabla DynamoDB de resultados...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb create-table \
    --table-name "$DYNAMODB_TABLE_RESULTS" \
    --attribute-definitions \
        AttributeName=PK,AttributeType=S \
        AttributeName=SK,AttributeType=S \
    --key-schema \
        AttributeName=PK,KeyType=HASH \
        AttributeName=SK,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION" 2>/dev/null || echo -e "${GREEN}Tabla resultados ya existe${NC}"
echo -e "${GREEN}Tabla DynamoDB resultados creada/verificada${NC}"

deploy_lambda() {
    local LAMBDA_DIR=$1
    local LAMBDA_NAME=$2

    echo -e "${YELLOW}Desplegando $LAMBDA_NAME...${NC}"

    cd "$PARENT_DIR/$LAMBDA_DIR"

    rm -rf package function.zip
    mkdir -p package

    if [ -f "requirements.txt" ]; then
        python3 -m pip install -r requirements.txt -t package --platform manylinux2014_x86_64 --only-binary=:all: --quiet 2>/dev/null || \
        python3 -m pip install -r requirements.txt -t package --quiet
    fi

    cp -r src/* package/

    cd package
    zip -r "../function.zip" . -x "*.pyc" -x "__pycache__/*" > /dev/null
    cd ..

    aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda create-function \
        --function-name "$LAMBDA_NAME" \
        --runtime python3.12 \
        --handler lambda_handler.lambda_handler \
        --zip-file fileb://function.zip \
        --role arn:aws:iam::000000000000:role/lambda-role \
        --region "$AWS_REGION" \
        --timeout 30 \
        --memory-size 256 \
        2>/dev/null || \
    aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda update-function-code \
        --function-name "$LAMBDA_NAME" \
        --zip-file fileb://function.zip \
        --region "$AWS_REGION" > /dev/null

    rm -rf package function.zip
    echo -e "${GREEN}$LAMBDA_NAME desplegada${NC}"
}

deploy_lambda "lambda-calculo-ingresos" "smartpay-calculo-ingresos-local"
deploy_lambda "lambda-calculo-base-gravable" "smartpay-calculo-base-gravable-local"
deploy_lambda "lambda-calculo-seguridad-social" "smartpay-calculo-seguridad-social-local"
deploy_lambda "lambda-calculo-otras-deducciones" "smartpay-calculo-otras-deducciones-local"
deploy_lambda "lambda-calculo-capacidad-endeudamiento" "smartpay-calculo-capacidad-endeudamiento-local"
deploy_lambda "lambda-escritura-dynamo" "smartpay-escritura-dynamo-local"
deploy_lambda "lambda-lectura" "smartpay-lectura-local"
deploy_lambda "lambda-lectura-chunk" "smartpay-lectura-chunk-local"

# Configure environment variables for DynamoDB Lambda
# Note: Lambda runs inside Docker, so it needs host.docker.internal to reach LocalStack
LAMBDA_DYNAMODB_ENDPOINT="http://host.docker.internal:4566"
echo -e "${YELLOW}Configurando variables de entorno para Lambda DynamoDB...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda update-function-configuration \
    --function-name "smartpay-escritura-dynamo-local" \
    --environment "Variables={DYNAMODB_ENDPOINT_URL=$LAMBDA_DYNAMODB_ENDPOINT,DYNAMODB_TABLE_RESULTS=$DYNAMODB_TABLE_RESULTS,DYNAMODB_TABLE_CHUNKS=$DYNAMODB_TABLE_CHUNKS,AWS_REGION=$AWS_REGION}" \
    --region "$AWS_REGION" > /dev/null
echo -e "${GREEN}Variables de entorno configuradas${NC}"

# Configure environment variables for Lambda Lectura (PostgreSQL + DynamoDB)
DB_HOST="${DB_HOST:-host.docker.internal}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-smartpay}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-password}"
DB_SCHEMA="${DB_SCHEMA:-esquema_liquidacion}"
echo -e "${YELLOW}Configurando variables de entorno para Lambda Lectura...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda update-function-configuration \
    --function-name "smartpay-lectura-local" \
    --environment "Variables={DB_HOST=$DB_HOST,DB_PORT=$DB_PORT,DB_NAME=$DB_NAME,DB_USER=$DB_USER,DB_PASSWORD=$DB_PASSWORD,DB_SCHEMA=$DB_SCHEMA,DYNAMODB_ENDPOINT_URL=$LAMBDA_DYNAMODB_ENDPOINT,DYNAMODB_TABLE_NAME=$DYNAMODB_TABLE_CHUNKS,AWS_REGION=$AWS_REGION}" \
    --region "$AWS_REGION" > /dev/null
echo -e "${GREEN}Variables de entorno para Lambda Lectura configuradas${NC}"

echo -e "${YELLOW}Configurando variables de entorno para Lambda Lectura Chunk...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda update-function-configuration \
    --function-name "smartpay-lectura-chunk-local" \
    --environment "Variables={DYNAMODB_ENDPOINT_URL=$LAMBDA_DYNAMODB_ENDPOINT,DYNAMODB_TABLE_NAME=$DYNAMODB_TABLE_CHUNKS,AWS_REGION=$AWS_REGION}" \
    --region "$AWS_REGION" > /dev/null
echo -e "${GREEN}Variables de entorno para Lambda Lectura Chunk configuradas${NC}"

echo -e "${YELLOW}Obteniendo ARNs de las Lambdas...${NC}"
LAMBDA_INGRESOS_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function --function-name smartpay-calculo-ingresos-local --query 'Configuration.FunctionArn' --output text --region "$AWS_REGION")
LAMBDA_BASE_GRAVABLE_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function --function-name smartpay-calculo-base-gravable-local --query 'Configuration.FunctionArn' --output text --region "$AWS_REGION")
LAMBDA_SEGURIDAD_SOCIAL_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function --function-name smartpay-calculo-seguridad-social-local --query 'Configuration.FunctionArn' --output text --region "$AWS_REGION")
LAMBDA_OTRAS_DEDUCCIONES_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function --function-name smartpay-calculo-otras-deducciones-local --query 'Configuration.FunctionArn' --output text --region "$AWS_REGION")
LAMBDA_CAPACIDAD_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function --function-name smartpay-calculo-capacidad-endeudamiento-local --query 'Configuration.FunctionArn' --output text --region "$AWS_REGION")
LAMBDA_ESCRITURA_DYNAMO_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function --function-name smartpay-escritura-dynamo-local --query 'Configuration.FunctionArn' --output text --region "$AWS_REGION")
LAMBDA_LECTURA_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function --function-name smartpay-lectura-local --query 'Configuration.FunctionArn' --output text --region "$AWS_REGION")
LAMBDA_LECTURA_CHUNK_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" lambda get-function --function-name smartpay-lectura-chunk-local --query 'Configuration.FunctionArn' --output text --region "$AWS_REGION")

echo -e "${YELLOW}Creando IAM Role para Step Functions...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" iam create-role \
    --role-name smartpay-sfn-role \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"states.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
    --region "$AWS_REGION" 2>/dev/null || true

echo -e "${YELLOW}Procesando definicion de la maquina de estados...${NC}"
cd "$PROJECT_ROOT"

DEFINITION=$(cat statemachine/liquidacion.asl.json | \
    sed "s|\${LambdaLecturaArn}|$LAMBDA_LECTURA_ARN|g" | \
    sed "s|\${LambdaLecturaChunkArn}|$LAMBDA_LECTURA_CHUNK_ARN|g" | \
    sed "s|\${LambdaCalculoIngresosArn}|$LAMBDA_INGRESOS_ARN|g" | \
    sed "s|\${LambdaCalculoBaseGravableArn}|$LAMBDA_BASE_GRAVABLE_ARN|g" | \
    sed "s|\${LambdaCalculoSeguridadSocialArn}|$LAMBDA_SEGURIDAD_SOCIAL_ARN|g" | \
    sed "s|\${LambdaCalculoOtrasDeduccionesArn}|$LAMBDA_OTRAS_DEDUCCIONES_ARN|g" | \
    sed "s|\${LambdaCalculoCapacidadEndeudamientoArn}|$LAMBDA_CAPACIDAD_ARN|g" | \
    sed "s|\${LambdaEscrituraDynamoArn}|$LAMBDA_ESCRITURA_DYNAMO_ARN|g")

echo -e "${YELLOW}Creando/Actualizando maquina de estados...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" stepfunctions create-state-machine \
    --name "smartpay-flujo-liquidacion-local" \
    --definition "$DEFINITION" \
    --role-arn "arn:aws:iam::000000000000:role/smartpay-sfn-role" \
    --region "$AWS_REGION" 2>/dev/null || \
aws --endpoint-url="$LOCALSTACK_ENDPOINT" stepfunctions update-state-machine \
    --state-machine-arn "arn:aws:states:$AWS_REGION:000000000000:stateMachine:smartpay-flujo-liquidacion-local" \
    --definition "$DEFINITION" \
    --region "$AWS_REGION" > /dev/null

STATE_MACHINE_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" stepfunctions list-state-machines \
    --query "stateMachines[?name=='smartpay-flujo-liquidacion-local'].stateMachineArn" \
    --output text --region "$AWS_REGION")

echo ""
echo -e "${GREEN}=== Despliegue Completado ===${NC}"
echo -e "${GREEN}State Machine ARN: $STATE_MACHINE_ARN${NC}"
echo -e "${GREEN}DynamoDB Table Chunks: $DYNAMODB_TABLE_CHUNKS${NC}"
echo -e "${GREEN}DynamoDB Table Results: $DYNAMODB_TABLE_RESULTS${NC}"
echo ""
echo -e "Para iniciar una ejecucion:"
echo -e "  ${YELLOW}./scripts/start-execution.sh${NC}"

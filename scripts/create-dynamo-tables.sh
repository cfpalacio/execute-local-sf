#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOCALSTACK_ENDPOINT="http://localhost:4566"
AWS_REGION="us-east-1"
DYNAMODB_TABLE_PARAMETROS="dynamodb-smartpay-preliquidacion-parametros"
DYNAMODB_TABLE_PLAN_PAGOS="dynamodb-smartpay-registro-plan-pagos"

echo -e "${YELLOW}=== Creando tablas DynamoDB ===${NC}"

echo -e "${YELLOW}Verificando LocalStack...${NC}"
if ! curl -s "$LOCALSTACK_ENDPOINT/_localstack/health" > /dev/null 2>&1; then
    echo -e "${RED}Error: LocalStack no esta corriendo. Ejecute: docker-compose up -d${NC}"
    exit 1
fi
echo -e "${GREEN}LocalStack esta activo${NC}"

echo -e "${YELLOW}Creando tabla DynamoDB de parametros de preliquidacion...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb create-table \
    --table-name "$DYNAMODB_TABLE_PARAMETROS" \
    --attribute-definitions \
        AttributeName=execution_key,AttributeType=S \
    --key-schema \
        AttributeName=execution_key,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION" 2>/dev/null || echo -e "${GREEN}Tabla parametros ya existe${NC}"
echo -e "${GREEN}Tabla DynamoDB parametros creada/verificada${NC}"

echo -e "${YELLOW}Creando tabla DynamoDB de registro plan de pagos...${NC}"
aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb create-table \
    --table-name "$DYNAMODB_TABLE_PLAN_PAGOS" \
    --attribute-definitions \
        AttributeName=id_participante,AttributeType=S \
        AttributeName=id_solicitud_pago,AttributeType=S \
    --key-schema \
        AttributeName=id_participante,KeyType=HASH \
        AttributeName=id_solicitud_pago,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region "$AWS_REGION" 2>/dev/null || echo -e "${GREEN}Tabla plan de pagos ya existe${NC}"
echo -e "${GREEN}Tabla DynamoDB plan de pagos creada/verificada${NC}"

echo ""
echo -e "${GREEN}=== Tablas DynamoDB creadas ===${NC}"
echo -e "${GREEN}Tabla Parametros: $DYNAMODB_TABLE_PARAMETROS${NC}"
echo -e "${GREEN}Tabla Plan Pagos: $DYNAMODB_TABLE_PLAN_PAGOS${NC}"

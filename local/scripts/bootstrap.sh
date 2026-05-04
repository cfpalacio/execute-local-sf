#!/bin/bash
# Crea las tablas DynamoDB y la cola SQS necesarias para correr la maquina de
# estados localmente. Idempotente: si ya existen, no falla.
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

DYNAMODB_ENDPOINT="http://localhost:8000"
SQS_ENDPOINT="http://localhost:9324"
AWS_REGION="us-east-1"

DYNAMODB_TABLE_PARAMETROS="dynamodb-smartpay-preliquidacion-parametros"
DYNAMODB_TABLE_PLAN_PAGOS="dynamodb-smartpay-registro-plan-pagos"
SQS_QUEUE_NAME="smartpay-liquidation-response"

export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
export AWS_DEFAULT_REGION=$AWS_REGION

echo -e "${YELLOW}=== DynamoDB ===${NC}"

aws --endpoint-url="$DYNAMODB_ENDPOINT" dynamodb create-table \
    --table-name "$DYNAMODB_TABLE_PARAMETROS" \
    --attribute-definitions AttributeName=execution_key,AttributeType=S \
    --key-schema AttributeName=execution_key,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST 2>/dev/null \
    && echo -e "${GREEN}Tabla $DYNAMODB_TABLE_PARAMETROS creada${NC}" \
    || echo -e "${GREEN}Tabla $DYNAMODB_TABLE_PARAMETROS ya existia${NC}"

aws --endpoint-url="$DYNAMODB_ENDPOINT" dynamodb create-table \
    --table-name "$DYNAMODB_TABLE_PLAN_PAGOS" \
    --attribute-definitions \
        AttributeName=id_participante,AttributeType=S \
        AttributeName=id_solicitud_pago,AttributeType=S \
    --key-schema \
        AttributeName=id_participante,KeyType=HASH \
        AttributeName=id_solicitud_pago,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST 2>/dev/null \
    && echo -e "${GREEN}Tabla $DYNAMODB_TABLE_PLAN_PAGOS creada${NC}" \
    || echo -e "${GREEN}Tabla $DYNAMODB_TABLE_PLAN_PAGOS ya existia${NC}"

echo ""
echo -e "${YELLOW}=== SQS (elasticmq) ===${NC}"

aws --endpoint-url="$SQS_ENDPOINT" sqs create-queue \
    --queue-name "$SQS_QUEUE_NAME" 2>/dev/null \
    && echo -e "${GREEN}Cola $SQS_QUEUE_NAME creada${NC}" \
    || echo -e "${GREEN}Cola $SQS_QUEUE_NAME ya existia${NC}"

echo ""
echo -e "${GREEN}Bootstrap completo.${NC}"
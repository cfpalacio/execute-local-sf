#!/bin/bash
# Sustituye los placeholders del ASL con ARNs/URLs de los servicios locales y
# crea (o actualiza) la state machine en Step Functions Local.
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

SFN_ENDPOINT="http://localhost:8083"
AWS_REGION="us-east-1"
ACCOUNT_ID="123456789012"
STATE_MACHINE_NAME="smartpay-flujo-liquidacion-local"
ASL_SOURCE="$PROJECT_ROOT/step-function-orchestrator/statemachine/liquidacion.asl.json"
ASL_RENDERED="$SCRIPT_DIR/../.rendered.asl.json"

export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
export AWS_DEFAULT_REGION=$AWS_REGION

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}jq es requerido. Instala con: brew install jq${NC}"
    exit 1
fi

echo -e "${YELLOW}Verificando Step Functions Local en $SFN_ENDPOINT...${NC}"
if ! curl -s -o /dev/null "$SFN_ENDPOINT"; then
    echo -e "${RED}Step Functions Local no responde. Levanta con: docker compose -f local/docker-compose.yml up -d${NC}"
    exit 1
fi

echo -e "${YELLOW}Renderizando placeholders del ASL...${NC}"

LAMBDA_ARN_PREFIX="arn:aws:lambda:$AWS_REGION:$ACCOUNT_ID:function"

sed \
    -e "s|\${LambdaCalculoIngresosArn}|$LAMBDA_ARN_PREFIX:smartpay-lambda-calculo-ingresos|g" \
    -e "s|\${LambdaCalculoBaseGravableArn}|$LAMBDA_ARN_PREFIX:smartpay-lambda-calculo-base-gravable|g" \
    -e "s|\${LambdaCalculoSeguridadSocialArn}|$LAMBDA_ARN_PREFIX:smartpay-lambda-calculo-seguridad-social|g" \
    -e "s|\${LambdaCalculoOtrasDeduccionesArn}|$LAMBDA_ARN_PREFIX:smartpay-lambda-calculo-otras-deducciones|g" \
    -e "s|\${LambdaCalculoCapacidadEndeudamientoArn}|$LAMBDA_ARN_PREFIX:smartpay-lambda-calculo-capacidad-endeudamiento|g" \
    -e "s|\${LambdaCalculoFechaPagoArn}|$LAMBDA_ARN_PREFIX:smartpay-lambda-calculo-fecha-pago|g" \
    -e "s|\${LambdaEscrituraDynamoArn}|$LAMBDA_ARN_PREFIX:smartpay-lambda-escritura-dynamo|g" \
    -e "s|\${LambdaLecturaChunkArn}|$LAMBDA_ARN_PREFIX:smartpay-lambda-lectura-chunk|g" \
    -e "s|\${StepfunctionLiquidationResponseQueueUrl}|http://host.docker.internal:9324/queue/smartpay-liquidation-response|g" \
    "$ASL_SOURCE" > "$ASL_RENDERED"

# Validar JSON
jq empty "$ASL_RENDERED" || { echo -e "${RED}ASL renderizado invalido${NC}"; exit 1; }

STATE_MACHINE_ARN="arn:aws:states:$AWS_REGION:$ACCOUNT_ID:stateMachine:$STATE_MACHINE_NAME"

EXISTS=$(aws --endpoint-url="$SFN_ENDPOINT" stepfunctions list-state-machines \
    --query "stateMachines[?name=='$STATE_MACHINE_NAME'].stateMachineArn" \
    --output text)

if [ -n "$EXISTS" ]; then
    echo -e "${YELLOW}Actualizando state machine existente...${NC}"
    aws --endpoint-url="$SFN_ENDPOINT" stepfunctions update-state-machine \
        --state-machine-arn "$EXISTS" \
        --definition file://"$ASL_RENDERED" \
        --role-arn "arn:aws:iam::$ACCOUNT_ID:role/DummyRole" >/dev/null
    echo -e "${GREEN}State machine actualizada: $EXISTS${NC}"
else
    echo -e "${YELLOW}Creando state machine...${NC}"
    aws --endpoint-url="$SFN_ENDPOINT" stepfunctions create-state-machine \
        --name "$STATE_MACHINE_NAME" \
        --definition file://"$ASL_RENDERED" \
        --role-arn "arn:aws:iam::$ACCOUNT_ID:role/DummyRole" >/dev/null
    echo -e "${GREEN}State machine creada: $STATE_MACHINE_ARN${NC}"
fi
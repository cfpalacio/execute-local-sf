#!/bin/bash
# Inicia una ejecucion de la state machine local con un input de test, espera
# a que termine y muestra el output.
#
# Uso: start-execution.sh [ruta-input.json]
# Default: step-function-orchestrator/test-events/liquidacion-input.json
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
STATE_MACHINE_ARN="arn:aws:states:$AWS_REGION:$ACCOUNT_ID:stateMachine:smartpay-flujo-liquidacion-local"

INPUT_FILE="${1:-$PROJECT_ROOT/step-function-orchestrator/test-events/liquidacion-input.json}"

export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy
export AWS_DEFAULT_REGION=$AWS_REGION

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Archivo de entrada no encontrado: $INPUT_FILE${NC}"
    exit 1
fi

EXECUTION_NAME="exec-$(date +%Y%m%d-%H%M%S)-$RANDOM"

echo -e "${YELLOW}Iniciando ejecucion con: $INPUT_FILE${NC}"

EXECUTION_ARN=$(aws --endpoint-url="$SFN_ENDPOINT" stepfunctions start-execution \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --name "$EXECUTION_NAME" \
    --input file://"$INPUT_FILE" \
    --query 'executionArn' \
    --output text)

echo -e "${GREEN}ARN: $EXECUTION_ARN${NC}"
echo ""

while true; do
    STATUS=$(aws --endpoint-url="$SFN_ENDPOINT" stepfunctions describe-execution \
        --execution-arn "$EXECUTION_ARN" \
        --query 'status' \
        --output text)
    if [ "$STATUS" != "RUNNING" ]; then
        break
    fi
    echo "Estado: $STATUS..."
    sleep 2
done

echo ""
echo -e "${YELLOW}=== Estado Final: $STATUS ===${NC}"

aws --endpoint-url="$SFN_ENDPOINT" stepfunctions describe-execution \
    --execution-arn "$EXECUTION_ARN" \
    --query '{status:status,error:error,cause:cause,output:output}' \
    --output json | python3 -m json.tool

echo ""
echo -e "${YELLOW}=== Historia de Ejecucion ===${NC}"
aws --endpoint-url="$SFN_ENDPOINT" stepfunctions get-execution-history \
    --execution-arn "$EXECUTION_ARN" \
    --query 'events[].{ts:timestamp,type:type,name:stateEnteredEventDetails.name||stateExitedEventDetails.name}' \
    --output table
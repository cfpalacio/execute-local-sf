#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

LOCALSTACK_ENDPOINT="http://localhost:4566"
AWS_REGION="us-east-1"
STATE_MACHINE_ARN="arn:aws:states:$AWS_REGION:000000000000:stateMachine:smartpay-flujo-liquidacion-local"

INPUT_FILE="${1:-$PROJECT_ROOT/test-events/liquidacion-input.json}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Archivo de entrada no encontrado: $INPUT_FILE"
    exit 1
fi

echo "Iniciando ejecucion con input: $INPUT_FILE"

EXECUTION_NAME="exec-$(date +%Y%m%d-%H%M%S)-$RANDOM"

EXECUTION_ARN=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" stepfunctions start-execution \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --name "$EXECUTION_NAME" \
    --input file://"$INPUT_FILE" \
    --query 'executionArn' \
    --output text \
    --region "$AWS_REGION")

echo "Ejecucion iniciada: $EXECUTION_ARN"
echo ""
echo "Esperando resultado..."

while true; do
    STATUS=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" stepfunctions describe-execution \
        --execution-arn "$EXECUTION_ARN" \
        --query 'status' \
        --output text \
        --region "$AWS_REGION")

    if [ "$STATUS" != "RUNNING" ]; then
        break
    fi

    echo "Estado: $STATUS..."
    sleep 2
done

echo ""
echo "=== Estado Final: $STATUS ==="
echo ""

OUTPUT=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" stepfunctions describe-execution \
    --execution-arn "$EXECUTION_ARN" \
    --query 'output' \
    --output text \
    --region "$AWS_REGION")

echo "Output:"
echo "$OUTPUT" | python3 -m json.tool 2>/dev/null || echo "$OUTPUT"

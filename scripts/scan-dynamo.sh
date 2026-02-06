#!/bin/bash

LOCALSTACK_ENDPOINT="http://localhost:4566"
AWS_REGION="us-east-1"
DYNAMODB_TABLE_CHUNKS="smartpay-chunks"
DYNAMODB_TABLE_RESULTS="smartpay-resultados"

PYTHON_HELPERS='
import sys
import json

def get_value(item, key, default="N/A"):
    if key not in item:
        return default
    val = item[key]
    if "S" in val:
        return val["S"]
    elif "N" in val:
        return val["N"]
    elif "BOOL" in val:
        return val["BOOL"]
    elif "M" in val:
        return val["M"]
    elif "L" in val:
        return val["L"]
    return default

def format_number(val):
    try:
        num = float(val)
        if num == int(num):
            return str(int(num))
        return f"{num:.2f}"
    except:
        return str(val)
'

echo "=============================================================="
echo "=== Tabla de Chunks: $DYNAMODB_TABLE_CHUNKS ==="
echo "=============================================================="
echo ""

RESULT_CHUNKS=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb scan \
    --table-name "$DYNAMODB_TABLE_CHUNKS" \
    --region "$AWS_REGION" 2>&1)

if [ $? -ne 0 ]; then
    echo "Error o tabla no existe: $RESULT_CHUNKS"
else
    COUNT=$(echo "$RESULT_CHUNKS" | python3 -c "import sys, json; print(json.load(sys.stdin)['Count'])")
    echo "Total items: $COUNT"
    echo ""

    if [ "$COUNT" -eq 0 ]; then
        echo "La tabla esta vacia."
    else
        echo "$RESULT_CHUNKS" | python3 -c "$PYTHON_HELPERS
data = json.load(sys.stdin)
items = sorted(data['Items'], key=lambda x: (get_value(x, 'PK'), get_value(x, 'SK')))

for item in items:
    print('=' * 60)
    pk = get_value(item, 'PK')
    sk = get_value(item, 'SK')
    print(f'PK: {pk}')
    print(f'SK: {sk}')

    if sk == 'METADATA':
        print(f'Tipo: METADATA DEL BATCH')
        print(f'  BatchId: {get_value(item, \"batchId\")}')
        print(f'  Estado: {get_value(item, \"estado\")}')
        print(f'  Modo: {get_value(item, \"modo\")}')
        print(f'  Total Registros: {get_value(item, \"totalRegistros\")}')
        print(f'  Tamano Chunk: {get_value(item, \"tamanoLote\")}')
        print(f'  Total Chunks: {get_value(item, \"totalChunks\")}')
        print(f'  Chunks Procesados: {get_value(item, \"chunksProcesados\")}')
        print(f'  Creado: {get_value(item, \"creadoEn\")}')

    elif sk.startswith('CHUNK#'):
        print(f'Tipo: CHUNK DE DATOS')
        print(f'  ChunkId: {get_value(item, \"chunkId\")}')
        print(f'  Estado: {get_value(item, \"estado\")}')
        print(f'  Registro Inicio: {get_value(item, \"registroInicio\")}')
        print(f'  Registro Fin: {get_value(item, \"registroFin\")}')
        print(f'  Participantes Procesados: {get_value(item, \"participantesProcesados\", \"0\")}')
        print(f'  Total Participantes: {get_value(item, \"totalParticipantes\", \"0\")}')
        participantes = get_value(item, 'participantes', [])
        if isinstance(participantes, list):
            print(f'  Participantes en chunk: {len(participantes)}')

    print()
"
    fi
fi

echo ""
echo "=============================================================="
echo "=== Tabla de Resultados: $DYNAMODB_TABLE_RESULTS ==="
echo "=============================================================="
echo ""

RESULT_RESULTS=$(aws --endpoint-url="$LOCALSTACK_ENDPOINT" dynamodb scan \
    --table-name "$DYNAMODB_TABLE_RESULTS" \
    --region "$AWS_REGION" 2>&1)

if [ $? -ne 0 ]; then
    echo "Error o tabla no existe: $RESULT_RESULTS"
else
    COUNT=$(echo "$RESULT_RESULTS" | python3 -c "import sys, json; print(json.load(sys.stdin)['Count'])")
    echo "Total items: $COUNT"
    echo ""

    if [ "$COUNT" -eq 0 ]; then
        echo "La tabla esta vacia."
    else
        echo "$RESULT_RESULTS" | python3 -c "$PYTHON_HELPERS
data = json.load(sys.stdin)
items = sorted(data['Items'], key=lambda x: (get_value(x, 'PK'), get_value(x, 'SK')))

for item in items:
    print('=' * 60)
    pk = get_value(item, 'PK')
    sk = get_value(item, 'SK')
    print(f'PK: {pk}')
    print(f'SK: {sk}')
    print(f'Tipo: RESULTADO PROCESADO')

    batch = get_value(item, 'batch')
    item_id = get_value(item, 'item')
    participante = get_value(item, 'idParticipante')
    status = get_value(item, 'status')
    created = get_value(item, 'createdAt')

    print(f'  Batch: {batch}')
    print(f'  Item: {item_id}')
    print(f'  Participante: {participante}')
    print(f'  Status: {status}')
    print(f'  Creado: {created}')

    ingresos_raw = get_value(item, 'ingresos', {})
    if isinstance(ingresos_raw, dict) and ingresos_raw:
        print('  Ingresos:')
        for k, v in ingresos_raw.items():
            if isinstance(v, dict):
                val = list(v.values())[0] if v else 'N/A'
            else:
                val = v
            print(f'    - {k}: {format_number(val)}')

    deducciones = get_value(item, 'deducciones', [])
    if isinstance(deducciones, list) and deducciones:
        print('  Deducciones Seguridad Social:')
        for ded in deducciones:
            d = ded.get('M', ded) if isinstance(ded, dict) else {}
            tipo = d.get('type', {}).get('S', d.get('type', 'N/A'))
            valor = d.get('localValue', {}).get('N', d.get('localValue', '0'))
            pct = d.get('percentage', {}).get('N', d.get('percentage', '0'))
            try:
                pct_display = float(pct) * 100
            except:
                pct_display = pct
            print(f'    - {tipo}: \${format_number(valor)} ({format_number(pct_display)}%)')

    pagos = get_value(item, 'pagosAdicionales', [])
    if isinstance(pagos, list) and pagos:
        print('  Otras Deducciones:')
        for pago in pagos:
            p = pago.get('M', pago) if isinstance(pago, dict) else {}
            tipo = p.get('type', {}).get('S', p.get('type', 'N/A'))
            valor = p.get('localValue', {}).get('N', p.get('localValue', '0'))
            print(f'    - {tipo}: \${format_number(valor)}')

    print()
"
    fi
fi

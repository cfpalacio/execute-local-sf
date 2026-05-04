# Setup local — Step Functions Local + SAM Local

Reemplazo de LocalStack para correr la state machine `liquidacion.asl.json` en el laptop sin tocar AWS.

## Arquitectura

```
                 Mac host
+------------------------------------------+
| sam local start-lambda  (puerto 3001)    |  <- corre las 9 Lambdas en Docker
+----^-------------------------------------+
     |  invoke (HTTP)
     |
+----+-----------------------+   +----------------+   +----------------+
| stepfunctions-local :8083  |   | dynamodb :8000 |   | elasticmq :9324|
|  (amazon/aws-stepfn-local) |   |  (AWS oficial) |   |  (compat. SQS) |
+----------------------------+   +----------------+   +----------------+
```

Step Functions Local ejecuta el ASL real, llama a SAM Local para los Task de
`lambda:invoke` y a ElasticMQ para los `sqs:sendMessage`.

## Pre-requisitos

- Docker / Docker Desktop
- AWS CLI v2
- AWS SAM CLI (`brew install aws-sam-cli`)
- `jq` (`brew install jq`)
- Python 3.12 (para que SAM construya las Lambdas)

## Primera vez

```bash
make local-up        # 1. levanta SF Local + DynamoDB + ElasticMQ
make bootstrap       # 2. crea tablas DynamoDB y cola SQS
make sam-lambda      # 3. levanta SAM en otra terminal (queda en foreground)
make deploy          # 4. renderiza el ASL y crea la state machine
make execute         # 5. lanza una ejecucion con test-events/liquidacion-input.json
```

`make execute INPUT=ruta/al/otro-input.json` para usar otro input.

## Inspector web (UI)

```bash
make inspector       # http://localhost:5050
```

Servidor Flask que se conecta a SF Local y DynamoDB Local. Permite:
- Lanzar ejecuciones desde el navegador (incluye preset `plan_pagos`).
- Ver lista de ejecuciones recientes con su estado.
- Ver detalle: input, output, error, historia de eventos.
- Ver y refrescar contenido de las tablas DynamoDB.

Requiere `flask` y `boto3` (los instala automaticamente).

## Ciclo iterativo

- Cambias codigo de una Lambda → SAM detecta el cambio (con `--warm-containers LAZY` se reconstruye en la siguiente invocacion).
- Cambias el ASL → `make deploy` para re-renderizar y re-crear la state machine.
- Para limpiar: `make clean` (borra volumenes y el ASL renderizado).

## Notas

- Los placeholders `${LambdaXxxArn}` del ASL se sustituyen en `local/scripts/deploy-state-machine.sh` por ARNs sinteticos `arn:aws:lambda:us-east-1:000000000000:function:smartpay-lambda-xxx`. SAM Local enruta por nombre de funcion extraido del ARN.
- `${StepfunctionLiquidationResponseQueueUrl}` se sustituye por la URL de ElasticMQ.
- Para mockear Lambdas sin correrlas: descomentar el volume y `SFN_MOCK_CONFIG` en `docker-compose.yml`, agregar `MockConfigFile.json`, y arrancar ejecuciones con `--state-machine-arn ...#TestCaseName`. Util para CI.
- El setup viejo de LocalStack queda accesible con los targets `make legacy-*` por si se necesita comparar.

## Troubleshooting

- **`AlreadyExists: image "public.ecr.aws/lambda/python:3.12-rapid-x86_64"` al levantar SAM**: bug conocido de SAM CLI con `--warm-containers EAGER` cuando varias funciones comparten imagen base (compiten por crearla). El Makefile usa `LAZY` para evitarlo. Si quedaron contenedores huerfanos: `docker ps -a | grep lambda` y `docker rm -f <id>`. Si el problema persiste con `LAZY`, eliminar la imagen y dejar que SAM la baje de nuevo: `docker rmi public.ecr.aws/lambda/python:3.12-rapid-x86_64`.
- **SAM no encuentra la funcion `smartpay-lambda-xxx`**: SAM Local enruta por `FunctionName`. Verificar que `local/template.yaml` tenga el `FunctionName` que el script `deploy-state-machine.sh` esta usando en los ARNs.
- **SF Local no responde a `curl localhost:8083`**: la imagen tarda ~5s en bootear; si no levanta revisar `make logs`.
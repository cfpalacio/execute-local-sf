.PHONY: help local-up local-down sam-lambda bootstrap deploy execute logs status clean all inspector
.PHONY: legacy-start legacy-stop legacy-deploy legacy-execute legacy-clean

DOCKER_COMPOSE = docker compose
LOCAL_COMPOSE = $(DOCKER_COMPOSE) -f local/docker-compose.yml

help:
	@echo "SmartPay Liquidacion - Step Functions Local (SF Local + SAM Local)"
	@echo ""
	@echo "Setup recomendado (Step Functions Local + SAM Local + DynamoDB Local + ElasticMQ):"
	@echo "  make local-up    - Levantar SF Local, DynamoDB Local y ElasticMQ"
	@echo "  make sam-lambda  - Levantar SAM Local con todas las Lambdas en :3001 (foreground)"
	@echo "  make bootstrap   - Crear tablas DynamoDB y cola SQS"
	@echo "  make deploy      - Renderizar ASL y crear/actualizar la state machine"
	@echo "  make execute     - Ejecutar la state machine con un input de test"
	@echo "  make logs        - Ver logs de los contenedores"
	@echo "  make status      - Ver estado de los servicios"
	@echo "  make inspector   - Levantar UI web en :5050 para ver dynamo + ejecuciones"
	@echo "  make local-down  - Detener servicios"
	@echo "  make clean       - Detener y borrar volumenes/render"
	@echo ""
	@echo "Setup legacy (LocalStack, no recomendado por bug de pickle):"
	@echo "  make legacy-start | legacy-deploy | legacy-execute | legacy-stop | legacy-clean"

local-up:
	@echo "Levantando Step Functions Local + DynamoDB Local + ElasticMQ..."
	$(LOCAL_COMPOSE) up -d
	@sleep 5
	@echo "Listos:"
	@echo "  Step Functions Local : http://localhost:8083"
	@echo "  DynamoDB Local       : http://localhost:8000"
	@echo "  ElasticMQ (SQS)      : http://localhost:9324"

local-down:
	$(LOCAL_COMPOSE) down

sam-lambda:
	@echo "Levantando SAM Local Lambda en :3001 (Ctrl+C para detener)..."
	@command -v sam >/dev/null 2>&1 || { echo "AWS SAM CLI no instalado. brew install aws-sam-cli"; exit 1; }
	cd local && sam local start-lambda --port 3001 --host 0.0.0.0 --warm-containers LAZY

bootstrap:
	@./local/scripts/bootstrap.sh

deploy:
	@./local/scripts/deploy-state-machine.sh

execute:
	@./local/scripts/start-execution.sh $(INPUT)

inspector:
	@command -v pip >/dev/null 2>&1 || { echo "pip no encontrado"; exit 1; }
	@pip install -q -r local/inspector/requirements.txt
	@python local/inspector/server.py

logs:
	$(LOCAL_COMPOSE) logs -f

status:
	@$(LOCAL_COMPOSE) ps

clean:
	$(LOCAL_COMPOSE) down -v
	@rm -f local/.rendered.asl.json

all: local-up bootstrap deploy execute

# --- Legacy (LocalStack) ---

legacy-start:
	$(DOCKER_COMPOSE) up -d
	@sleep 10
	@echo "LocalStack listo en http://localhost:4566"

legacy-stop:
	$(DOCKER_COMPOSE) down

legacy-deploy:
	@chmod +x step-function-orchestrator/scripts/*.sh
	@./step-function-orchestrator/scripts/deploy-local.sh

legacy-execute:
	@./step-function-orchestrator/scripts/start-execution.sh

legacy-clean:
	$(DOCKER_COMPOSE) down -v
	@rm -rf /tmp/localstack
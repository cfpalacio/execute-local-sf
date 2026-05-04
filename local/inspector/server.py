from __future__ import annotations

import json
import os
import uuid
from decimal import Decimal
from pathlib import Path

import boto3
from boto3.dynamodb.types import TypeSerializer
from flask import Flask, jsonify, request, send_from_directory

SFN_ENDPOINT = os.environ.get("SFN_ENDPOINT", "http://localhost:8083")
DYNAMODB_ENDPOINT = os.environ.get("DYNAMODB_ENDPOINT", "http://localhost:8000")
REGION = "us-east-1"
ACCOUNT = "123456789012"
STATE_MACHINE_NAME = os.environ.get("STATE_MACHINE_NAME", "smartpay-flujo-liquidacion-local")
STATE_MACHINE_ARN = f"arn:aws:states:{REGION}:{ACCOUNT}:stateMachine:{STATE_MACHINE_NAME}"

os.environ.setdefault("AWS_ACCESS_KEY_ID", "dummy")
os.environ.setdefault("AWS_SECRET_ACCESS_KEY", "dummy")
os.environ.setdefault("AWS_DEFAULT_REGION", REGION)

app = Flask(__name__, static_folder=str(Path(__file__).parent / "static"))

PARAMETROS_TABLE = os.environ.get(
    "PARAMETROS_TABLE", "dynamodb-smartpay-preliquidacion-parametros"
)

sfn = boto3.client("stepfunctions", endpoint_url=SFN_ENDPOINT, region_name=REGION)
ddb = boto3.client("dynamodb", endpoint_url=DYNAMODB_ENDPOINT, region_name=REGION)
ddb_resource = boto3.resource("dynamodb", endpoint_url=DYNAMODB_ENDPOINT, region_name=REGION)
type_serializer = TypeSerializer()


def _is_ddb_shaped(value):
    if not isinstance(value, dict) or len(value) != 1:
        return False
    return next(iter(value.keys())) in {"S", "N", "BOOL", "M", "L", "NULL", "B", "SS", "NS", "BS"}


def _floats_to_decimal(value):
    if isinstance(value, float):
        return Decimal(str(value))
    if isinstance(value, dict):
        return {k: _floats_to_decimal(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_floats_to_decimal(v) for v in value]
    return value


def _to_ddb_item(payload: dict) -> dict:
    if not payload:
        raise ValueError("empty payload")
    if all(_is_ddb_shaped(v) for v in payload.values()):
        return payload
    converted = _floats_to_decimal(payload)
    return {k: type_serializer.serialize(v) for k, v in converted.items()}


def _serialize(obj):
    if isinstance(obj, Decimal):
        f = float(obj)
        return int(f) if f.is_integer() else f
    if isinstance(obj, dict):
        return {k: _serialize(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_serialize(v) for v in obj]
    if isinstance(obj, bytes):
        return obj.decode("utf-8", errors="replace")
    return obj


@app.get("/")
def index():
    return send_from_directory(app.static_folder, "index.html")


@app.get("/api/tables")
def list_tables():
    return jsonify(ddb.list_tables()["TableNames"])


@app.get("/api/tables/<table>")
def scan_table(table):
    limit = int(request.args.get("limit", 50))
    items = ddb_resource.Table(table).scan(Limit=limit).get("Items", [])
    return jsonify(_serialize(items))


@app.get("/api/tables/<table>/<pk>")
def get_item(table, pk):
    pk_name = request.args.get("pk_name", "execution_key")
    res = ddb_resource.Table(table).get_item(Key={pk_name: pk})
    return jsonify(_serialize(res.get("Item")))


@app.get("/api/executions")
def list_executions():
    res = sfn.list_executions(stateMachineArn=STATE_MACHINE_ARN, maxResults=20)
    return jsonify(_serialize(res["executions"]))


@app.get("/api/executions/<path:arn>")
def describe_execution(arn):
    desc = sfn.describe_execution(executionArn=arn)
    history = sfn.get_execution_history(executionArn=arn, maxResults=200, reverseOrder=False)
    return jsonify({"description": _serialize(desc), "history": _serialize(history["events"])})


@app.post("/api/executions")
def start_execution():
    body = request.get_json(force=True)
    name = body.get("name") or f"exec-from-ui-{os.urandom(4).hex()}"
    payload = body["input"]
    payload_str = payload if isinstance(payload, str) else json.dumps(payload)
    res = sfn.start_execution(
        stateMachineArn=STATE_MACHINE_ARN,
        name=name,
        input=payload_str,
    )
    return jsonify(_serialize(res))


@app.get("/api/parametros/keys")
def list_parametros_keys():
    res = ddb.scan(
        TableName=PARAMETROS_TABLE,
        ProjectionExpression="execution_key",
    )
    keys = sorted({item["execution_key"]["S"] for item in res.get("Items", []) if "execution_key" in item})
    return jsonify(keys)


@app.post("/api/parametros")
def upload_parametros():
    body = request.get_json(force=True)
    payload = body.get("item")
    if not isinstance(payload, dict):
        return jsonify({"error": "missing 'item' object"}), 400

    auto_generate = bool(body.get("autoGenerateKey", False))

    try:
        ddb_item = _to_ddb_item(payload)
    except Exception as exc:
        return jsonify({"error": f"invalid item: {exc}"}), 400

    if auto_generate or "execution_key" not in ddb_item:
        new_key = str(uuid.uuid4())
        ddb_item["execution_key"] = {"S": new_key}
        if "idSolicitudPago" not in ddb_item:
            ddb_item["idSolicitudPago"] = {"S": new_key}

    execution_key = ddb_item["execution_key"].get("S")
    if not execution_key:
        return jsonify({"error": "execution_key must be a string (S)"}), 400

    ddb.put_item(TableName=PARAMETROS_TABLE, Item=ddb_item)
    return jsonify({"execution_key": execution_key, "table": PARAMETROS_TABLE})


@app.get("/api/state-machine")
def state_machine_info():
    try:
        res = sfn.describe_state_machine(stateMachineArn=STATE_MACHINE_ARN)
        return jsonify({"exists": True, "name": res["name"], "arn": res["stateMachineArn"]})
    except sfn.exceptions.StateMachineDoesNotExist:
        return jsonify({"exists": False, "arn": STATE_MACHINE_ARN})


if __name__ == "__main__":
    print(f"Inspector en http://localhost:5050")
    print(f"  SFN endpoint     : {SFN_ENDPOINT}")
    print(f"  DynamoDB endpoint: {DYNAMODB_ENDPOINT}")
    print(f"  State machine    : {STATE_MACHINE_ARN}")
    app.run(host="0.0.0.0", port=5050, debug=True)

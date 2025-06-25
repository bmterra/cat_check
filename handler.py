import json
import logging
import os

import boto3
from boto3.dynamodb.conditions import Key

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

dynamodb = boto3.resource("dynamodb")
TABLE    = dynamodb.Table(os.environ["TABLE_NAME"])


def lambda_handler(event, context):
    """
    GET /cat_status?cat_id=whiskers
    → { "cat_id": "whiskers", "status": "processing", "last_update": "2025-06-25T09:14:00Z" }
    """
    qs = event.get("queryStringParameters") or {}
    cat_id = qs.get("cat_id")

    if not cat_id:
        return _resp(400, {"error": "Missing required query parameter 'cat_id'."})

    try:
        result = TABLE.get_item(Key={"cat_id": cat_id})
    except Exception as e:
        log.exception("DynamoDB get_item failed")
        return _resp(500, {"error": "Internal error reading data"})

    item = result.get("Item")
    if not item:
        return _resp(404, {"error": f"No status found for cat_id '{cat_id}'."})

    return _resp(200, item)


# ---------------------------------------------------------------------------

def _resp(status: int, body: dict):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps(body),
    }

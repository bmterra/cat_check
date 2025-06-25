import json
import logging
import os
import uuid
import boto3
from botocore.exceptions import ClientError

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

s3       = boto3.client("s3")
BUCKET   = os.environ["BUCKET_NAME"]
EXPIRY   = int(os.getenv("URL_EXPIRY_SECONDS", "600"))          # 10 min default
ALLOWED  = {".jpg", ".png"}                                     # whitelist

def lambda_handler(event, context):
    """
    GET /s3_upload?filename=mycat.jpg
    → 400 if extension not jpg/png
    → 200 {upload_url, object_key, expires_in}
    """
    qs = event.get("queryStringParameters") or {}
    filename = (qs.get("filename") or "").split("/")[-1]        # trim any path

    # -------- Extension check ---------------------------------------------
    if "." not in filename:
        return _resp(400, {"error": "filename query param must include an extension"})

    ext = "." + filename.rsplit(".", 1)[1].lower()
    if ext not in ALLOWED:
        return _resp(
            400,
            {
                "error": "Only .jpg or .png uploads are allowed",
                "allowed_extensions": sorted(ALLOWED),
            },
        )

    # -------- Generate unique key -----------------------------------------
    object_key = f"{uuid.uuid4().hex}{ext}"

    # -------- Presigned URL -----------------------------------------------
    try:
        url = s3.generate_presigned_url(
            ClientMethod="put_object",
            Params={
                "Bucket": BUCKET,
                "Key": object_key,
                # Optional: force the client to tag the correct content-type
                # "ContentType": f"image/{'jpeg' if ext == '.jpg' else 'png'}"
            },
            ExpiresIn=EXPIRY,
            HttpMethod='PUT'
        )
    except ClientError:
        log.exception("Failed to generate presigned URL")
        return _resp(500, {"error": "Failed to generate upload URL"})

    return _resp(200, {"upload_url": url, "object_key": object_key, "expires_in": EXPIRY})


# ---------------------------------------------------------------------------

def _resp(status: int, body: dict):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json", "Access-Control-Allow-Origin": "*"},
        "body": json.dumps(body),
    }

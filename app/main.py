from fastapi import FastAPI
from pydantic import BaseModel
from datetime import datetime
from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import Response
import logging


app = FastAPI(title="Document Validation Service")

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s"
)
logger = logging.getLogger("document-service")


# Metrics
REQUEST_COUNT = Counter(
    "document_validation_requests_total",
    "Total number of document validation requests"
)

VALIDATION_FAILURES = Counter(
    "document_validation_failures_total",
    "Total number of failed document validations"
)

REQUEST_LATENCY = Histogram(
    "document_validation_request_latency_seconds",
    "Latency of document validation requests"
)

ALLOWED_DOCUMENT_TYPES = {"invoice", "delivery_note", "certificate"}


class DocumentRequest(BaseModel):
    document_id: str
    document_type: str
    created_at: str
    source_system: str


class ValidationResponse(BaseModel):
    document_id: str
    status: str
    reason: str | None = None


@app.post("/validate", response_model=ValidationResponse)
def validate_document(document: DocumentRequest):
    REQUEST_COUNT.inc()
    logger.info(f"validate_request document_id={document.document_id} type={document.document_type}")

    with REQUEST_LATENCY.time():
        try:
            if not document.document_id.strip():
                raise ValueError("document_id is empty")

            if document.document_type not in ALLOWED_DOCUMENT_TYPES:
                raise ValueError("invalid document_type")

            try:
                datetime.strptime(document.created_at, "%Y-%m-%d")
            except ValueError:
                raise ValueError("invalid created_at format (expected YYYY-MM-DD)")


            if not document.source_system.strip():
                raise ValueError("source_system is empty")
            
            logger.info(f"validate_result ACCEPTED document_id={document.document_id}")

            return ValidationResponse(
                document_id=document.document_id,
                status="ACCEPTED"
            )

        except ValueError as exc:
            VALIDATION_FAILURES.inc()

            logger.warning(f"validate_result REJECTED document_id={document.document_id} reason={str(exc)}")

            return ValidationResponse(
                document_id=document.document_id,
                status="REJECTED",
                reason=str(exc)
            )

@app.get("/metrics")
def metrics():
    return Response(
        content=generate_latest(),
        media_type="text/plain"
    )


@app.get("/health/live")
def health_live():
    return {"status": "alive"}


@app.get("/health/ready")
def health_ready():
    return {"status": "ready"}


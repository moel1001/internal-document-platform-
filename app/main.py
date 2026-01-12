from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from datetime import datetime
from prometheus_client import Counter, Histogram, generate_latest
from fastapi.responses import Response
import time

app = FastAPI(title="Document Validation Service")

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
    start_time = time.time()
    REQUEST_COUNT.inc()

    try:
        if not document.document_id.strip():
            raise ValueError("document_id is empty")

        if document.document_type not in ALLOWED_DOCUMENT_TYPES:
            raise ValueError("invalid document_type")

        try:
            datetime.strptime(document.created_at, "%Y-%m-%d")
        except ValueError:
            raise ValueError("invalid created_at format")

        if not document.source_system.strip():
            raise ValueError("source_system is empty")

        return ValidationResponse(
            document_id=document.document_id,
            status="ACCEPTED"
        )

    except ValueError as exc:
        VALIDATION_FAILURES.inc()
        return ValidationResponse(
            document_id=document.document_id,
            status="REJECTED",
            reason=str(exc)
        )

    finally:
        REQUEST_LATENCY.observe(time.time() - start_time)


@app.get("/metrics")
def metrics():
    return Response(
        content=generate_latest(),
        media_type="text/plain"
    )

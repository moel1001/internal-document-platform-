from fastapi import FastAPI
from fastapi.responses import Response, HTMLResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel
from datetime import datetime
from prometheus_client import Counter, Histogram, generate_latest
import logging
from pathlib import Path
import time

app = FastAPI(title="Document Validation Service")


BASE_DIR = Path(__file__).parent
app.mount("/static", StaticFiles(directory=BASE_DIR / "static"), name="static")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("document-service")

ALLOWED_DOCUMENT_TYPES = {"invoice", "delivery_note", "certificate"}

# Prometheus Metrics

REQUEST_COUNT = Counter(
    "document_validation_requests_total",
    "Total number of document validation requests",
    ["result", "document_type"],
)

VALIDATION_FAILURES = Counter(
    "document_validation_failures_total",
    "Total number of failed document validations",
    ["reason_code", "document_type"],
)

REQUEST_LATENCY = Histogram(
    "document_validation_request_latency_seconds",
    "Latency of document validation requests",
    ["result", "document_type"],
)

def metric_document_type(raw: str) -> str:
    """Prevent unbounded label cardinality. Unknown/invalid values collapse into 'invalid'."""
    v = (raw or "").strip()
    return v if v in ALLOWED_DOCUMENT_TYPES else "invalid"

def reason_code_for_rejection(document: "DocumentRequest", exc_msg: str) -> str:
    """
    Stable, low-cardinality reason codes.
    """
    if exc_msg == "document_id is empty":
        return "empty_document_id"
    if exc_msg == "invalid document_type":
        if not (document.document_type or "").strip():
            return "empty_document_type"
        return "invalid_document_type"
    if exc_msg == "invalid created_at format (expected YYYY-MM-DD)":
        if not (document.created_at or "").strip():
            return "empty_created_at"
        return "invalid_created_at"
    if exc_msg == "source_system is empty":
        return "empty_source_system"
    return "other"

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
    start = time.monotonic()

    doc_type_label = metric_document_type(document.document_type)
    result_label = "REJECTED"
    reason_msg: str | None = None
    reason_code: str | None = None

    logger.info(
        f"validate_request document_id={document.document_id} type={document.document_type}"
    )

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
        result_label = "ACCEPTED"

        return ValidationResponse(document_id=document.document_id, status="ACCEPTED")

    except ValueError as exc:
        reason_msg = str(exc)
        reason_code = reason_code_for_rejection(document, reason_msg)

        logger.warning(
            f"validate_result REJECTED document_id={document.document_id} reason={reason_msg}"
        )

        return ValidationResponse(
            document_id=document.document_id, status="REJECTED", reason=reason_msg
        )

    finally:
        duration = time.monotonic() - start

        REQUEST_COUNT.labels(result=result_label, document_type=doc_type_label).inc()
        REQUEST_LATENCY.labels(result=result_label, document_type=doc_type_label).observe(
            duration
        )

        if result_label == "REJECTED" and reason_code is not None:
            VALIDATION_FAILURES.labels(
                reason_code=reason_code, document_type=doc_type_label
            ).inc()

UI_HTML = Path(__file__).with_name("ui.html").read_text(encoding="utf-8")

@app.get("/", include_in_schema=False)
def root():
    return RedirectResponse(url="/ui")

@app.get("/ui", response_class=HTMLResponse, include_in_schema=False)
def ui():
    return UI_HTML

@app.get("/metrics")
def metrics():
    return Response(content=generate_latest(), media_type="text/plain")

@app.get("/health/live")
def health_live():
    return {"status": "alive"}

@app.get("/health/ready")
def health_ready():
    return {"status": "ready"}

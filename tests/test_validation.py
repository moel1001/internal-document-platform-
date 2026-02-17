from fastapi.testclient import TestClient
from app.main import app

client=TestClient(app)

def test_validate_success():
    response = client.post(
        "/validate",
        json={
            "document_id" : "123",
            "document_type" : "invoice",
            "created_at": "2024-01-01",
            "source_system" : "sap"
        }
    )

    assert response.status_code == 200
    assert response.json()["status"] == "ACCEPTED"

def test_invalid_document_type():
    response = client.post(
        "/validate",
        json={
            "document_id" : "123",
            "document_type" : "invalid",
            "created_at": "2024-01-01",
            "source_system" : "sap"
        }
    )

    assert response.status_code == 200
    assert response.json()["status"] == "REJECTED"

def test_invalid_date_format():
    response = client.post(
        "/validate",
        json={
            "document_id" : "123",
            "document_type" : "invoice",
            "created_at": "01-01-2024",
            "source_system" : "sap"
        }
    )

    assert response.status_code == 200
    assert response.json()["status"] == "REJECTED"

def test_empty_document_id():
    response = client.post(
        "/validate",
        json={
            "document_id" : "",
            "document_type" : "invoice",
            "created_at": "2024-01-01",
            "source_system" : "sap"
        }
    )
    
    assert response.status_code == 200
    assert response.json()["status"] == "REJECTED"

def test_empty_source_system():
    response = client.post(
        "/validate",
        json={
            "document_id" : "123",
            "document_type" : "invoice",
            "created_at": "2024-01-01",
            "source_system" : ""
        }
    )

    assert response.status_code == 200
    assert response.json()["status"] == "REJECTED"
    

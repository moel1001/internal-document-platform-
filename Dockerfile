FROM python:3.11-slim-bookworm

WORKDIR /app

#Refresh Debian packages so trivy does not flag fixed OS vulnerabilities
RUN apt-get update \
    && apt-get upgrade -y \
    && rm -rf /var/lib/apt/lists/*

#Install dependencies first for better layer caching
COPY app/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

#Copy application code
COPY app /app/app

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host=0.0.0.0", "--port=8000"]

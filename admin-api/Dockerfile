FROM python:3.11-slim

WORKDIR /app

# Run as root to allow chown operations
USER root

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application
COPY main.py .

# Create necessary directories
RUN mkdir -p /opt/est/data /opt/est/tenants /opt/est/archives

# Expose port
EXPOSE 8087

# Run application as root (needed for chown operations)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8087"]

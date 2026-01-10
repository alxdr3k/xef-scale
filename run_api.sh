#!/bin/bash
# Quick start script for FastAPI development server

set -e

echo "Starting Expense Tracker API..."
echo ""
echo "API Documentation will be available at:"
echo "  - Swagger UI: http://localhost:8000/docs"
echo "  - ReDoc: http://localhost:8000/redoc"
echo "  - Health Check: http://localhost:8000/health"
echo ""

# Activate virtual environment if it exists
if [ -d ".venv" ]; then
    source .venv/bin/activate
fi

# Run uvicorn with auto-reload
uvicorn backend.main:app --reload --host 0.0.0.0 --port 8000

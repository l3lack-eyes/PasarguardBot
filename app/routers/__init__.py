"""
Router initialization and FastAPI app setup.
"""

from fastapi import FastAPI

from .webhook import webhook_router

# Create FastAPI application
api_app = FastAPI(
    title="PasarguardBot API", version="1.0.0", docs_url="/docs", redoc_url="/redoc", openapi_url="/openapi.json"
)

api_app.include_router(webhook_router, prefix="/api", tags=["Webhook"])

__all__ = ["api_app"]

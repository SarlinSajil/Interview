"""
"""
"""
Test suite for the DevOps Demo API
"""
import pytest
import asyncio
import sys
import os
from pathlib import Path

# Add the src directory to the Python path
src_path = Path(__file__).parent.parent / "src"
sys.path.insert(0, str(src_path))

from httpx import AsyncClient
from fastapi.testclient import TestClient

try:
    from main import app  # type: ignore
except ImportError:
    # Fallback import method
    import importlib.util
    spec = importlib.util.spec_from_file_location("main", src_path / "main.py")
    if spec is not None and spec.loader is not None:
        main_module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(main_module)
        app = main_module.app
    else:
        raise ImportError("Could not import main module")

@pytest.fixture
async def client():
    import httpx
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as ac:
        yield ac

class TestAPI:
    
    async def test_root_endpoint(self, client: AsyncClient):
        """Test the root endpoint"""
        response = await client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert data["message"] == "DevOps Demo API"
        assert data["version"] == "1.0.0"
    
    async def test_health_endpoint(self, client: AsyncClient):
        """Test the health check endpoint"""
        response = await client.get("/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data
        assert "environment" in data
        assert "version" in data
    
    async def test_metrics_endpoint(self, client: AsyncClient):
        """Test the metrics endpoint"""
        response = await client.get("/metrics")
        assert response.status_code == 200
        content = response.text
        assert "api_counter_total" in content
        assert "api_health" in content
    
    async def test_counter_get_initial(self, client: AsyncClient):
        """Test getting counter initial value"""
        # This test might fail in environments without Redis
        # We'll make it resilient
        response = await client.get("/counter")
        # Should either succeed with counter data or fail with 503
        assert response.status_code in [200, 503]
        
        if response.status_code == 200:
            data = response.json()
            assert "counter" in data
            assert "timestamp" in data
    
    async def test_user_endpoints_structure(self, client: AsyncClient):
        """Test user endpoints structure (may fail without DB)"""
        # Test user creation endpoint structure
        user_data = {
            "name": "Test User",
            "email": "test@example.com"
        }
        
        response = await client.post("/users", json=user_data)
        # Should either succeed or fail with 503 (service unavailable)
        assert response.status_code in [200, 201, 400, 503]
        
        # Test user listing endpoint
        response = await client.get("/users")
        assert response.status_code in [200, 503]

class TestHealthChecks:
    
    async def test_readiness_check(self, client: AsyncClient):
        """Test readiness check endpoint"""
        response = await client.get("/ready")
        # This will likely fail without Redis/PostgreSQL, which is expected
        assert response.status_code in [200, 503]

if __name__ == "__main__":
    pytest.main([__file__, "-v"])
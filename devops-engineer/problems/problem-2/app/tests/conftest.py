"""
Pytest configuration for DevOps Demo API tests
"""
import sys
import os
import pytest

# Add the src directory to the Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"
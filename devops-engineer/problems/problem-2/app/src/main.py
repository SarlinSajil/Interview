"""
FastAPI Sample Application for DevOps CI/CD Pipeline Demo
"""
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
import logging
import time
from typing import Dict, Any, Optional, Union, cast
import redis
import psycopg2
from psycopg2.extras import RealDictCursor
import json

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="DevOps Demo API",
    description="Sample API for demonstrating GitOps CI/CD pipeline",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Environment variables
REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD", "redis_password")

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = int(os.getenv("POSTGRES_PORT", "5432"))
POSTGRES_DB = os.getenv("POSTGRES_DB", "interview_db")
POSTGRES_USER = os.getenv("POSTGRES_USER", "interview_user")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "interview_password")

# Pydantic models
class HealthResponse(BaseModel):
    status: str
    timestamp: float
    environment: str
    version: str

class CounterResponse(BaseModel):
    counter: int
    timestamp: float

class UserCreate(BaseModel):
    name: str
    email: str

class UserResponse(BaseModel):
    id: int
    name: str
    email: str
    created_at: str

# Global connections
redis_client = None
postgres_conn = None

def get_redis_client() -> Optional[redis.Redis]:
    """Get Redis client with connection handling"""
    global redis_client
    try:
        if redis_client is None:
            redis_client = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                password=REDIS_PASSWORD,
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5
            )
        redis_client.ping()
        return redis_client
    except Exception as e:
        logger.error(f"Redis connection failed: {e}")
        return None

def get_postgres_connection() -> Optional[psycopg2.extensions.connection]:
    """Get PostgreSQL connection with connection handling"""
    global postgres_conn
    try:
        if postgres_conn is None or postgres_conn.closed:
            postgres_conn = psycopg2.connect(
                host=POSTGRES_HOST,
                port=POSTGRES_PORT,
                database=POSTGRES_DB,
                user=POSTGRES_USER,
                password=POSTGRES_PASSWORD,
                cursor_factory=RealDictCursor
            )
        return postgres_conn
    except Exception as e:
        logger.error(f"PostgreSQL connection failed: {e}")
        return None

@app.on_event("startup")
async def startup_event():
    """Initialize database tables"""
    logger.info("Starting up application...")
    
    # Initialize PostgreSQL table
    conn = get_postgres_connection()
    if conn:
        try:
            with conn.cursor() as cursor:
                cursor.execute("""
                    CREATE TABLE IF NOT EXISTS users (
                        id SERIAL PRIMARY KEY,
                        name VARCHAR(100) NOT NULL,
                        email VARCHAR(100) UNIQUE NOT NULL,
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
                conn.commit()
                logger.info("Database table initialized successfully")
        except Exception as e:
            logger.error(f"Database initialization failed: {e}")

@app.get("/", response_model=Dict[str, str])
async def root():
    """Root endpoint"""
    return {
        "message": "DevOps Demo API",
        "version": "1.0.0",
        "docs": "/docs"
    }

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint for Kubernetes probes"""
    return HealthResponse(
        status="healthy",
        timestamp=time.time(),
        environment=os.getenv("ENVIRONMENT", "development"),
        version="1.0.0"
    )

@app.get("/ready")
async def readiness_check():
    """Readiness check for Kubernetes"""
    # Check Redis connectivity
    redis_ok = get_redis_client() is not None
    
    # Check PostgreSQL connectivity
    postgres_ok = get_postgres_connection() is not None
    
    if redis_ok and postgres_ok:
        return {"status": "ready", "redis": "ok", "postgres": "ok"}
    else:
        raise HTTPException(
            status_code=503,
            detail={
                "status": "not ready",
                "redis": "ok" if redis_ok else "error",
                "postgres": "ok" if postgres_ok else "error"
            }
        )

@app.get("/counter", response_model=CounterResponse)
async def get_counter():
    """Get current counter value from Redis"""
    redis_client = get_redis_client()
    if not redis_client:
        raise HTTPException(status_code=503, detail="Redis not available")
    
    try:
        counter_value = redis_client.get("api_counter")
        if counter_value is None:
            counter = 0
        else:
            # Redis returns string when decode_responses=True, bytes otherwise
            counter = int(str(counter_value))
        
        return CounterResponse(counter=counter, timestamp=time.time())
    except Exception as e:
        logger.error(f"Counter retrieval failed: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/counter", response_model=CounterResponse)
async def increment_counter():
    """Increment counter in Redis"""
    redis_client = get_redis_client()
    if not redis_client:
        raise HTTPException(status_code=503, detail="Redis not available")
    
    try:
        counter_result = redis_client.incr("api_counter")
        counter = int(str(counter_result))
        return CounterResponse(counter=counter, timestamp=time.time())
    except Exception as e:
        logger.error(f"Counter increment failed: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.post("/users", response_model=UserResponse)
async def create_user(user: UserCreate):
    """Create a new user in PostgreSQL"""
    conn = get_postgres_connection()
    if not conn:
        raise HTTPException(status_code=503, detail="Database not available")
    
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "INSERT INTO users (name, email) VALUES (%s, %s) RETURNING *",
                (user.name, user.email)
            )
            new_user = cursor.fetchone()
            conn.commit()
            
            if new_user is None:
                raise Exception("Failed to create user")
            
            # Cast the RealDictRow to proper types
            user_data = cast(Dict[str, Any], new_user)
            return UserResponse(
                id=int(user_data["id"]),
                name=str(user_data["name"]),
                email=str(user_data["email"]),
                created_at=user_data["created_at"].isoformat()
            )
    except psycopg2.IntegrityError:
        conn.rollback()
        raise HTTPException(status_code=400, detail="Email already exists")
    except Exception as e:
        conn.rollback()
        logger.error(f"User creation failed: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/users")
async def list_users():
    """List all users from PostgreSQL"""
    conn = get_postgres_connection()
    if not conn:
        raise HTTPException(status_code=503, detail="Database not available")
    
    try:
        with conn.cursor() as cursor:
            cursor.execute("SELECT * FROM users ORDER BY created_at DESC LIMIT 10")
            users = cursor.fetchall()
            
            return {
                "users": [
                    {
                        "id": int(cast(Dict[str, Any], user)["id"]),
                        "name": str(cast(Dict[str, Any], user)["name"]),
                        "email": str(cast(Dict[str, Any], user)["email"]),
                        "created_at": cast(Dict[str, Any], user)["created_at"].isoformat()
                    }
                    for user in users
                ]
            }
    except Exception as e:
        logger.error(f"User listing failed: {e}")
        raise HTTPException(status_code=500, detail="Internal server error")

@app.get("/metrics")
async def get_metrics():
    """Basic metrics endpoint for Prometheus scraping"""
    redis_client = get_redis_client()
    
    # Get counter value
    counter = 0
    if redis_client:
        try:
            counter_value = redis_client.get("api_counter")
            if counter_value is not None:
                counter = int(str(counter_value))
        except:
            pass
    
    # Simple metrics format
    metrics = f"""# HELP api_counter_total Total API counter value
# TYPE api_counter_total counter
api_counter_total {counter}

# HELP api_health Application health status
# TYPE api_health gauge
api_health 1
"""
    
    return metrics

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
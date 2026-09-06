from fastapi import FastAPI

from api.routes import health, jobs, models

app = FastAPI(title="Cadence API")

app.include_router(health.router, prefix="/api")
app.include_router(jobs.router, prefix="/api/jobs")
app.include_router(models.router, prefix="/api/models")

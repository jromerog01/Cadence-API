from fastapi import FastAPI

from api.routes import auth, health, jobs, models, uploads

app = FastAPI(title="Cadence API")

app.include_router(health.router, prefix="/api")
app.include_router(auth.router, prefix="/api/auth")
app.include_router(jobs.router, prefix="/api/jobs")
app.include_router(models.router, prefix="/api/models")
app.include_router(uploads.router, prefix="/api/uploads")

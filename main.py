from datetime import datetime
from typing import Optional, List
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field
from database import get_connection

app = FastAPI(title= "GPS Analytics API")

class GPSPoint(BaseModel):
    device_id: str = Field(min_length=1)
    recorded_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_m: Optional[float] = Field(default=None, ge=0)

class GPSBatch(BaseModel):
    points: List[GPSPoint] = Field(min_length=1, max_length=1000)

@app.get("/")
def home():
    return {"message": "GPS Analytics API is running"}

@app.post("/gps")
def create_gps_point(point: GPSPoint):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO gps_points
                        (device_id, recorded_at, latitude, longitude, accuracy_m)
                    VALUES (%s, %s, %s, %s, %s)
                    RETURNING id
                    """,
                    (
                        point.device_id,
                        point.recorded_at,
                        point.latitude,
                        point.longitude,
                        point.accuracy_m,
                    ),
                )
                new_id = cur.fetchone()[0]

            return {"message": "GPS point saved", "id": new_id}

    except Exception as exc:
        print(f"Database insert failed: {exc}")
        raise HTTPException(
            status_code=500,
            detail="Could not save GPS point",
        )

@app.post("/gps/batch")
def create_gps_batch(batch: GPSBatch):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.executemany(
                    """
                    INSERT INTO gps_points
                    (device_id, recorded_at, latitude, longitude, accuracy_m)
                    VALUES (%s, %s, %s, %s, %s)
                    """,
                    [
                        (
                            point.device_id,
                            point.recorded_at,
                            point.latitude,
                            point.longitude,
                            point.accuracy_m
                        )
                        for point in batch.points
                    ],
                )
            return {
                "message": "GPS batch saved",
                "count": len(batch.points),
            }
    except Exception as exc:
        print(f"Database batch insert failed: {exc}")
        raise HTTPException(
            status_code=500,
            detail="Could not save GPS batch",
        )

@app.get("/gps")
def get_gps_points(
        device_id: str = "iphone-test",
        limit: int = Query(default=100, ge=1, le=1000),
):
    try:
        with get_connection() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT id, device_id, recorded_at, latitude, longitude, accuracy_m, received_at
                    FROM gps_points
                    WHERE device_id = %s
                    ORDER BY recorded_at DESC
                    limit %s
                    """,
                    (device_id, limit),
                )

                rows = cur.fetchall()
        return [
            {
                "id": row[0],
                "device_id": row[1],
                "recorded_at": row[2],
                "latitude": row[3],
                "longitude": row[4],
                "accuracy_m": row[5],
                "received_at": row[6],
            }
            for row in rows
        ]

    except Exception as exc:
        print(f"Database query failed: {exc}")
        raise HTTPException(
            status_code = 500,
            detail="Could not retrieve GPS history",
        )
use axum::extract::Json;
use crate::models::{ChartRequest, ChartResponse};

pub async fn calculate_chart(Json(payload): Json<ChartRequest>) -> Json<ChartResponse> {
    // TODO: Step 2-2 에페메리스 로직 연동
    // 1. Convert local time to UTC using tz_offset
    // 2. Compute Julian Day (calendar_to_jd)
    // 3. Evaluate AnalyticalProvider for planet coordinates
    // 4. Build planet data and call compute_chart
    // 5. Map result to response

    Json(ChartResponse {
        status: "success".to_string(),
        message: format!("Received valid request for {}-{}-{}", payload.year, payload.month, payload.day),
    })
}

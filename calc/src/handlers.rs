use axum::extract::Json;
use axum::http::StatusCode;
use crate::models::{ChartRequest, ChartResponse};
use chrono::{FixedOffset, NaiveDate, TimeZone, Utc, Datelike, Timelike};
use vedaksha::prelude::*;

pub async fn calculate_chart(Json(payload): Json<ChartRequest>) -> Result<Json<ChartResponse>, StatusCode> {
    // 1. 년/월/일/시/분 및 시간대 오프셋 정보를 바탕으로 UTC 변환 후 율리우스일(JD) 계산
    let local_datetime = NaiveDate::from_ymd_opt(payload.year, payload.month, payload.day)
        .and_then(|d| d.and_hms_opt(payload.hour, payload.minute, 0))
        .ok_or(StatusCode::BAD_REQUEST)?;

    // tz_offset (시간 단위)을 초 단위 오프셋으로 변환하여 FixedOffset 생성
    let offset_seconds = (payload.tz_offset * 3600.0) as i32;
    let offset = FixedOffset::east_opt(offset_seconds)
        .ok_or(StatusCode::BAD_REQUEST)?;

    let dt_with_tz = offset.from_local_datetime(&local_datetime)
        .single()
        .ok_or(StatusCode::BAD_REQUEST)?;

    let utc = dt_with_tz.with_timezone(&Utc);

    // UT 기준일(day)의 소수점 계산
    let utc_year = utc.year();
    let utc_month = utc.month();
    let utc_day = utc.day() as f64 
        + (utc.hour() as f64 / 24.0) 
        + (utc.minute() as f64 / 1440.0) 
        + (utc.second() as f64 / 86400.0);

    let jd = calendar_to_jd(utc_year, utc_month, utc_day);

    // 2. Analytical Ephemeris Provider 설정 및 행성 위치 계산
    let provider = AnalyticalProvider::new();
    let bodies = [
        Body::Sun,
        Body::Moon,
        Body::Mercury,
        Body::Venus,
        Body::Mars,
        Body::Jupiter,
        Body::Saturn,
        Body::Uranus,
        Body::Neptune,
        Body::MeanNode, // Rahu로 매핑
    ];

    let mut planet_data = Vec::new();
    for body in bodies {
        let pos = apparent_position(&provider, body, jd)
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        
        // Body::MeanNode는 "Rahu"로 이름 정의
        let name = match body {
            Body::MeanNode => "Rahu".to_string(),
            _ => body.name().to_string(),
        };

        planet_data.push((
            name,
            pos.ecliptic.longitude.to_degrees(),
            pos.ecliptic.latitude.to_degrees(),
            pos.ecliptic.distance,
            pos.longitude_speed,
        ));
    }

    // Ketu 계산 (Rahu의 반대편 180도)
    if let Some(rahu_idx) = planet_data.iter().position(|p| p.0 == "Rahu") {
        let rahu = &planet_data[rahu_idx];
        let ketu_lon = (rahu.1 + 180.0) % 360.0;
        planet_data.push((
            "Ketu".to_string(),
            ketu_lon,
            -rahu.2, // 대략적으로 반대 위도
            rahu.3,  // 동일 거리
            rahu.4,  // 동일 속도
        ));
    }

    // 3. 하우스 계산을 위한 RAMC 및 obliquity 계산
    let jd_tt = vedaksha::ephem::delta_t::ut1_to_tt(jd);
    let (dpsi, deps) = vedaksha::ephem::nutation::nutation(jd_tt);
    let eps_true_rad = vedaksha::ephem::obliquity::true_obliquity(jd_tt, deps);
    let gast_rad = vedaksha::ephem::sidereal_time::gast(jd, dpsi, eps_true_rad);
    let gast_deg = gast_rad.to_degrees();

    // RAMC = LST + 경도
    let ramc = vedaksha::math::angle::normalize_degrees(gast_deg + payload.longitude);
    let eps_deg = eps_true_rad.to_degrees();

    // 4. 차트 계산 (Lahiri 아야남샤 적용, 전체 사인 하우스 시스템 적용)
    let mut config = ChartConfig::default();
    config.ayanamsha = Some(Ayanamsha::Lahiri);
    config.house_system = HouseSystem::WholeSign;

    let computed_chart = compute_chart(&planet_data, ramc, payload.latitude, eps_deg, jd, &config);

    // 5. 달의 황경을 바탕으로 Vimshottari Dasha 계산 (Maha & Antar 2단계 깊이)
    let moon_sidereal_lon = computed_chart.planets.iter()
        .find(|p| p.name == "Moon")
        .map(|p| p.longitude)
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;

    let dasha = dasha::vimshottari::compute_vimshottari(moon_sidereal_lon, jd, 2);

    Ok(Json(ChartResponse {
        status: "success".to_string(),
        message: "Calculated chart successfully".to_string(),
        chart: computed_chart,
        dasha,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_calculate_chart_success() {
        let payload = ChartRequest {
            year: 1995,
            month: 1,
            day: 1,
            hour: 12,
            minute: 0,
            latitude: 37.5665,
            longitude: 126.9780,
            tz_offset: 9.0,
        };

        let result = calculate_chart(Json(payload)).await;
        assert!(result.is_ok());
        
        let response = result.unwrap().0;
        assert_eq!(response.status, "success");
        assert_eq!(response.message, "Calculated chart successfully");
        
        let planets = response.chart.planets;
        assert!(planets.iter().any(|p| p.name == "Sun"));
        assert!(planets.iter().any(|p| p.name == "Moon"));
        assert!(planets.iter().any(|p| p.name == "Rahu"));
        assert!(planets.iter().any(|p| p.name == "Ketu"));
        
        // Vimshottari dasha 검증
        assert_eq!(response.dasha.moon_nakshatra.name(), "Moola");
    }
}


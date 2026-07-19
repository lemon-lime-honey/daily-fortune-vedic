use axum::extract::Json;
use axum::http::StatusCode;
use crate::models::{ChartRequest, ChartResponse};
use chrono::{FixedOffset, NaiveDate, TimeZone, Utc, Datelike, Timelike};
use vedaksha::prelude::*;
use std::env;

fn compute_jd(year: i32, month: u32, day: u32, hour: u32, minute: u32, tz_offset: f64) -> Result<f64, StatusCode> {
    let local_datetime = NaiveDate::from_ymd_opt(year, month, day)
        .and_then(|d| d.and_hms_opt(hour, minute, 0))
        .ok_or(StatusCode::BAD_REQUEST)?;

    let offset_seconds = (tz_offset * 3600.0) as i32;
    let offset = FixedOffset::east_opt(offset_seconds)
        .ok_or(StatusCode::BAD_REQUEST)?;

    let dt_with_tz = offset.from_local_datetime(&local_datetime)
        .single()
        .ok_or(StatusCode::BAD_REQUEST)?;

    let utc = dt_with_tz.with_timezone(&Utc);

    let utc_year = utc.year();
    let utc_month = utc.month();
    let utc_day = utc.day() as f64 
        + (utc.hour() as f64 / 24.0) 
        + (utc.minute() as f64 / 1440.0) 
        + (utc.second() as f64 / 86400.0);

    Ok(calendar_to_jd(utc_year, utc_month, utc_day))
}

fn calculate_planets_and_houses(jd: f64, latitude: f64, longitude: f64) -> Result<ComputedChart, StatusCode> {
    let provider = AnalyticalProvider::new();
    let bodies = [
        Body::Sun, Body::Moon, Body::Mercury, Body::Venus, 
        Body::Mars, Body::Jupiter, Body::Saturn, Body::Uranus, 
        Body::Neptune, Body::MeanNode,
    ];

    let mut planet_data = Vec::new();
    for body in bodies {
        let pos = apparent_position(&provider, body, jd)
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        
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

    let jd_tt = vedaksha::ephem::delta_t::ut1_to_tt(jd);
    let (dpsi, deps) = vedaksha::ephem::nutation::nutation(jd_tt);
    let eps_true_rad = vedaksha::ephem::obliquity::true_obliquity(jd_tt, deps);
    let gast_rad = vedaksha::ephem::sidereal_time::gast(jd, dpsi, eps_true_rad);
    let gast_deg = gast_rad.to_degrees();

    let ramc = vedaksha::math::angle::normalize_degrees(gast_deg + longitude);
    let eps_deg = eps_true_rad.to_degrees();

    let mut config = ChartConfig::default();
    config.ayanamsha = Some(Ayanamsha::Lahiri);
    config.house_system = HouseSystem::WholeSign;

    Ok(compute_chart(&planet_data, ramc, latitude, eps_deg, jd, &config))
}

pub async fn calculate_chart(Json(payload): Json<ChartRequest>) -> Result<Json<ChartResponse>, StatusCode> {
    // 1. Natal JD and Chart
    let natal_jd = compute_jd(payload.year, payload.month, payload.day, payload.hour, payload.minute, payload.tz_offset)?;
    let natal_chart = calculate_planets_and_houses(natal_jd, payload.latitude, payload.longitude)?;

    // 2. Dasha
    let moon_sidereal_lon = natal_chart.planets.iter()
        .find(|p| p.name == "Moon")
        .map(|p| p.longitude)
        .ok_or(StatusCode::INTERNAL_SERVER_ERROR)?;
    let dasha = dasha::vimshottari::compute_vimshottari(moon_sidereal_lon, natal_jd, 2);

    // 3. Transit Chart Fallbacks
    let target_hour = payload.target_hour
        .or_else(|| env::var("TARGET_HOUR").ok().and_then(|v| v.parse::<u32>().ok()))
        .unwrap_or(12);
    let target_minute = payload.target_minute
        .or_else(|| env::var("TARGET_MINUTE").ok().and_then(|v| v.parse::<u32>().ok()))
        .unwrap_or(0);
    
    let target_tz_offset = payload.target_tz_offset
        .or_else(|| env::var("TARGET_TZ_OFFSET").ok().and_then(|v| v.parse::<f64>().ok()))
        .unwrap_or(payload.tz_offset);

    let transit_jd = compute_jd(
        payload.target_year, 
        payload.target_month, 
        payload.target_day, 
        target_hour, 
        target_minute, 
        target_tz_offset
    )?;

    let transit_lat = env::var("TARGET_LATITUDE")
        .ok()
        .and_then(|v| v.parse::<f64>().ok())
        .unwrap_or(payload.latitude);
        
    let transit_lon = env::var("TARGET_LONGITUDE")
        .ok()
        .and_then(|v| v.parse::<f64>().ok())
        .unwrap_or(payload.longitude);

    let transit_chart = calculate_planets_and_houses(transit_jd, transit_lat, transit_lon)?;

    // Find active dasha at transit_jd
    let active_dasha = dasha.maha_dashas.iter()
        .find(|md| transit_jd >= md.start_jd && transit_jd <= md.end_jd);

    let current_dasha = if let Some(md) = active_dasha {
        let active_antar = md.sub_periods.iter()
            .find(|sd| transit_jd >= sd.start_jd && transit_jd <= sd.end_jd);
        match active_antar {
            Some(sd) => format!("{:?} - {:?}", md.lord, sd.lord),
            None => format!("{:?}", md.lord),
        }
    } else {
        "Unknown".to_string()
    };

    // Find transit Moon house
    let transit_moon_house = transit_chart.planets.iter()
        .find(|p| p.name == "Moon")
        .map(|p| format!("Moon in {} House", p.house))
        .unwrap_or_else(|| "Unknown".to_string());

    Ok(Json(ChartResponse {
        status: "success".to_string(),
        message: "Calculated chart successfully".to_string(),
        natal_chart,
        transit_chart,
        dasha,
        current_dasha,
        transit_moon_house,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_calculate_chart_success() {
        // Remove unsafe set_var, let it fallback to natal coordinates and tz_offset
        // which perfectly tests the fallback logic.

        let payload = ChartRequest {
            year: 1995,
            month: 1,
            day: 1,
            hour: 12,
            minute: 0,
            latitude: 37.5665,
            longitude: 126.9780,
            tz_offset: 9.0,
            target_year: 2026,
            target_month: 7,
            target_day: 20,
            target_hour: None,
            target_minute: None,
            target_tz_offset: None,
        };

        let result = calculate_chart(Json(payload)).await;
        assert!(result.is_ok());
        
        let response = result.unwrap().0;
        assert_eq!(response.status, "success");
        assert_eq!(response.message, "Calculated chart successfully");
        assert!(!response.current_dasha.is_empty());
        assert!(!response.transit_moon_house.is_empty());
        
        let planets = response.natal_chart.planets;
        assert!(planets.iter().any(|p| p.name == "Sun"));
        assert!(planets.iter().any(|p| p.name == "Moon"));
        assert!(planets.iter().any(|p| p.name == "Rahu"));
        assert!(planets.iter().any(|p| p.name == "Ketu"));
        
        let t_planets = response.transit_chart.planets;
        assert!(t_planets.iter().any(|p| p.name == "Sun"));
        assert!(t_planets.iter().any(|p| p.name == "Moon"));
        
        // Vimshottari dasha 검증
        assert_eq!(response.dasha.moon_nakshatra.name(), "Moola");
    }
}

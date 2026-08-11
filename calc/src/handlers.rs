use axum::extract::Json;
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde_json::json;

#[derive(Debug)]
pub enum AppError {
    BadRequest(String),
    InternalError(String),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, error_message) = match self {
            AppError::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            AppError::InternalError(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg),
        };
        let body = Json(json!({ "error": error_message }));
        (status, body).into_response()
    }
}

use crate::models::{ChartRequest, ChartResponse, RelativeTransitPlanet, RelativeTransitChart, DailyMetrics, ActivatedTrigger};
use chrono::{FixedOffset, NaiveDate, TimeZone, Utc, Datelike, Timelike};
use vedaksha::prelude::*;
use vedaksha::astro::sidereal::Ayanamsha;
use vedaksha::vedic::ashtakavarga::{bhinna_ashtakavarga, sarvashtakavarga, BhinnaAshtakavargaInput};
use vedaksha::vedic::muhurta::compute_tithi;
use vedaksha::vedic::panchanga::{compute_panchanga_yoga, compute_karana};
use vedaksha::vedic::nakshatra::Nakshatra;
use std::env;

fn calculate_relative_house(longitude: f64, lagna_sign: i32) -> i32 {
    let transit_sign = (longitude as i32) / 30 + 1;
    (transit_sign + 12 - lagna_sign) % 12 + 1
}

fn compute_jd(year: i32, month: u32, day: u32, hour: u32, minute: u32, tz_offset: f64) -> Result<f64, AppError> {
    let local_datetime = NaiveDate::from_ymd_opt(year, month, day)
        .and_then(|d| d.and_hms_opt(hour, minute, 0))
        .ok_or_else(|| AppError::BadRequest("Invalid date/time/timezone".to_string()))?;

    let offset_seconds = (tz_offset * 3600.0) as i32;
    let offset = FixedOffset::east_opt(offset_seconds)
        .ok_or_else(|| AppError::BadRequest("Invalid date/time/timezone".to_string()))?;

    let dt_with_tz = offset.from_local_datetime(&local_datetime)
        .single()
        .ok_or_else(|| AppError::BadRequest("Invalid date/time/timezone".to_string()))?;

    let utc = dt_with_tz.with_timezone(&Utc);

    let utc_year = utc.year();
    let utc_month = utc.month();
    let utc_day = utc.day() as f64 
        + (utc.hour() as f64 / 24.0) 
        + (utc.minute() as f64 / 1440.0) 
        + (utc.second() as f64 / 86400.0);

    Ok(calendar_to_jd(utc_year, utc_month, utc_day))
}

fn calculate_planets_and_houses(jd: f64, latitude: f64, longitude: f64) -> Result<ComputedChart, AppError> {
    let provider = AnalyticalProvider::new();
    let bodies = [
        Body::Sun, Body::Moon, Body::Mercury, Body::Venus, 
        Body::Mars, Body::Jupiter, Body::Saturn,
    ];

    let mut planet_data = Vec::new();
    for body in bodies {
        let pos = apparent_position(&provider, body, jd)
            .map_err(|e| AppError::InternalError(format!("Failed to compute position: {:?}", e)))?;
        
        planet_data.push((
            body.name().to_string(),
            pos.ecliptic.longitude.to_degrees(),
            pos.ecliptic.latitude.to_degrees(),
            pos.ecliptic.distance,
            pos.longitude_speed,
        ));
    }

    // Calculate Rahu and Ketu bypassing the library's buggy geocentric correction
    let rahu_lon = vedaksha::ephem::nodes::mean_node(jd);
    let ketu_lon = (rahu_lon + 180.0) % 360.0;

    planet_data.push((
        "Rahu".to_string(),
        rahu_lon,
        0.0,
        1.0,
        -0.053, // mean speed (retrograde)
    ));

    planet_data.push((
        "Ketu".to_string(),
        ketu_lon,
        0.0,
        1.0,
        -0.053,
    ));

    let jd_tt = vedaksha::ephem::delta_t::ut1_to_tt(jd);
    let (dpsi, deps) = vedaksha::ephem::nutation::nutation(jd_tt);
    let eps_true_rad = vedaksha::ephem::obliquity::true_obliquity(jd_tt, deps);
    let gast_rad = vedaksha::ephem::sidereal_time::gast(jd, dpsi, eps_true_rad);
    let gast_deg = gast_rad.to_degrees();

    let ramc = vedaksha::math::angle::normalize_degrees(gast_deg + longitude);
    let eps_deg = eps_true_rad.to_degrees();

    let mut config = ChartConfig::default();
    config.ayanamsha = None; // Fix: Use Tropical mode to align planet and house calculations
    config.house_system = HouseSystem::WholeSign;

    Ok(compute_chart(&planet_data, ramc, latitude, eps_deg, jd, &config))
}

pub async fn calculate_chart(Json(payload): Json<ChartRequest>) -> Result<Json<ChartResponse>, AppError> {
    // 1. Natal JD and Chart (Tropical)
    let natal_jd = compute_jd(payload.year, payload.month, payload.day, payload.hour, payload.minute, payload.tz_offset)?;
    let mut natal_chart = calculate_planets_and_houses(natal_jd, payload.latitude, payload.longitude)?;

    // Calculate Ayanamsha for Natal JD
    let natal_ayanamsha = vedaksha::astro::sidereal::ayanamsha_value(Ayanamsha::Lahiri, natal_jd);

    // Calculate Sidereal Ascendant and Lagna Sign
    let sidereal_asc = (natal_chart.houses.asc - natal_ayanamsha + 360.0) % 360.0;
    let lagna_sign = (sidereal_asc as i32) / 30 + 1;

    // Convert Natal planets longitudes to Sidereal manually
    let signs = [
        "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
        "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"
    ];

    for p in &mut natal_chart.planets {
        p.longitude = (p.longitude - natal_ayanamsha + 360.0) % 360.0;
        let sign_idx = ((p.longitude as i32) / 30) as usize % 12;
        p.sign_index = sign_idx as u8;
        p.sign = signs[sign_idx].to_string();
        p.house = (((p.longitude as i32) / 30 + 1 + 12 - lagna_sign) % 12 + 1) as u8;
    }

    // Update natal houses field for API compatibility (convert all house cusps to sidereal)
    natal_chart.houses.asc = sidereal_asc;
    for cusp in &mut natal_chart.houses.cusps {
        *cusp = (*cusp - natal_ayanamsha + 360.0) % 360.0;
    }

    // 2. Dasha (Calculate based on Sidereal Moon Longitude)
    let moon_sidereal_lon = natal_chart.planets.iter()
        .find(|p| p.name == "Moon")
        .map(|p| p.longitude)
        .ok_or_else(|| AppError::InternalError("Planet missing in chart".to_string()))?;
    let dasha = dasha::vimshottari::compute_vimshottari(moon_sidereal_lon, natal_jd, 2);

    // 3. Transit Chart Fallbacks
    let target_hour = match payload.target_hour {
        Some(h) => h,
        None => env::var("TARGET_HOUR").unwrap_or_else(|_| "12".to_string())
            .parse::<u32>().map_err(|_| AppError::BadRequest("Invalid TARGET_HOUR".to_string()))?
    };
    let target_minute = match payload.target_minute {
        Some(m) => m,
        None => env::var("TARGET_MINUTE").unwrap_or_else(|_| "0".to_string())
            .parse::<u32>().map_err(|_| AppError::BadRequest("Invalid TARGET_MINUTE".to_string()))?
    };
    
    let target_tz_offset = match payload.target_tz_offset {
        Some(tz) => tz,
        None => env::var("TARGET_TZ_OFFSET").ok()
            .map(|v| v.parse::<f64>().map_err(|_| AppError::BadRequest("Invalid TARGET_TZ_OFFSET".to_string())))
            .transpose()?.unwrap_or(payload.tz_offset)
    };

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
    let transit_ayanamsha = vedaksha::astro::sidereal::ayanamsha_value(Ayanamsha::Lahiri, transit_jd);

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

    let signs = [
        "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
        "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"
    ];

    // Compute relative Gochar planets manually based on Sidereal longitudes
    let relative_planets = transit_chart.planets.iter().map(|p| {
        let sidereal_lon = (p.longitude - transit_ayanamsha + 360.0) % 360.0;
        let relative_house = calculate_relative_house(sidereal_lon, lagna_sign);
        let transit_sign_idx = ((sidereal_lon as i32) / 30) as usize;
        let sign_name = signs[transit_sign_idx % 12].to_string();

        RelativeTransitPlanet {
            name: p.name.clone(),
            longitude: sidereal_lon,
            latitude: p.latitude,
            distance: p.distance,
            speed: p.speed,
            sign: sign_name,
            house: relative_house,
            retrograde: p.retrograde,
        }
    }).collect::<Vec<_>>();

    let relative_transit_chart = RelativeTransitChart {
        planets: relative_planets,
        lagna_sign,
    };

    let transit_moon_house = relative_transit_chart.planets.iter()
        .find(|p| p.name == "Moon")
        .map(|p| format!("{}", p.house))
        .unwrap_or_else(|| "Unknown".to_string());

    // 4. Calculate Panchanga
    let transit_sun = relative_transit_chart.planets.iter().find(|p| p.name == "Sun")
        .ok_or_else(|| AppError::InternalError("Planet missing in chart".to_string()))?;
    let transit_moon = relative_transit_chart.planets.iter().find(|p| p.name == "Moon")
        .ok_or_else(|| AppError::InternalError("Planet missing in chart".to_string()))?;

    let tithi_data = compute_tithi(transit_moon.longitude, transit_sun.longitude);
    let tithi = format!("{} ({})", tithi_data.name, tithi_data.number);

    let nakshatra_data = Nakshatra::from_longitude(transit_moon.longitude);
    let nakshatra = nakshatra_data.name().to_string();

    let yoga_data = compute_panchanga_yoga(transit_sun.longitude, transit_moon.longitude);
    let yoga = yoga_data.name.to_string();

    let karana_data = compute_karana(transit_moon.longitude, transit_sun.longitude);
    let karana = karana_data.name.to_string();

    let target_date = NaiveDate::from_ymd_opt(payload.target_year, payload.target_month as u32, payload.target_day as u32)
        .ok_or_else(|| AppError::BadRequest("Invalid date/time/timezone".to_string()))?;
    let weekday_enum = target_date.weekday();
    let weekday = weekday_enum.to_string();
    let weekday_ruler = match weekday_enum {
        chrono::Weekday::Mon => "Moon",
        chrono::Weekday::Tue => "Mars",
        chrono::Weekday::Wed => "Mercury",
        chrono::Weekday::Thu => "Jupiter",
        chrono::Weekday::Fri => "Venus",
        chrono::Weekday::Sat => "Saturn",
        chrono::Weekday::Sun => "Sun",
    }.to_string();

    // 5. Calculate Tara Bala
    let birth_moon = natal_chart.planets.iter().find(|p| p.name == "Moon")
        .ok_or_else(|| AppError::InternalError("Planet missing in chart".to_string()))?;
    let birth_nak = Nakshatra::from_longitude(birth_moon.longitude);
    let birth_nak_idx = birth_nak.index();
    let transit_nak_idx = nakshatra_data.index();

    let tara_bala_step = (transit_nak_idx as i16 - birth_nak_idx as i16 + 27) % 9 + 1;
    let (tara_bala_category, tara_bala_description) = match tara_bala_step {
        1 => ("Janma", "일반적인 에너지 상태 / 사소한 신체적 기분 변화와 전환의 시기"),
        2 => ("Sampat", "물질적 혜택과 재물운 상승 / 가치 있는 것을 획득하기에 매우 유리한 기운"),
        3 => ("Vipat", "돌발적인 장애물과 지연 / 중요한 결정을 멈추고 신중히 검토해야 하는 위기"),
        4 => ("Kshema", "안정과 내적 보호막 획득 / 안정적인 성장을 도모하고 내적 평화를 누리기에 길함"),
        5 => ("Pratyak", "기대에 어긋나는 지연 및 대인관계 마찰 / 행동의 신중함과 절제가 요구됨"),
        6 => ("Sadhaka", "성취와 목표 달성 / 진행 중인 프로젝트나 일에서 성공적 결실을 맺기에 매우 길함"),
        7 => ("Vadha", "위험 및 에너지 소멸 / 극도로 흉한 운이므로 무모한 투자나 활동을 절대 금함"),
        8 => ("Mitra", "우호적인 조력자 등장 및 관계의 조화 / 협력적인 지원과 소통이 부드럽게 흐름"),
        9 => ("Param Mitra", "최상의 대인관계 및 동반자적 길운 / 인생의 중요한 멘토나 계약을 성사시키기에 아주 유리함"),
        _ => ("Unknown", "판정 불가"),
    };

    // 6. Calculate Ashtakavarga
    let find_sign_idx = |name: &str| -> u8 {
        natal_chart.planets.iter()
            .find(|p| p.name == name)
            .map(|p| p.sign_index)
            .unwrap_or(0)
    };

    let ashtakavarga_input = BhinnaAshtakavargaInput {
        sun: find_sign_idx("Sun"),
        moon: find_sign_idx("Moon"),
        mars: find_sign_idx("Mars"),
        mercury: find_sign_idx("Mercury"),
        jupiter: find_sign_idx("Jupiter"),
        venus: find_sign_idx("Venus"),
        saturn: find_sign_idx("Saturn"),
        lagna: (lagna_sign - 1) as u8,
    };

    let bhinna_tables = bhinna_ashtakavarga(&ashtakavarga_input);
    let sav_table = sarvashtakavarga(&bhinna_tables);

    let transit_moon_sign_idx = ((transit_moon.longitude as i32) / 30) as usize % 12;
    let transit_moon_sav = sav_table.get(transit_moon_sign_idx).copied().unwrap_or(0);
    let transit_moon_bav = bhinna_tables.get(1).and_then(|t| t.bindus.get(transit_moon_sign_idx)).copied().unwrap_or(0);

    // 7. Calculate Activated Triggers (Gochara Vedha, Double Transit, Transit-to-Natal Aspect)
    let mut activated_triggers = Vec::new();
    const RASHI_NAMES: [&str; 12] = [
        "Aries", "Taurus", "Gemini", "Cancer", "Leo", "Virgo",
        "Libra", "Scorpio", "Sagittarius", "Capricorn", "Aquarius", "Pisces"
    ];

    // (1) Transit-to-Natal Aspect
    for p_trans in &relative_transit_chart.planets {
        let p_trans_rashi = (((p_trans.longitude) / 30.0) as i32) % 12;
        for p_natal in &natal_chart.planets {
            let p_natal_rashi = p_natal.sign_index as i32;
            let d = ((p_natal_rashi - p_trans_rashi + 12) % 12) + 1;

            let is_aspecting = match p_trans.name.as_str() {
                "Jupiter" => d == 1 || d == 5 || d == 7 || d == 9,
                "Mars" => d == 1 || d == 4 || d == 7 || d == 8,
                "Saturn" => d == 1 || d == 3 || d == 7 || d == 10,
                _ => d == 1 || d == 7,
            };

            if is_aspecting {
                let relationship = if d == 1 {
                    format!("Conjoining Natal {} in {}", p_natal.name, RASHI_NAMES[p_natal_rashi as usize])
                } else {
                    format!("Aspecting Natal {} ({}th Sthana Drishti) in {}", p_natal.name, d, RASHI_NAMES[p_natal_rashi as usize])
                };

                activated_triggers.push(ActivatedTrigger {
                    name: p_trans.name.clone(),
                    relationship,
                    transit_house_from_lagna: p_trans.house,
                });
            }
        }
    }

    // (2) Double Transit (Jupiter & Saturn aspecting the same Natal sign/planet)
    if let (Some(t_jup), Some(t_sat)) = (
        relative_transit_chart.planets.iter().find(|p| p.name == "Jupiter"),
        relative_transit_chart.planets.iter().find(|p| p.name == "Saturn")
    ) {
        let jup_rashi = (((t_jup.longitude) / 30.0) as i32) % 12;
        let sat_rashi = (((t_sat.longitude) / 30.0) as i32) % 12;

        let mut jup_aspects = Vec::new();
        for &d in &[1, 5, 7, 9] {
            jup_aspects.push((jup_rashi + d - 1) % 12);
        }
        let mut sat_aspects = Vec::new();
        for &d in &[1, 3, 7, 10] {
            sat_aspects.push((sat_rashi + d - 1) % 12);
        }

        for r in 0..12 {
            if jup_aspects.contains(&r) && sat_aspects.contains(&r) {
                for p_natal in &natal_chart.planets {
                    if p_natal.sign_index as i32 == r {
                        let house = ((r - (lagna_sign as i32 - 1) + 12) % 12) + 1;
                        activated_triggers.push(ActivatedTrigger {
                            name: "Double Transit".to_string(),
                            relationship: format!("Transit Jupiter and Saturn are con-aspecting Natal {} in {}", p_natal.name, RASHI_NAMES[r as usize]),
                            transit_house_from_lagna: house,
                        });
                    }
                }
            }
        }
    }

    // (3) Gochara Vedha
    let get_vedha_info = |planet: &str, house: i32| -> Option<i32> {
        match planet {
            "Sun" => match house {
                3 => Some(9),
                6 => Some(12),
                10 => Some(4),
                11 => Some(5),
                _ => None
            },
            "Moon" => match house {
                1 => Some(5),
                3 => Some(9),
                6 => Some(12),
                7 => Some(2),
                10 => Some(4),
                11 => Some(8),
                _ => None
            },
            "Mars" | "Saturn" => match house {
                3 => Some(12),
                6 => Some(9),
                11 => Some(5),
                _ => None
            },
            "Mercury" => match house {
                2 => Some(5),
                4 => Some(3),
                6 => Some(9),
                8 => Some(1),
                10 => Some(8),
                11 => Some(12),
                _ => None
            },
            "Jupiter" => match house {
                2 => Some(12),
                5 => Some(4),
                7 => Some(3),
                9 => Some(10),
                11 => Some(8),
                _ => None
            },
            "Venus" => match house {
                1 => Some(8),
                2 => Some(7),
                3 => Some(1),
                4 => Some(10),
                5 => Some(9),
                8 => Some(5),
                9 => Some(11),
                11 => Some(6),
                12 => Some(3),
                _ => None
            },
            _ => None
        }
    };

    let moon_rashi = (((transit_moon.longitude) / 30.0) as i32) % 12;
    for p_trans in &relative_transit_chart.planets {
        if p_trans.name == "Rahu" || p_trans.name == "Ketu" {
            continue;
        }
        let p_trans_rashi = (((p_trans.longitude) / 30.0) as i32) % 12;
        let house_from_moon = ((p_trans_rashi - moon_rashi + 12) % 12) + 1;

        if let Some(vedha_house) = get_vedha_info(&p_trans.name, house_from_moon) {
            for ob_trans in &relative_transit_chart.planets {
                if ob_trans.name == p_trans.name || ob_trans.name == "Rahu" || ob_trans.name == "Ketu" {
                    continue;
                }
                let ob_trans_rashi = (((ob_trans.longitude) / 30.0) as i32) % 12;
                let ob_house_from_moon = ((ob_trans_rashi - moon_rashi + 12) % 12) + 1;

                if ob_house_from_moon == vedha_house {
                    if (p_trans.name == "Sun" && ob_trans.name == "Saturn") || (p_trans.name == "Saturn" && ob_trans.name == "Sun") {
                        continue;
                    }
                    if (p_trans.name == "Mercury" && ob_trans.name == "Moon") || (p_trans.name == "Moon" && ob_trans.name == "Mercury") {
                        continue;
                    }

                    activated_triggers.push(ActivatedTrigger {
                        name: p_trans.name.clone(),
                        relationship: format!(
                            "Auspicious {}th House transit is obstructed by Transit {} in {}th House (Gochara Vedha)",
                            house_from_moon, ob_trans.name, ob_house_from_moon
                        ),
                        transit_house_from_lagna: p_trans.house,
                    });
                    break;
                }
            }
        }
    }

    let daily_metrics = DailyMetrics {
        tithi,
        nakshatra,
        yoga,
        karana,
        weekday,
        weekday_ruler,
        tara_bala_category: tara_bala_category.to_string(),
        tara_bala_description: tara_bala_description.to_string(),
        transit_moon_sav,
        transit_moon_bav,
        activated_triggers,
    };

    Ok(Json(ChartResponse {
        status: "success".to_string(),
        message: "Calculated chart successfully".to_string(),
        natal_chart,
        transit_chart: relative_transit_chart,
        dasha,
        current_dasha,
        transit_moon_house,
        daily_metrics,
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
        for p in &planets {
            println!("PLANET_DEBUG: {} -> Longitude: {}, Sign: {}, House: {}", p.name, p.longitude, p.sign, p.house);
        }
        assert!(planets.iter().any(|p| p.name == "Sun"));
        assert!(planets.iter().any(|p| p.name == "Moon"));
        assert!(planets.iter().any(|p| p.name == "Rahu"));
        assert!(planets.iter().any(|p| p.name == "Ketu"));
        
        let t_planets = response.transit_chart.planets;
        for p in &t_planets {
            println!("TRANSIT_DEBUG: {} -> Longitude: {}, Sign: {}, House: {}", p.name, p.longitude, p.sign, p.house);
        }
        assert!(t_planets.iter().any(|p| p.name == "Sun"));
        assert!(t_planets.iter().any(|p| p.name == "Moon"));
        
        // Vimshottari dasha 검증
        assert_eq!(response.dasha.moon_nakshatra.name(), "Moola");
    }
}

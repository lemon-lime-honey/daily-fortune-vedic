use serde::{Deserialize, Serialize};
use vedaksha::prelude::{ComputedChart, dasha::vimshottari::VimshottariDasha};

#[derive(Debug, Deserialize)]
pub struct ChartRequest {
    pub year: i32,
    pub month: u32,
    pub day: u32,
    pub hour: u32,
    pub minute: u32,
    pub latitude: f64,
    pub longitude: f64,
    pub tz_offset: f64,
    
    pub target_year: i32,
    pub target_month: u32,
    pub target_day: u32,
    pub target_hour: Option<u32>,
    pub target_minute: Option<u32>,
    pub target_tz_offset: Option<f64>,
}

#[derive(Debug, Serialize)]
pub struct RelativeTransitPlanet {
    pub name: String,
    pub longitude: f64,
    pub latitude: f64,
    pub distance: f64,
    pub speed: f64,
    pub sign: String,
    pub house: i32,
    pub retrograde: bool,
}

#[derive(Debug, Serialize)]
pub struct RelativeTransitChart {
    pub planets: Vec<RelativeTransitPlanet>,
    pub lagna_sign: i32,
}

#[derive(Debug, Serialize)]
pub struct ActivatedTrigger {
    pub name: String,
    pub relationship: String,
    pub transit_house_from_lagna: i32,
}

#[derive(Debug, Serialize)]
pub struct DailyMetrics {
    pub tithi: String,
    pub nakshatra: String,
    pub yoga: String,
    pub karana: String,
    pub weekday: String,
    pub weekday_ruler: String,
    pub tara_bala_category: String,
    pub tara_bala_description: String,
    pub transit_moon_sav: u8,
    pub transit_moon_bav: u8,
    pub activated_triggers: Vec<ActivatedTrigger>,
}

#[derive(Debug, Serialize)]
pub struct ChartResponse {
    pub status: String,
    pub message: String,
    pub natal_chart: ComputedChart,
    pub transit_chart: RelativeTransitChart,
    pub dasha: VimshottariDasha,
    pub current_dasha: String,
    pub transit_moon_house: String,
    pub daily_metrics: DailyMetrics,
}

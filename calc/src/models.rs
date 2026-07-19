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
pub struct ChartResponse {
    pub status: String,
    pub message: String,
    pub natal_chart: ComputedChart,
    pub transit_chart: ComputedChart,
    pub dasha: VimshottariDasha,
    pub current_dasha: String,
    pub transit_moon_house: String,
}

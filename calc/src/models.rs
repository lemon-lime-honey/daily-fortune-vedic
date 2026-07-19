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
}

#[derive(Debug, Serialize)]
pub struct ChartResponse {
    pub status: String,
    pub message: String,
    pub chart: ComputedChart,
    pub dasha: VimshottariDasha,
}

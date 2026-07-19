#!/bash
if [ ! -f .env ]; then
  echo "ERROR: .env file not found."
  exit 1
fi

# Load variables safely
export $(grep -v '^#' .env | xargs)

REQUIRED_VARS=(
  BIRTH_DATE
  BIRTH_TIME
  BIRTH_LAT
  BIRTH_LON
  TRANSIT_TIMEZONE
  LLM_API_KEY
  LLM_MODEL_NAME
  NOTION_API_KEY
  NOTION_TARGET_ID
  RUST_CALC_API_URL
)

MISSING=0
for var in "${REQUIRED_VARS[@]}"; do
  val="${!var}"
  if [ -z "$val" ]; then
    echo "ERROR: $var is empty or not set."
    MISSING=1
  elif [[ "$val" == *"your_"* || "$val" == *"YYYY"* ]]; then
    echo "WARNING: $var appears to have a placeholder value: $val"
  else
    echo "SUCCESS: $var is set"
  fi
done

if [ $MISSING -eq 1 ]; then
  echo "Validation FAIL"
  exit 1
else
  echo "Validation SUCCESS"
  exit 0
fi

#!/bin/sh
set -eu

DEPLOY_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$DEPLOY_DIR"

set -a
# shellcheck disable=SC1091
. ./.env
set +a

: "${EVENT_H3_CELL:?Set EVENT_H3_CELL to the target resolution-9 H3 cell}"
: "${EVENT_LAT:?Set EVENT_LAT to an approximate public event latitude}"
: "${EVENT_LNG:?Set EVENT_LNG to an approximate public event longitude}"

STARTS_AT=${EVENT_STARTS_AT:-now}
DURATION=${EVENT_DURATION:-2 hours}

docker compose --env-file .env -f compose.prod.yml exec -T postgres \
  psql -v ON_ERROR_STOP=1 -U nakama -d nakama \
  -v cell="$EVENT_H3_CELL" -v lat="$EVENT_LAT" -v lng="$EVENT_LNG" \
  -v starts="$STARTS_AT" -v duration="$DURATION" <<'SQL'
WITH fixture(kind,title,description,goal,cap,radius,metadata) AS (
  VALUES
    ('cat_cafe_rally','Cat Café Rally','Pool treats to fill the café bowls.',120,12,500,'{"resource":"treats"}'::jsonb),
    ('cardboard_fortress','Cardboard Fortress','Join a squad and reinforce the fortress.',200,20,550,'{"requiresSquad":true}'::jsonb),
    ('laser_pointer_chase','Laser Pointer Chase','Tag checkpoints or use the stationary accessible path.',100,10,600,
     '{"checkpoints":[{"id":"loop-a","label":"Walking loop","stationary":false},{"id":"accessible","label":"Stationary beam","stationary":true}]}'::jsonb)
)
INSERT INTO catdex_events
  (id,h3_cell,kind,title,description,goal,starts_at,ends_at,radius_m,per_user_cap,
   latitude,longitude,metadata,personal_reward,community_reward)
SELECT gen_random_uuid(), :'cell', kind,title,description,goal,
       :'starts'::timestamptz, :'starts'::timestamptz + :'duration'::interval,
       radius,cap, :'lat'::float8, :'lng'::float8, metadata,5,20
FROM fixture
RETURNING id,kind,title,starts_at,ends_at;
SQL

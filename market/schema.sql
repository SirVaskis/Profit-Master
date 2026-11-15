CREATE SCHEMA IF NOT EXISTS market;
CREATE SCHEMA IF NOT EXISTS reporting;
REVOKE ALL ON SCHEMA market FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE TABLE IF NOT EXISTS market.schema_version (version integer PRIMARY KEY);
INSERT INTO market.schema_version VALUES (1) ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS market.uploads (
    batch_id uuid PRIMARY KEY,
    contributor text NOT NULL,
    producer_id uuid NOT NULL,
    source_id uuid NOT NULL,
    addon text NOT NULL CHECK (addon IN ('ProfitMaster','ProfitTop')),
    snapshot_sha256 text NOT NULL,
    revision_ns bigint NOT NULL,
    part_index integer NOT NULL,
    part_count integer NOT NULL,
    snapshot_record_count integer NOT NULL,
    record_count integer NOT NULL,
    body_sha256 text NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (contributor,producer_id,source_id,addon,snapshot_sha256,part_index)
);

CREATE TABLE IF NOT EXISTS market.observations (
    contributor text NOT NULL,
    producer_id uuid NOT NULL,
    source_id uuid NOT NULL,
    record_key text NOT NULL,
    addon text NOT NULL,
    market_key text NOT NULL,
    item_id integer NOT NULL,
    variant text NOT NULL,
    metric text NOT NULL,
    observed_at timestamptz NOT NULL,
    price numeric NOT NULL CHECK(price > 0),
    item_name text,
    vendor_copper bigint,
    low numeric,
    high numeric,
    samples bigint,
    sample_units bigint,
    units_kind text,
    mean_sum numeric,
    scan_count bigint,
    revision_ns bigint NOT NULL,
    batch_id uuid NOT NULL REFERENCES market.uploads(batch_id),
    PRIMARY KEY(contributor,producer_id,source_id,record_key)
);
CREATE INDEX IF NOT EXISTS observations_item_time ON market.observations(item_id,observed_at DESC);
CREATE INDEX IF NOT EXISTS observations_market_time ON market.observations(market_key,observed_at DESC);

-- Static item classifications are shared between both addon feeds on Forever.
CREATE TABLE IF NOT EXISTS market.item_catalog (
    item_id integer PRIMARY KEY,
    item_name text,
    class_id integer NOT NULL,
    subclass_id integer NOT NULL,
    class_name text NOT NULL,
    subclass_name text NOT NULL,
    revision_ns bigint NOT NULL
);

CREATE TABLE IF NOT EXISTS market.scan_times (
    contributor text NOT NULL,
    producer_id uuid NOT NULL,
    source_id uuid NOT NULL,
    addon text NOT NULL,
    scanned_at timestamptz NOT NULL,
    PRIMARY KEY(contributor,producer_id,source_id,scanned_at)
);

-- Each source's mutable daily/snapshot slot has one row. Re-uploading daily
-- totals replaces that row; it never adds cumulative observation counts twice.
CREATE OR REPLACE VIEW reporting.price_history AS
SELECT o.addon,o.market_key,o.item_id,o.variant,o.metric,o.observed_at,o.price,
       COALESCE(o.item_name,c.item_name) AS item_name,o.vendor_copper,
       o.low,o.high,o.samples,o.sample_units,o.units_kind,o.contributor,o.source_id::text AS source_id,
       c.class_id,c.subclass_id,c.class_name,c.subclass_name
FROM market.observations o LEFT JOIN market.item_catalog c USING(item_id);

-- Average charts never substitute floors or daily low/high/latest quotes.
-- PM stores daily cumulative sums/counts, not one historical row per scan.
CREATE OR REPLACE VIEW reporting.average_history AS
SELECT o.addon,o.market_key,o.item_id,o.variant,o.metric,o.observed_at,
       COALESCE(o.item_name,c.item_name) AS item_name,o.contributor,o.source_id::text AS source_id,
       c.class_id,c.subclass_id,c.class_name,c.subclass_name,
       CASE WHEN o.metric='trimmed_mean' THEN o.mean_sum/NULLIF(o.scan_count,0) ELSE o.price END AS average_copper,
       CASE WHEN o.metric='trimmed_mean' THEN 'Daily trimmed average' ELSE 'Sampled listing average' END AS average_method,
       o.scan_count
FROM market.observations o LEFT JOIN market.item_catalog c USING(item_id)
WHERE o.metric IN ('trimmed_mean','listing_vwap');

-- Forever's AH class set (not Retail-only classes); subclass names come from
-- the client's actual item metadata, never guessed from item names.
CREATE OR REPLACE VIEW reporting.ah_categories AS
SELECT * FROM (VALUES (2,'Weapons'),(4,'Armor'),(1,'Containers'),(0,'Consumables'),
    (7,'Trade Goods'),(6,'Projectiles'),(11,'Quivers'),(9,'Recipes'),(5,'Reagents'),
    (15,'Miscellaneous'),(12,'Quest Items'),(13,'Keys'),(-1,'Unclassified')) AS c(class_id,name);

CREATE OR REPLACE VIEW reporting.trimmed_averages AS
SELECT addon,market_key,item_id,variant,contributor,source_id::text AS source_id,
       SUM(mean_sum)/NULLIF(SUM(scan_count),0) AS average_copper,
       SUM(scan_count) AS completed_scans,MAX(observed_at) AS last_observed_at
FROM market.observations WHERE metric='trimmed_mean'
GROUP BY addon,market_key,item_id,variant,contributor,source_id;

-- Saved-history imports are not invented full scans. This dashboard summary
-- counts a save only when every declared part committed successfully.
CREATE OR REPLACE VIEW reporting.saved_imports AS
SELECT contributor,addon,producer_id::text AS producer_id,source_id::text AS source_id,
       snapshot_sha256,MAX(received_at) AS received_at,MAX(revision_ns) AS revision_ns,
       SUM(record_count) AS records,MAX(part_count) AS expected_parts,COUNT(*) AS received_parts,
       COUNT(*)=MAX(part_count) AS complete
FROM market.uploads
GROUP BY contributor,addon,producer_id,source_id,snapshot_sha256;

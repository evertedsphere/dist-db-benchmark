-- non-partitioned
CREATE TABLE hdb_metadata (
  project_id UUID NOT NULL PRIMARY KEY,
  metadata JSON NOT NULL,
  resource_version INTEGER NOT NULL DEFAULT 1
);

-- partitioned
CREATE TABLE IF NOT EXISTS hdb_metadata_split (
  project_id UUID NOT NULL,
  metadata JSON NOT NULL,
  resource_version INTEGER NOT NULL DEFAULT 1,
  geo_partition VARCHAR
) PARTITION BY LIST (geo_partition);

CREATE TABLE hdb_metadata_split_us
    PARTITION OF hdb_metadata_split
      (project_id, metadata, resource_version, geo_partition,
      PRIMARY KEY (project_id HASH, geo_partition))
    FOR VALUES IN ('US') TABLESPACE us_west_2_region_tablespace;

CREATE TABLE hdb_metadata_split_in
    PARTITION OF hdb_metadata_split
      (project_id, metadata, resource_version, geo_partition,
      PRIMARY KEY (project_id HASH, geo_partition))
    FOR VALUES IN ('IN') TABLESPACE ap_south_1_tablespace;

CREATE TABLE hdb_metadata_split_eu
    PARTITION OF hdb_metadata_split
      (project_id, metadata, resource_version, geo_partition,
      PRIMARY KEY (project_id HASH, geo_partition))
    FOR VALUES IN ('EU') TABLESPACE eu_central_1_tablespace;

insert into hdb_metadata (project_id, metadata, resource_version)
select gen_random_uuid(), '{}'::json, generate_series(1, 10000, 1);

insert into hdb_metadata_split (project_id, metadata, resource_version, geo_partition)
select gen_random_uuid(), '{}'::json, generate_series(1, 10000, 1), 'US';

insert into hdb_metadata_split (project_id, metadata, resource_version, geo_partition)
select gen_random_uuid(), '{}'::json, generate_series(1, 10000, 1), 'IN';

insert into hdb_metadata_split (project_id, metadata, resource_version, geo_partition)
select gen_random_uuid(), '{}'::json, generate_series(1, 10000, 1), 'EU';

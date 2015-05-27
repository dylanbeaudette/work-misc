
# example:
# sh get-touching.sh ca792_official.shp CA792 26911
# sh get-touching.sh ca630_official.shp CA630 26910

# distance threshold for locating adjacent (almost touching SSURGO polygons)
thresh=0.0001

new=$1
new_areasymbol=$2
srid=$3


# load new data and inverse project to GCS WGS84
# overwrite existing table of the same name
shp2pgsql -s ${srid}:4326 -d -g wkb_geometry -I $new dylan.join_new_data | psql -q -U postgres ssurgo_combined

echo "
-- set path
SET search_path to dylan, public, ssurgo;

-- check ST_DWithin: works well, but units are in degrees
-- ----> cannot cast to geography because spatial indices are not used
-- -----> threshold of about 0.0001  degrees makes sense ~ 10 meters

-- get data + geometry for all SSURGO data within threshold distance of CA792
-- note that for each polygon of CA792 there could be 1 or more corresponding SSURGO polygons
-- this results in multiple instances of the same polygons in the table
-- ~ 4 minutes
DROP TABLE dylan.new_and_ssurgo;
CREATE TABLE dylan.new_and_ssurgo AS
SELECT gid, join_new_data.musym as new_musym, 
mapunit.areasymbol as ssurgo_areasymbol, mapunit.musym as ssurgo_musym, mapunit.muname, mapunit.mukey, ogc_fid, 
join_new_data.wkb_geometry as source_geom, mapunit_poly.wkb_geometry as ssurgo_geom
FROM
-- filter those SSURGO polygons that are within threshold distance of new polygons
join_new_data JOIN mapunit_poly ON ST_DWithin(join_new_data.wkb_geometry, mapunit_poly.wkb_geometry, $thresh)
-- filter out overlapping polygons (usually USFS islands)

JOIN mapunit USING(mukey)
-- filter out any SSURGO polygons with the same areasymbol
WHERE mapunit.areasymbol != LOWER('$new_areasymbol')
ORDER BY gid ASC;

-- UNION exterior ring of new and nearby SSURGO
DROP TABLE dylan.new_and_ssurgo_union;
CREATE TABLE dylan.new_and_ssurgo_union AS
SELECT '$new_areasymbol' as areasymbol, 'new'::text as survey_id, new_musym as musym, ''::text as muname, ''::text as mukey, 
ST_Transform(source_geom, $srid) as geom 
FROM new_and_ssurgo
UNION
SELECT ssurgo_areasymbol as areasymbol, 'ssurgo'::text as survey_id, ssurgo_musym as musym, muname, mukey, 
ST_Transform(ssurgo_geom, $srid) as geom 
FROM new_and_ssurgo;

" | psql -U postgres ssurgo_combined


# save exterior ring of polygons in new and touching SSURGO
# CRS is same as original CRS of new data
pgsql2shp -f ${new_areasymbol}_ssurgo_union.shp -g geom -u postgres ssurgo_combined dylan.new_and_ssurgo_union




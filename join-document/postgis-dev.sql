-- 

-- load data
shp2pgsql -s 4326 -c -g wkb_geometry -I ca792_official.shx ca792 | psql -U postgres ssurgo_combined

-- set path
\timing
SET  search_path to public, ssurgo;

-- ST_Touches() : this doesn't work due to topological errors


-- check ST_DWithin: works well, but units are in degrees
-- ----> cannot case to geography because spatial indices are not used
-- -----> threshold of about 0.0001  degrees makes sense ~ 10 meters
\set thresh 0.0001

-- just select map unit data: 10 seconds
SELECT gid, ca792.musym as ca792_musym, mapunit.muname, mapunit.mukey, ogc_fid
FROM
ca792 JOIN mapunit_poly ON ST_DWithin(ca792.wkb_geometry, mapunit_poly.wkb_geometry, :thresh)
JOIN mapunit USING(mukey)
WHERE mapunit.areasymbol != 'ca792'
AND ca792.musym = '1101';

-- get data + geometry for all SSURGO data within threshold distance of CA792
-- note that for each polygon of CA792 there could be 1 or more corresponding SSURGO polygons
-- this results in multiple instances of the same polygons in the table
-- ~ 4 minutes
DROP TABLE ca792_ssurgo;
CREATE TABLE ca792_ssurgo AS
SELECT gid, ca792.musym as ca792_musym, mapunit.muname, mapunit.mukey, ogc_fid, 
ca792.wkb_geometry as source_geom, mapunit_poly.wkb_geometry as ssurgo_geom
FROM
ca792 JOIN mapunit_poly ON ST_DWithin(ca792.wkb_geometry, mapunit_poly.wkb_geometry, :thresh)
JOIN mapunit USING(mukey)
WHERE mapunit.areasymbol != 'ca792'
AND mapunit.muname != 'No Digital Data Available'
AND ca792.musym NOT IN ('NOTCOM', 'notcom')
ORDER BY gid ASC;

-- UNION exterior "ring" of CA792 and nearby SSURGO
DROP TABLE ca792_ssurgo_union;
CREATE TABLE ca792_ssurgo_union AS
SELECT 'ca792'::text as survey_id, ca792_musym as mukey, source_geom as geom FROM ca792_ssurgo
UNION
SELECT 'ssurgo'::text as survey_id, mukey, ssurgo_geom as geom FROM ca792_ssurgo;


--
-- get / dump the unique set of SSURGO data that is touching CA792
--
DROP TABLE ca792_unique_touching_ssurgo;
CREATE TABLE ca792_unique_touching_ssurgo AS
SELECT wkb_geometry, ogc_fid, mukey, muname
FROM mapunit_poly JOIN mapunit USING(mukey)
WHERE ogc_fid IN (SELECT DISTINCT ogc_fid from ca792_ssurgo);


-- test spatial alignment of source and SSURGO polygons
SELECT gid, ogc_fid, ST_Touches(source_geom, ssurgo_geom), ST_Overlaps(source_geom, ssurgo_geom), ST_Intersects(source_geom, ssurgo_geom)
FROM ca792_ssurgo;

-- what do the distances > 0 mean?
-- ----> not important
SELECT gid, ogc_fid, ST_Touches(source_geom, ssurgo_geom), ST_Overlaps(source_geom, ssurgo_geom), ST_Intersects(source_geom, ssurgo_geom), ST_Distance(source_geom::geography, ssurgo_geom::geography) 
FROM ca792_ssurgo;


-- try snapping SSURGO to CA792 geometry, does this help intersections?
-- ----> YES
SELECT gid, ogc_fid, ST_Intersects(source_geom, ssurgo_geom) AS t_orig, 
ST_Intersects(source_geom, ST_Snap(ssurgo_geom, source_geom, 0.0001)) AS t_snap_geom,
ST_Intersects(ST_SnapToGrid(source_geom, -118, 36, :thresh, :thresh), ST_SnapToGrid(ssurgo_geom, -118, 36, :thresh, :thresh)) AS t_snap_grid
FROM ca792_ssurgo;

-- try getting the intersection of the snapped geometries
-- note that they must be _made_ valid... not sure why
-- ----> snapping tolerance must be very small otherwise the results are a variety of geom types
-- ----> this doesn't work... data are simple features so the "fabric" is destroyed
-- ----> keep point on intersection surface... 
-- ----> depending on the thresholds, some points on the surface are "empty"
-- -----> results must be filtered when dumping to SHP
DROP TABLE ca792_ssurgo_snapped;
CREATE TABLE ca792_ssurgo_snapped AS
SELECT gid, ca792_musym, muname, mukey, ogc_fid,
ST_Intersection(ST_MakeValid(ST_SnapToGrid(source_geom, -118, 36, :thresh, :thresh)), ST_MakeValid(ST_SnapToGrid(ssurgo_geom, -118, 36, :thresh, :thresh))) as int_geom,
ST_PointOnSurface(ST_Intersection(ST_MakeValid(ST_SnapToGrid(source_geom, -118, 36, :thresh, :thresh)), ST_MakeValid(ST_SnapToGrid(ssurgo_geom, -118, 36, :thresh, :thresh)))) as int_geom_pt
FROM ca792_ssurgo;


-- save exterior ring of polygons in CA792 and touching SSURGO
pgsql2shp -f ca792_ssurgo_union.shp -g geom -u postgres ssurgo_combined ca792_ssurgo_union

-- save touching SSURGO
pgsql2shp -f touching_ssurgo.shp -g wkb_geometry -u postgres ssurgo_combined ca792_unique_touching_ssurgo

-- save a single point on the snapped intersection surface, filtering out empty geom
pgsql2shp -f snapped_intersection.shp -g int_geom_pt -u postgres ssurgo_combined "SELECT gid, ca792_musym, muname, mukey, ogc_fid, int_geom_pt FROM ca792_ssurgo_snapped WHERE ST_IsEmpty(int_geom_pt) = 'f' "










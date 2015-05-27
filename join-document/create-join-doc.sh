#!/bin/bash
set -x

## NOTE: this only works when run interactively

## native coordinate system of source data: usually UTM z10 or z11 NAD83
## "left-hand" data are the new data
## "right-hand" data are SSURGO

# ssurgo-new_data-union
new=$1
prefix=$2

# threshold in meters
thresh=10

# import and clean topology: still has errors
v.in.ogr --q --o dsn=$new output=ssurgo_join snap=$thresh

# add cats to boundaries in layer 2
v.category --q --o input=ssurgo_join type=boundary option=add layer=2 output=ssurgo_join_b_cats

# in order to upload, we need to make a new att table in layer 2
v.db.addtable --q map=ssurgo_join_b_cats table=ssurgo_join_b_cats_boundaries layer=2 columns="left int, right int"

# double-check table connections: 
# v.db.connect -p ssurgo_join_b_cats

# upload left | right area cats, for each boundary cat
v.to.db --q map=ssurgo_join_b_cats type=boundary layer=2 qlayer=1 option=sides columns="left,right"

# convert left | right cats into survey names and symbols
# keep only "join" boundaries
q="SELECT ssurgo_join_b_cats_boundaries.cat as bdy_id, 
l.SURVEY_ID as left_survey, r.SURVEY_ID as right_survey, 
l.MUSYM as left_musym, r.MUSYM as right_musym, 
r.MUNAME as right_muname, r.MUKEY as right_mukey, r.AREASYMBOL as righ_areasymbol
FROM ssurgo_join_b_cats_boundaries 
JOIN ssurgo_join as l ON left=l.cat 
JOIN ssurgo_join as r on right=r.cat 
WHERE l.SURVEY_ID != r.SURVEY_ID 
ORDER BY l.SURVEY_ID"

# test: OK
# db.select sql="$q"

# ID those segments that are digitized backwards from the others
# left-hand survey should always be the source data, right should be ssurgo
backwards="SELECT ssurgo_join_b_cats_boundaries.cat as bdy_id
FROM ssurgo_join_b_cats_boundaries 
JOIN ssurgo_join as l ON left=l.cat 
JOIN ssurgo_join as r on right=r.cat 
WHERE l.SURVEY_ID != r.SURVEY_ID
AND l.SURVEY_ID = 'ssurgo'"

bdy_to_flip_cats=`db.select -c sql="$backwards"`
bdy_to_flip_cats=`echo $bdy_to_flip_cats | tr ' ' ','`

# flip line segments in original data
v.edit --q ssurgo_join_b_cats layer=2 type=boundary cats=$bdy_to_flip_cats tool=flip

# re-compute left | right information
v.to.db --q map=ssurgo_join_b_cats type=boundary layer=2 qlayer=1 option=sides columns="left,right"

# test: OK
# db.select sql="$q"

## TODO: this will probably throw an error
# create new table to store results
db.execute --q -i "DROP TABLE join_data;"
db.execute --q sql="CREATE TABLE join_data ( bdy_id integer, l_survey varchar(10), r_survey varchar(10), l_musym varchar(10), r_musym varchar(10), r_muname varchar(10), r_mukey varchar(10), r_asym varchar(10) )"
db.execute --q sql="INSERT INTO join_data $q"


# manually copy over join data
v.db.addcolumn --q map=ssurgo_join_b_cats layer=2 columns="l_survey varchar(10), r_survey varchar(10), l_musym varchar(10), r_musym varchar(10), r_muname varchar(10), r_mukey varchar(10), r_asym varchar(10)"

# copy over each column... PITA, limitation of SQLite
columns="l_survey
r_survey
l_musym
r_musym
r_muname
r_mukey
r_asym"

for x in $columns
do
db.execute --q sql="UPDATE ssurgo_join_b_cats_boundaries SET $x = (SELECT $x FROM join_data WHERE join_data.bdy_id = ssurgo_join_b_cats_boundaries.cat)"
done

# extract only those boundaries that define join decisions, keep original cats
# note, results go into layer 2
v.extract --o --q input=ssurgo_join_b_cats layer=2 type=boundary where="l_survey IS NOT NULL" output=ssurgo_final_join new=-1


### associate each join segment with a polyline of contiguous segments

# combine join segments into contiguous polylines
v.build.polylines --o --q ssurgo_final_join output=join_pl type=boundary
v.category --o --q join_pl type=boundary output=join_pl_cats option=add layer=1

# add column in join segments to store:
# chunk ID, distance from chunk (should be 0), distance along chunk
v.db.addcolumn --q map=ssurgo_final_join layer=2 columns="chunk_id integer, chunk_d double, d_along double"

## this is freakin genious!
# upload chunk ID, chunk distance, and distance along chunk to join segments from closest chunk
v.distance --q from=ssurgo_final_join from_layer=2 from_type=boundary to=join_pl_cats to_type=boundary column=chunk_id,chunk_d,d_along upload=cat,dist,to_along 

# check: OK
# db.select "select * from ssurgo_final_join ORDER BY chunk_id, d_along ASC"


### export in the natural order along chunks 
## this is kind of slow, but appears to work
export_order_cats=`db.select -c "select cat from ssurgo_final_join ORDER BY chunk_id, d_along ASC"`

# toggle first record flag and start loop
first_record=1
for this_cat in $export_order_cats ; do

# extract current record
v.extract --o --q input=ssurgo_final_join layer=2 type=boundary cats="$this_cat" output=temp_feature_xxx new=-1

# if this is the first record in the set the nmake a new layer
if [[ "$first_record" == "1" ]] ; then
# overwrite existing data
v.out.ogr --o --q -e input=temp_feature_xxx layer=2 type=boundary dsn=output_data olayer=${prefix}_join_lines otype=line
# toggle first record flag
first_record=0

# otherwise append to this layer
else
v.out.ogr --q -a input=temp_feature_xxx layer=2 type=boundary dsn=output_data olayer=${prefix}_join_lines otype=line

fi

# clean up
g.remove --q vect=temp_feature_xxx
done



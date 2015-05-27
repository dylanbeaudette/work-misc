library(rgdal)
library(sharpshootR)

## pre-processing: get the data from FGB and save as SHP

# SEKI
x <- readOGR(dsn='l:/CA792/ca792_spatial/FG_CA792_OFFICIAL.gdb', layer='ca792_a')
writeOGR(x, dsn='CA792', layer='ca792_official', driver = 'ESRI Shapefile', overwrite_layer = TRUE)

# CA630
x <- readOGR(dsn='l:/CA630/FG_CA630_OFFICIAL.gdb', layer='ca630_a')
writeOGR(x, dsn='CA630', layer='ca630_official', driver = 'ESRI Shapefile', overwrite_layer = TRUE)


## send to PostGIS / GRASS for the hard stuff


## post-processing: generate a join decision / line segment ID

# SEKI
x <- readOGR(dsn='CA792', layer = 'join_lines', stringsAsFactors = FALSE)
# make a unique ID for joing decisions that should survive subsequent re-generation of the join document
x$jd_id <- generateLineHash(x)
# save new version to standard location
writeOGR(x, dsn='l:/CA792/join-document', layer='join_lines', driver = 'ESRI Shapefile', overwrite_layer = TRUE)
write.csv(x@data, file='l:/CA792/join-document/text-version.csv', row.names=FALSE)

# make network diagram:
a <- joinAdjacency(x)

pdf(file='l:/CA792/join-document/network-diagram.pdf', width = 12, height = 12)
par(mar=c(0,0,0,0))
plotSoilRelationGraph(a, spanning.tree='max', edge.scaling.factor=1, vertex.scaling.factor = 2, edge.transparency = 0)
dev.off()


# CA630
x <- readOGR(dsn='CA630', layer = 'ca630_join_lines', stringsAsFactors = FALSE)
# make a unique ID for joing decisions that should survive subsequent re-generation of the join document
x$jd_id <- generateLineHash(x)
# save new version to standard location
writeOGR(x, dsn='l:/CA630/join-document', layer='join_lines', driver = 'ESRI Shapefile', overwrite_layer = TRUE)
write.csv(x@data, file='l:/CA630/join-document/text-version.csv', row.names=FALSE)

# make network diagram:
a <- joinAdjacency(x)

pdf(file='l:/CA630/join-document/network-diagram.pdf', width = 12, height = 12)
par(mar=c(0,0,0,0))
plotSoilRelationGraph(a, spanning.tree='max', edge.scaling.factor=1, vertex.scaling.factor = 2, edge.transparency = 0)
dev.off()


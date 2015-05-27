library(rgdal)
library(sharpshootR)
library(digest)

x <- readOGR(dsn='CA792', layer = 'join_lines', stringsAsFactors = FALSE)

# get relationship from left / right musym


plotSoilRelationGraph(r$adjMat, spanning.tree='max', edge.scaling.factor=0.1, vertex.scaling.factor=1)
plotSoilRelationGraph(r$adjMat, spanning.tree=0.9, edge.scaling.factor=0.1)

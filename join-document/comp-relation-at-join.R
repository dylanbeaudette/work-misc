library(soilDB)
library(sharpshootR)
library(plyr)
library(scales)
library(igraph)
library(RColorBrewer)
library(Cairo)
library(rgdal)

# load SURRGO components that touch CA630 (~ 1km)
res <- read.csv('ca630-ssurgo-data.csv', stringsAsFactors=FALSE)

# normalize coponent names
res$compname <- tolower(res$compname)

# keep only major components
res <- subset(res, majcompflag == 'Yes')

# throw-out rock outcrop units
res <- subset(res, compname != 'rock outcrop')

# load musym and lkey from SDA
u <- unique(res$mukey)
u.in.sql <- format_SQL_in_statement(u)
q <- paste("SELECT mukey, musym, nationalmusym FROM mapunit WHERE mukey IN ", u.in.sql, "ORDER BY mukey;")
sda.data <- SDA_query(q)

# aggregate component percentages when multiple components of the same name are present
res <- ddply(res, c('mukey','compname'), summarise, comppct_r=sum(comppct_r), .progress='text')
res <- res[order(res$mukey, res$comppct_r), ]

# load spatial data (GCS NAD83)
s <- readOGR(dsn='.', layer='adjacent_ssurgo', stringsAsFactors=FALSE)
s$mukey <- s$MUKEY
s$MUKEY <- NULL

# aggregate multi-component map units by stringing together the component names
f <- function(i) {
  i <- i[order(i$comppct_r, decreasing=TRUE), ]
  r <- paste(i$compname, collapse='-')
  return(r)
}
res.agg <- ddply(res, 'mukey', f)
names(res.agg) <- c('mukey', 'maj_comp')

# join SSURGO data musym, national symbol from SDA
res.agg <- join(res.agg, sda.data, by='mukey')

# join with spatial data and save
s@data <- join(s@data, res.agg, by='mukey')

# convert to UTM z10
s <- spTransform(s, CRSobj=CRS('+proj=utm +zone=10 +datum=NAD83'))

# save new spatial data + attributes
writeOGR(s, dsn='L:/Geodata/1project_data/ssurgo-join', layer='touching_polygons', overwrite_layer=TRUE, driver='ESRI Shapefile')

# convert into adj. matrix without using component pct weights
m <- component.adj.matrix(res) 

# compute graph from weighted adjacency matrix: component pct weighting isn't correct
# investigate with: dotchart(sort(rank(m[s, ])), pch=16)
g <- graph.adjacency(m, mode='upper', weighted=TRUE)
# transfer labels
V(g)$label <- V(g)$name 

# adjust size of vertex based on degree of connectivity
v.size <- sqrt(degree(g)) * 2

# community metrics
g.com <- fastgreedy.community(g)
g.com.length <- length(g.com)
g.com.membership <- membership(g.com)

# colors for communities
if(g.com.length <= 9) cols <- brewer.pal(n=g.com.length, name='Set1') else cols <- colorRampPalette(brewer.pal(n=9, name='Set1'))(g.com.length)

cols.alpha <- alpha(cols, 0.65)
V(g)$color <- cols.alpha[membership(g.com)]

# plot graph
CairoPNG(file='touching-components.png', width=1000, height=1000)
par(mar=c(0,0,0,0)) # no margins
set.seed(1010101) # consistant output
plot(g, layout=layout.fruchterman.reingold, vertex.size=v.size, vertex.label.color='black', vertex.label.cex=0.8, vertex.label.font=1, edge.color=alpha(grey(0.6), 0.4))
dev.off()

CairoPNG(file='touching-components-dend.png', width=500, height=800)
par(mar=c(0,0,0,0)) # no margins
dendPlot(g.com, no.margin=TRUE, label.offset=0.1, col='black', colbar=cols, cex=0.85)
dev.off()

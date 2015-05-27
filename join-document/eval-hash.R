


r <- generateLineHash(x, algo='murmur32')


f <- function(h) {
  
  # interpret hash as two 4 digit hex values
  h.1 <- substr(h, 1,4)
  h.2 <- substr(h, 5,8)
  
  # convert to decimal
  d.1 <- strtoi(h.1, base=16L)
  d.2 <- strtoi(h.2, base=16L)
  
  return(data.frame(d.1=d.1, d.2=d.2))
}

plot(f(r))

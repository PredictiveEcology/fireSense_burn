## The coarse-to-fine regrid of the ignition raster is done once, not every year. The fine-grid result
## must be what the per-year postProcess() regrid gave.

## reference: the per-year code before the mapping was kept
oldFineTable <- function(coarse, fine, pixelIDs) {
  igRas <- terra::rast(coarse)
  igRas[pixelIDs] <- pixelIDs
  igRas <- postProcess(igRas, to = fine, method = "near")
  igRas[fine[] != 1] <- NA
  list(ras = igRas, dt = data.table::as.data.table(igRas, cells = TRUE))
}

## grids whose cells are not round multiples of each other
gridCoarse <- function() terra::rast(nrows = 3, ncols = 4, xmin = 0, xmax = 10, ymin = 0, ymax = 9,
                                      vals = 1, crs = "EPSG:3005")
gridFine <- function(nonFlammable = c(3L, 17L, 40L), na = 25L, nr = 11, nc = 13) {
  r <- terra::rast(nrows = nr, ncols = nc, xmin = 0, xmax = 10, ymin = 0, ymax = 9, vals = 1,
                   crs = "EPSG:3005")
  r[nonFlammable] <- 0
  r[na] <- NA
  r
}

newFineTable <- function(coarse, fine, store, pixelIDs) {
  dt <- fineCoarseTable(coarseToFineMap(coarse, fine, store), fine)
  dt[dt$chunkyPixels %in% pixelIDs, ]
}

test_that("the kept mapping gives the fine-grid ignition raster the per-year regrid gave, in two years", {
  coarse <- gridCoarse(); fine <- gridFine()
  store <- new.env()
  for (ids in list(c(1L, 2L, 5L, 6L, 9L, 12L), c(2L, 3L, 4L, 7L, 8L, 10L, 11L))) {  # year 1, year 2
    old <- oldFineTable(coarse, fine, ids)
    new <- newFineTable(coarse, fine, store, ids)
    expect_identical(as.numeric(new$pixelID), as.numeric(old$dt$cell))
    expect_identical(as.numeric(new$chunkyPixels), as.numeric(old$dt[[2]]))
    ## and as a raster: values, extent, crs
    r <- terra::rast(fine); r[] <- NA
    r[new$pixelID] <- new$chunkyPixels
    ## (terra holds NA as NaN after the regrid; the same missing cells)
    expect_equal(terra::values(r, mat = FALSE), terra::values(old$ras, mat = FALSE))
    expect_identical(as.vector(terra::ext(r)), as.vector(terra::ext(old$ras)))
    expect_identical(terra::crs(r), terra::crs(old$ras))
  }
})

test_that("the mapping is computed once, and rebuilt when either grid changes", {
  coarse <- gridCoarse(); fine <- gridFine()
  store <- new.env()
  map1 <- coarseToFineMap(coarse, fine, store)
  store$coarseToFine$marker <- "first"
  ## same grids (a different object, a different flammable pattern): reused
  map2 <- coarseToFineMap(gridCoarse(), gridFine(nonFlammable = 1:5), store)
  expect_identical(store$coarseToFine$marker, "first")
  expect_identical(map1, map2)
  ## a finer grid: rebuilt, and right
  fine2 <- gridFine(nr = 9, nc = 16)
  map3 <- coarseToFineMap(coarse, fine2, store)
  expect_null(store$coarseToFine$marker)
  expect_length(map3, terra::ncell(fine2))
  ids <- 1:12
  old <- oldFineTable(coarse, fine2, ids)
  new <- newFineTable(coarse, fine2, store, ids)
  expect_identical(as.numeric(new$chunkyPixels), as.numeric(old$dt[[2]]))
  ## a changed coarse grid: rebuilt
  coarse2 <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 10, ymin = 0, ymax = 9, vals = 1,
                         crs = "EPSG:3005")
  map4 <- coarseToFineMap(coarse2, fine2, store)
  expect_true(max(map4, na.rm = TRUE) <= 4)
  ## a changed extent with the same dimensions: rebuilt
  coarse3 <- coarse; terra::ext(coarse3) <- c(0, 10, 0, 18)
  expect_false(identical(coarseToFineMap(coarse3, fine2, store), map3))
})

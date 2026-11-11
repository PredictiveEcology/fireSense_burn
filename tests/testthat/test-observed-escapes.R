## ignitionSource = "observedEscapes": a hindcast spreads the year's observed escapes instead of drawing
## ignitions and escapes from the predicted surfaces, so it tests spread alone. Toy landscape of helper-toy.R:
## pixels of 6.25 ha, cell 1 in the west block, cell 10 in the east block, spread probability 1.

## fire polygons: a square of `side` pixels (all of them burnable) whose upper-left pixel is `cell`, with the fire's
## year and its whole size
toyFirePolys <- function(cells, years, sizesHa, side = 3L, rtm = toyRTM()) {
  xy <- terra::xyFromCell(rtm, cells)
  w <- terra::res(rtm)[1] * side
  one <- function(i) {   # cell `i` is the polygon's upper-left pixel
    x0 <- xy[i, 1] - 125; x1 <- x0 + w; y1 <- xy[i, 2] + 125; y0 <- y1 - w
    terra::vect(sprintf("POLYGON((%f %f, %f %f, %f %f, %f %f, %f %f))", x0, y0, x1, y0, x1, y1, x0, y1, x0, y0),
                crs = terra::crs(rtm))
  }
  p <- do.call(rbind, lapply(seq_along(cells), one))
  p$YEAR <- years
  p$POLY_HA <- sizesHa
  p$FIRECAUS <- "Natural"
  list(p)
}

## year 1: a 100 ha fire in the west block (escaped) and a 10 ha fire in the east (did not); year 2: 100 ha in the east
obsPolys <- function() toyFirePolys(c(1L, 6L, 56L), c(1L, 1L, 2L), c(100, 10, 100), side = 3L)

## the starts of the spread fit: fireSenseUtils::escapeFireSet(), one start per escape polygon
obsStarts <- function(polys = obsPolys()) {
  st <- fireSenseUtils::escapeFireSet(polys, toyFlammable())
  data.table::data.table(YEAR = as.integer(st$YEAR), pixelID = as.integer(st$pixelID))
}

## surfaces that would ignite and escape fires in every coarse pixel, had they been drawn from
predictedSurfaces <- function() {
  coarse <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2500, ymin = 0, ymax = 2500,
                        crs = "EPSG:3005", vals = 1)
  ras <- c(coarse * 5, coarse * 5)
  names(ras) <- c("ignitionProb", "escapeProb")
  list(fireSense_IgAndEscapeProbRas = ras,
       fireSense_IgAndEscapeDistribution = list(ignition = "count:poisson", escape = "count:poisson"),
       ignitionFitRTM = coarse)
}

## run with drawIgnitionsAndEscapes() replaced, to count its calls; burn() looks it up in the module's environment
runCountingDraws <- function(params, times = list(start = 1, end = 1), ignitions = NULL) {
  sim <- runFireSense(ignitions, times = times, params = params, doSpades = FALSE,
                      objects = c(predictedSurfaces(), list(firePolys = obsPolys())))
  mods <- environment(sim@.xData$.mods$fireSense_burn$burn)
  realDraw <- mods$drawIgnitionsAndEscapes
  draws <- 0L
  mods$drawIgnitionsAndEscapes <- function(...) { draws <<- draws + 1L; realDraw(...) }
  set.seed(3)
  sim <- suppressMessages(SpaDES.core::spades(sim, debug = FALSE))
  list(sim = sim, draws = draws)
}

test_that("observedEscapes spreads exactly the year's observed escapes and draws nothing", {
  out <- runCountingDraws(list(ignitionSource = "observedEscapes"))
  expect_identical(out$draws, 0L)
  ## the start is the fit's: the snapped centroid of the escape polygon
  expect_identical(out$sim$ignitionsAndEscapes,
                   data.table::data.table(pixelID = obsStarts()$pixelID[obsStarts()$YEAR == 1L], escaped = TRUE))
  ## the 10 ha fire did not escape and burns nothing: only the west block burns
  expect_identical(which(vals(out$sim$rstCurrentBurn) == 1), westCells())
})

test_that("observedEscapes takes the year of time(sim), also at the decimal times of a hindcast's reps", {
  out <- runCountingDraws(list(ignitionSource = "observedEscapes", .runInterval = 0.001),
                          times = list(start = 2, end = 2.0095))
  expect_identical(out$draws, 0L)
  ## ten burn events, each spreading year 2's one escape
  expect_identical(nrow(out$sim$burnSummary), 10L)
  expect_true(all(out$sim$burnSummary$igLoc == obsStarts()$pixelID[obsStarts()$YEAR == 2L]))
  expect_identical(which(vals(out$sim$rstCurrentBurn) == 1), eastCells())
})

test_that("a year without observed escapes burns nothing", {
  out <- runCountingDraws(list(ignitionSource = "observedEscapes"), times = list(start = 3, end = 3))
  expect_identical(out$draws, 0L)
  expect_identical(nrow(out$sim$ignitionsAndEscapes), 0L)
  expect_true(all(is.na(vals(out$sim$rstCurrentBurn))))
})

test_that("the default still draws from the predicted surfaces and ignores the observed fires", {
  out <- runCountingDraws(list())
  expect_identical(out$draws, 1L)
  expect_gt(nrow(out$sim$ignitionsAndEscapes), 1L)
  expect_true(all(c("igProb", "escapeProb") %in% names(out$sim$ignitionsAndEscapes)))
})

test_that("observedEscapes needs firePolys", {
  expect_error(runFireSense(NULL, params = list(ignitionSource = "observedEscapes")), "firePolys")
  expect_error(runFireSense(NULL, params = list(ignitionSource = "observed")), "ignitionSource must be")
})

test_that("observedEscapeStarts() are fireSenseUtils::escapeFireSet()'s starts, one per escape polygon", {
  polys <- obsPolys()
  st <- fireSenseUtils::escapeFireSet(polys, toyFlammable())
  got <- observedEscapeStarts(polys, toyFlammable(), 50, c("natural", "unknown"))
  expect_identical(got$pixelID, as.integer(st$pixelID))
  expect_identical(got$YEAR, as.integer(st$YEAR))
  expect_identical(nrow(got), 2L)                    # the 10 ha fire is not an escape
  ## a smaller escape size takes it in
  expect_identical(nrow(observedEscapeStarts(polys, toyFlammable(), 5, c("natural", "unknown"))), 3L)
  expect_identical(observedEscapes(got, 2), data.table::data.table(pixelID = got$pixelID[got$YEAR == 2L], escaped = TRUE))
  expect_identical(nrow(observedEscapes(got, 3)), 0L)
})

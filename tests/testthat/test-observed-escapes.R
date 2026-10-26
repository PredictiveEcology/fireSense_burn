## ignitionSource = "observedEscapes": a hindcast spreads the year's observed escapes instead of drawing
## ignitions and escapes from the predicted surfaces, so it tests spread alone. Toy landscape of helper-toy.R:
## pixels of 6.25 ha, cell 1 in the west block, cell 10 in the east block, spread probability 1.

## points at the centres of `cells`, with fire year and size
toyFirePoints <- function(cells, years, sizesHa, rtm = toyRTM()) {
  xy <- terra::xyFromCell(rtm, cells)
  terra::vect(data.frame(x = xy[, 1], y = xy[, 2], YEAR = years, SIZE_HA = sizesHa),
              geom = c("x", "y"), crs = terra::crs(rtm))
}

## year 1: a 100 ha fire on cell 1 (escaped) and a 10 ha fire on cell 10 (did not); year 2: 100 ha on cell 10
obsPoints <- function() toyFirePoints(c(1L, 10L, 10L), c(1L, 1L, 2L), c(100, 10, 100))

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
                      objects = c(predictedSurfaces(), list(ignitionFirePoints = obsPoints())))
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
  expect_identical(out$sim$ignitionsAndEscapes, data.table::data.table(pixelID = 1L, escaped = TRUE))
  ## the 10 ha fire on cell 10 did not escape and burns nothing: only the west block burns
  expect_identical(which(vals(out$sim$rstCurrentBurn) == 1), westCells())
  expect_identical(unique(out$sim$burnDT$initialPixels), 1L)
})

test_that("observedEscapes takes the year of time(sim), also at the decimal times of a hindcast's reps", {
  out <- runCountingDraws(list(ignitionSource = "observedEscapes", .runInterval = 0.001),
                          times = list(start = 2, end = 2.0095))
  expect_identical(out$draws, 0L)
  ## ten burn events, each spreading year 2's one escape (cell 10)
  expect_identical(nrow(out$sim$burnSummary), 10L)
  expect_true(all(out$sim$burnSummary$igLoc == 10L))
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

test_that("observedEscapes needs ignitionFirePoints", {
  expect_error(runFireSense(NULL, params = list(ignitionSource = "observedEscapes")), "ignitionFirePoints")
  expect_error(runFireSense(NULL, params = list(ignitionSource = "observed")), "ignitionSource must be")
})

test_that("observedEscapes() keeps escapes only, on the pixel of each point, and drops points off the grid", {
  rtm <- toyRTM()
  pts <- rbind(toyFirePoints(c(1L, 12L, 44L), 5L, c(50, 49, 6), rtm),
               terra::vect(data.frame(x = -500, y = 100, YEAR = 5L, SIZE_HA = 500), geom = c("x", "y"),
                           crs = terra::crs(rtm)))
  expect_identical(observedEscapes(pts, 5, rtm, 50), data.table::data.table(pixelID = 1L, escaped = TRUE))
  ## a fire must also be larger than one pixel (6.25 ha), as in the fit
  expect_identical(observedEscapes(pts, 5, rtm, 0)$pixelID, c(1L, 12L))
  expect_identical(nrow(observedEscapes(pts, 6, rtm, 50)), 0L)
})

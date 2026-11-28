## ignitionSource = "observedEscapes": a hindcast spreads the year's observed escapes instead of drawing
## ignitions and escapes from the predicted surfaces, so it tests spread alone. Toy landscape of helper-toy.R:
## pixels of 6.25 ha, cell 1 in the west block, cell 10 in the east block, spread probability 1.

## year 1: a 100 ha fire in the west block (escaped) and a 10 ha fire in the east (did not); year 2: 100 ha in the east
obsPolys <- function() toyFirePolys(c(1L, 6L, 56L), c(1L, 1L, 2L), c(100, 10, 100), side = 3L)

## the starts of the spread fit: fireSenseUtils::escapeFireSet(), one start per escape polygon
obsStarts <- function(polys = obsPolys()) {
  st <- fireSenseUtils::escapeFireSet(polys, toyFlammable())
  data.table::data.table(YEAR = as.integer(st$YEAR), pixelID = as.integer(st$pixelID))
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
  got <- observedEscapeStarts(polys, toyFlammable(), fireSenseUtils::escapeDefinition(50, c("natural", "unknown")))
  expect_identical(got$pixelID, as.integer(st$pixelID))
  expect_identical(got$YEAR, as.integer(st$YEAR))
  expect_identical(nrow(got), 2L)                    # the 10 ha fire is not an escape
  ## a smaller escape size takes it in
  expect_identical(nrow(observedEscapeStarts(polys, toyFlammable(), fireSenseUtils::escapeDefinition(5, c("natural", "unknown")))), 3L)
  expect_identical(observedEscapes(got, 2), data.table::data.table(pixelID = got$pixelID[got$YEAR == 2L], escaped = TRUE))
  expect_identical(nrow(observedEscapes(got, 3)), 0L)
})

## observedStartLocation = "ignitionPoint": each escape starts at its NFDB ignition point (snapped to a burnable pixel
## of the fire), not at the snapped centroid of its polygon
toyPoints <- function(cells, years, sizesHa, rtm = toyRTM()) {
  p <- terra::vect(terra::xyFromCell(rtm, cells), crs = terra::crs(rtm))
  p$YEAR <- as.integer(years)
  p$SIZE_HA <- sizesHa
  p$CAUSE <- "N"
  p
}
obsDef <- function() fireSenseUtils::escapeDefinition(50, c("natural", "unknown"))

test_that("ignitionPoint starts each escape at the pixel of its point; the centroid is the default", {
  ## the year-1 fire's point is its corner (cell 1), not its centroid (cell 12); year 2 has no point in its fire
  pts <- toyPoints(1L, 1L, 100)
  got <- observedEscapeStarts(obsPolys(), toyFlammable(), obsDef(), points = pts)
  cen <- observedEscapeStarts(obsPolys(), toyFlammable(), obsDef())
  expect_identical(got$pixelID[got$YEAR == 1L], 1L)
  expect_false(identical(got$pixelID[got$YEAR == 1L], cen$pixelID[cen$YEAR == 1L]))
  expect_identical(cen$pixelID[cen$YEAR == 1L], 12L)
  expect_identical(got$YEAR, cen$YEAR)
})

test_that("an escape without a matched point starts at its centroid, with a message", {
  pts <- toyPoints(1L, 1L, 100)
  expect_message(got <- observedEscapeStarts(obsPolys(), toyFlammable(), obsDef(), points = pts),
                 "1 of 2 observed escapes.*centroid")
  cen <- observedEscapeStarts(obsPolys(), toyFlammable(), obsDef())
  expect_identical(got$pixelID[got$YEAR == 2L], cen$pixelID[cen$YEAR == 2L])
  ## all matched: no message
  pts2 <- toyPoints(c(1L, 56L), c(1L, 2L), c(100, 100))
  expect_no_message(observedEscapeStarts(obsPolys(), toyFlammable(), obsDef(), points = pts2))
})

test_that("a point on a non-burnable pixel is moved to the nearest burnable pixel of the fire", {
  ## fire of cells 3:5 x rows 1:3 covers the barrier (column 5); its point is on the barrier, cell 5
  polys <- toyFirePolys(3L, 1L, 100, side = 3L)
  got <- observedEscapeStarts(polys, toyFlammable(), obsDef(), points = toyPoints(5L, 1L, 100))
  expect_identical(got$pixelID, 4L)
})

test_that("the point of the larger fire of a year is not taken by another fire", {
  ## two fires of year 1: each takes the point in it
  polys <- toyFirePolys(c(1L, 56L), c(1L, 1L), c(100, 100), side = 3L)
  got <- observedEscapeStarts(polys, toyFlammable(), obsDef(), points = toyPoints(c(1L, 58L), c(1L, 1L), c(100, 100)))
  expect_setequal(got$pixelID, c(1L, 58L))
})

test_that("with ignitionPoint the module spreads from the point's pixel; the default is unchanged", {
  run <- function(params) {
    sim <- runFireSense(NULL, params = c(list(ignitionSource = "observedEscapes"), params), doSpades = FALSE,
                        objects = c(predictedSurfaces(), list(firePolys = obsPolys(),
                                                              ignitionFirePoints = toyPoints(1L, 1L, 100))))
    suppressMessages(SpaDES.core::spades(sim, debug = FALSE))
  }
  expect_identical(run(list(observedStartLocation = "ignitionPoint"))$ignitionsAndEscapes$pixelID, 1L)
  expect_identical(run(list())$ignitionsAndEscapes$pixelID, 12L)
  expect_identical(run(list(observedStartLocation = "centroid"))$ignitionsAndEscapes$pixelID, 12L)
  expect_error(runFireSense(NULL, params = list(ignitionSource = "observedEscapes", observedStartLocation = "ignitionPoint"),
                            objects = c(predictedSurfaces(), list(firePolys = obsPolys()))), "ignitionFirePoints")
  expect_error(runFireSense(NULL, params = list(observedStartLocation = "centre")), "observedStartLocation")
})

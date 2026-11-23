## ignitionSource = "observedPolygons": the year's observed fires burn as they are (attribution runs); nothing is
## drawn or spread. Toy landscape of helper-toy.R: 10 x 10 pixels, the barrier is column 5 (not burnable).

## the cells of a `side` x `side` square whose upper-left cell is `cell`, in the toy landscape
boxCells <- function(cell, side = 3L) {
  r0 <- (cell - 1L) %/% 10L; c0 <- (cell - 1L) %% 10L
  as.integer(unlist(lapply(0:(side - 1L), function(i) r0 * 10L + i * 10L + c0 + seq_len(side))))
}

## year 1: A natural at cell 1 (9 pixels), B natural at cell 34 over the barrier (9 pixels, 6 burnable),
## C a prescribed burn of natural cause, D of human cause. Year 2: E natural at cell 47.
polysPerYear <- function() {
  toyFirePolys(c(1L, 34L, 77L, 71L, 47L), years = c(1L, 1L, 1L, 1L, 2L), sizesHa = rep(100, 5), side = 3L,
               causes = c("Natural", "Natural", "Natural", "Human", "Natural"),
               prescribed = c(NA, NA, "true", NA, NA))
}

## year 1's two natural fires, without the barrier
year1Burn <- function() setdiff(c(boxCells(1L), boxCells(34L)), barrierCells())

runPolygons <- function(times = list(start = 1, end = 1), polys = polysPerYear(), params = list()) {
  set.seed(1)
  runFireSense(NULL, times = times, params = c(list(ignitionSource = "observedPolygons"), params),
               objects = list(firePolys = polys, fireSense_SpreadPredicted = NULL))
}

test_that("observedPolygons burns exactly the burnable pixels of the year's modelled fires", {
  withr::local_options(list(spades.moduleCodeChecks = FALSE))
  testthat::local_mocked_bindings(spreadCpp = function(...) stop("spreadCpp called"), .package = "SpaDES.tools")
  sim <- runPolygons()
  ## A (9 pixels) and B (6 of its 9: the barrier is not burnable); the prescribed and the human fire do not burn
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), sort(year1Burn()))
  expect_false(any(barrierCells() %in% which(vals(sim$rstCurrentBurn) == 1)))
  ## the outputs the other modes set
  expect_identical(which(!is.na(vals(sim$rstAnnualBurnID))), sort(year1Burn()))
  ids <- vals(sim$rstAnnualBurnID)
  expect_identical(sort(unique(ids[!is.na(ids)])), c(1, 2))
  expect_identical(which(vals(sim$burnMap) == 1), sort(year1Burn()))
  expect_identical(nrow(sim$burnSummary), 2L)
  expect_identical(sort(sim$burnSummary$N), c(6L, 9L))
  expect_equal(sort(sim$burnSummary$areaBurnedHa), c(6, 9) * 6.25)
  expect_identical(sort(sim$burnDT$pixels), sort(year1Burn()))
})

test_that("observedPolygons burns only the year's polygons, and nothing in a year without any", {
  sim <- runPolygons(list(start = 2, end = 2))
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), sort(boxCells(47L)))
  sim <- runPolygons(list(start = 3, end = 3))
  expect_true(all(is.na(vals(sim$rstCurrentBurn))))
  expect_true(all(is.na(vals(sim$rstAnnualBurnID))))
})

test_that("observedPolygons resets rstCurrentBurn every year and adds up burnMap", {
  sim <- runPolygons(list(start = 1, end = 2))
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), sort(boxCells(47L)))
  expect_identical(sum(vals(sim$burnMap), na.rm = TRUE), length(year1Burn()) + 9)
})

test_that("observedPolygons needs no ignition or spread inputs, and fireCauses picks the causes", {
  ## no ignition surfaces, no spread surfaces (runPolygons gives none): the run works. Human fires burn when asked
  sim <- runPolygons(params = list(fireCauses = c("natural", "human")))
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), sort(c(year1Burn(), boxCells(71L))))
})

test_that("observedPolygons needs firePolys", {
  expect_error(runFireSense(NULL, params = list(ignitionSource = "observedPolygons")), "firePolys")
})

test_that("a fire smaller than a pixel burns its one burnable pixel, as the fit counts it", {
  ## 0.2 x 0.2 pixels at the upper-left corner of cell 56 (east block): its centre is in no cell
  small <- toyFirePolys(56L, 1L, 1, side = 0.2)
  expect_true(all(is.na(vals(terra::rasterize(small[[1]], toyRTM()))))) # terra::rasterize() would drop it
  sim <- runPolygons(polys = small)
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), 56L)
  ## on the barrier (not burnable) it burns nothing
  sim <- runPolygons(polys = toyFirePolys(5L, 1L, 1, side = 0.2))
  expect_true(all(is.na(vals(sim$rstCurrentBurn))))
})

test_that("observedPolygons needs flammableRTM on the grid of rasterToMatch", {
  coarse <- toyFlammable(toyRTM(5L, 500))
  expect_error(runFireSense(NULL, params = list(ignitionSource = "observedPolygons"),
                            objects = list(firePolys = polysPerYear(), flammableRTM = coarse,
                                           fireSense_SpreadPredicted = NULL)),
               "same grid")
})

test_that("a firePolys list of NULLs burns nothing, and YEAR stored as text still matches", {
  sim <- runPolygons(polys = list(NULL, NULL))
  expect_true(all(is.na(vals(sim$rstCurrentBurn))))
  polys <- polysPerYear()
  polys[[1]]$YEAR <- as.character(polys[[1]]$YEAR)
  sim <- runPolygons(polys = polys)
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), sort(year1Burn()))
})

test_that("a fire's burnSummary row is the same observed or predicted: igLoc is its lowest cell, area N * pixel", {
  obs <- runPolygons(polys = toyFirePolys(1L, 1L, 250, side = 4L, causes = "Natural")) # the west block's 4 columns, rows 1-4
  pred <- runFireSense(data.table::data.table(pixelID = 1L, escapes = 1L, escaped = TRUE))
  expect_identical(names(obs$burnSummary), names(pred$burnSummary))
  expect_identical(obs$burnSummary$igLoc, 1L)
  expect_equal(obs$burnSummary$areaBurnedHa, 16 * 6.25)
  expect_equal(pred$burnSummary$areaBurnedHa, 40 * 6.25) # the predicted path's area is unchanged: N * pixel ha
  expect_equal(pred$burnSummary$areaBurnedHa, pred$burnSummary$N * 6.25)
})

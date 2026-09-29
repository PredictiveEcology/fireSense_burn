## burn(): with spread probability 1 inside a block and 0 on the barrier, spread2() is
## deterministic -- a fire burns its whole block and nothing else -- so every expected
## value below is derived by hand from the toy landscape in helper-toy.R.

## one row per ignition; `escaped` says whether it escaped (fireSense_IgnitionPredict >= 1.0.0.9003)
ig <- function(pixelID, escapes) data.table::data.table(pixelID = pixelID, escapes = escapes, escaped = escapes > 0)

test_that("one escaped fire burns exactly its own block", {
  sim <- runFireSense(ig(1L, 1L)) # cell 1 is in the west block (cols 1-4)
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), westCells())   # 40 cells
  expect_identical(sort(sim$burnDT$pixels), westCells())
  expect_identical(unique(sim$burnDT$initialPixels), 1L)
  ## nothing east of the barrier, and nothing on it
  expect_true(all(is.na(vals(sim$rstCurrentBurn)[c(barrierCells(), eastCells())])))
})

test_that("burnSummary, burnDT and the rasters agree with each other", {
  sim <- runFireSense(ig(c(1L, 10L), c(1L, 1L))) # cell 10 is in the east block (cols 6-10)
  bs <- sim$burnSummary
  expect_identical(names(bs), c("igLoc", "N", "year", "areaBurnedHa"))
  expect_identical(bs$igLoc, c(1L, 10L))
  expect_identical(bs$N, c(40L, 50L))                 # 4 cols x 10 rows; 5 cols x 10 rows
  expect_identical(as.numeric(bs$year), c(1, 1))
  expect_equal(bs$areaBurnedHa, c(250, 312.5))        # 40 * 6.25 ha; 50 * 6.25 ha

  ## the same numbers from the rasters and from burnDT
  expect_identical(sum(vals(sim$rstCurrentBurn) == 1, na.rm = TRUE), sum(bs$N))
  expect_identical(nrow(sim$burnDT), sum(bs$N))
  expect_equal(sum(bs$areaBurnedHa),
               sum(vals(sim$rstCurrentBurn) == 1, na.rm = TRUE) *
                 prod(terra::res(sim$rasterToMatch)) / 1e4)
  expect_identical(as.vector(table(sim$burnDT$initialPixels)), c(40L, 50L))
})

test_that("rstAnnualBurnID labels each fire with its fire_id", {
  sim <- runFireSense(ig(c(1L, 10L), c(1L, 1L)))
  id <- vals(sim$rstAnnualBurnID)
  expect_true(all(id[westCells()] == 1))  # fire_id is .GRP by initialPixels, in order of appearance
  expect_true(all(id[eastCells()] == 2))
  expect_true(all(is.na(id[barrierCells()])))
  expect_identical(sort(unique(sim$burnDT$fire_id)), 1:2)
  expect_identical(unique(sim$burnDT[initialPixels == 10L]$fire_id), 2L)
})

test_that("non-flammable pixels never burn and stay NA in burnMap", {
  sim <- runFireSense(ig(c(1L, 10L), c(1L, 1L)))
  expect_false(any(barrierCells() %in% sim$burnDT$pixels))
  expect_true(all(is.na(vals(sim$burnMap)[barrierCells()])))
  expect_identical(vals(sim$burnMap)[-barrierCells()], rep(1, 90))
})

test_that("a barrier of NA spread probability also stops fire", {
  sim <- runFireSense(ig(1L, 1L),
                      objects = list(fireSense_SpreadPredicted = toySpreadProb(barrier = NA)))
  expect_identical(sort(sim$burnDT$pixels), westCells())
})

test_that("ignitions that did not escape do not burn", {
  ## cell 10 ignited but did not escape: only the west block burns
  sim <- runFireSense(ig(c(1L, 10L), c(1L, 0L)))
  expect_identical(sim$burnSummary$igLoc, 1L)
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), westCells())
  expect_identical(vals(sim$burnMap)[eastCells()], rep(0, 50))
})

test_that("no escapes at all leaves every output as init made it", {
  sim <- runFireSense(ig(c(1L, 10L), c(0L, 0L)))
  expect_null(sim$burnSummary)
  expect_null(sim$burnDT)
  ## this year's burn rasters exist and are empty (geometry only), so nothing reads a previous year's burn
  expect_false(terra::hasValues(sim$rstAnnualBurnID))
  expect_false(terra::hasValues(sim$rstCurrentBurn))
  expect_identical(sum(vals(sim$burnMap), na.rm = TRUE), 0)
})

test_that("an empty or all-NA ignitions table burns nothing", {
  empty <- runFireSense(ig(integer(), integer()))
  expect_null(empty$burnSummary)
  expect_identical(sum(vals(empty$burnMap), na.rm = TRUE), 0)

  allNA <- runFireSense(ig(1L, NA_integer_)) # sum(..., na.rm = TRUE) is 0
  expect_null(allNA$burnSummary)
})

test_that("nothing spreads unless whichModulesToPrepare includes fireSense_SpreadPredict", {
  sim <- runFireSense(ig(1L, 1L),
                      params = list(whichModulesToPrepare = "fireSense_IgnitionPredict"))
  expect_null(sim$burnSummary)
  expect_identical(sum(vals(sim$burnMap), na.rm = TRUE), 0)
})

test_that("zero spread probability burns only the ignition pixel", {
  sim <- runFireSense(ig(c(12L, 78L), c(1L, 1L)),
                      objects = list(fireSense_SpreadPredicted = toySpreadProb(p = 0)))
  expect_identical(sort(sim$burnDT$pixels), c(12L, 78L))
  expect_identical(sim$burnSummary$N, c(1L, 1L))
  expect_equal(sim$burnSummary$areaBurnedHa, c(6.25, 6.25))   # 1 pixel = 250 * 250 / 1e4 ha
})

test_that("fire spreads in 8 directions", {
  ## probability 1 only on the main diagonal: the 10 diagonal cells touch only at corners,
  ## so all 10 burn with 8 neighbours and only the ignition cell would with 4
  rtm <- toyRTM()
  sp <- rtm
  terra::values(sp) <- 0
  diagCells <- terra::cellFromRowCol(rtm, 1:10, 1:10)
  sp[diagCells] <- 1
  flam <- rtm # all flammable
  sim <- runFireSense(ig(diagCells[1], 1L),
                      objects = list(fireSense_SpreadPredicted = sp, flammableRTM = flam))
  expect_identical(sort(sim$burnDT$pixels), as.integer(diagCells))
  expect_equal(sim$burnSummary$areaBurnedHa, 62.5)            # 10 * 6.25 ha
})

test_that("two fires in one block share it without overlap", {
  sim <- runFireSense(ig(c(1L, 94L), c(1L, 1L))) # cells 1 and 94 are both west (cols 1 and 4)
  expect_identical(sort(sim$burnDT$pixels), westCells())      # each pixel burns once
  expect_identical(sum(sim$burnSummary$N), 40L)
  expect_true(all(sim$burnSummary$N >= 1L))
  expect_setequal(sim$burnSummary$igLoc, c(1L, 94L))
  ## a pixel belongs to the fire recorded in rstAnnualBurnID
  expect_identical(vals(sim$rstAnnualBurnID)[sim$burnDT$pixels], as.numeric(sim$burnDT$fire_id))
})

test_that("two escapes on one pixel burn the block once", {
  ## several escapes on one pixel are one fire: the first start burns the pixel, the others cannot
  sim <- runFireSense(ig(1L, 2L))
  expect_identical(sort(sim$burnDT$pixels), westCells())
  expect_identical(sim$burnSummary$N, 40L)
  expect_identical(vals(sim$burnMap)[westCells()], rep(1, 40)) # not 2
})

test_that("burnMap and burnSummary accumulate over years", {
  sim <- runFireSense(ig(1L, 1L), times = list(start = 1, end = 3))
  bm <- vals(sim$burnMap)
  expect_identical(bm[westCells()], rep(3, 40))                # burned in years 1, 2, 3
  expect_identical(bm[eastCells()], rep(0, 50))
  expect_identical(as.numeric(sim$burnSummary$year), c(1, 2, 3))
  expect_identical(sim$burnSummary$N, rep(40L, 3))
  expect_equal(sum(sim$burnSummary$areaBurnedHa), 750)         # 3 * 40 * 6.25 ha
  expect_identical(nrow(sim$burnDT), 40L)                      # burnDT holds the last year only
})

test_that("the pixel size sets the area burned", {
  rtm <- toyRTM(res = 100) # 100 * 100 / 1e4 = 1 ha per pixel
  ## At 1 ha per pixel the 50-ha escape size is more than the 40-cell block, so a fire stuck in the
  ## block would jump the barrier; this test is about pixel size, so jumping is off.
  sim <- runFireSense(ig(1L, 1L), params = list(jumpTries = 0L),
                      objects = list(rasterToMatch = rtm, flammableRTM = toyFlammable(rtm),
                                     fireSense_SpreadPredicted = toySpreadProb(rtm)))
  expect_equal(sim$burnSummary$areaBurnedHa, 40)
})

test_that("stochastic spread is reproducible and stays within the rules", {
  run <- function() {
    set.seed(4321)
    runFireSense(ig(c(1L, 10L), c(1L, 1L)),
                 objects = list(fireSense_SpreadPredicted = toySpreadProb(p = 0.3)))
  }
  a <- run()
  b <- run()
  expect_identical(a$burnDT$pixels, b$burnDT$pixels)
  expect_identical(a$burnSummary, b$burnSummary)
  ## a fire never leaves its block, never burns the barrier, always burns its ignition pixel
  expect_true(all(a$burnDT[initialPixels == 1L]$pixels %in% westCells()))
  expect_true(all(a$burnDT[initialPixels == 10L]$pixels %in% eastCells()))
  expect_true(all(c(1L, 10L) %in% a$burnDT$pixels))
  expect_identical(anyDuplicated(a$burnDT$pixels), 0L)
  expect_lt(nrow(a$burnDT), 90L) # p = 0.3 is far below the ~0.5 needed to fill a block
})

test_that("three or more escapes on one pixel burn the block once (spread2 used to stop here)", {
  sim <- runFireSense(ig(1L, 3L))
  expect_identical(sort(sim$burnDT$pixels), westCells())
  expect_identical(sim$burnSummary$N, 40L)
})

## ---- the per-year random effect (yearSpreadSD in the fit) ----

test_that("without a random effect the spread probability is used as it is", {
  sp <- toySpreadProb(p = 0.3)
  p <- as.vector(terra::values(sp))
  expect_identical(yearSpreadProb(sp, NULL), p)
  expect_identical(yearSpreadProb(sp, 0), p)
  expect_identical(yearSpreadProb(sp, toySpreadProb(p = 0)), p)   # an sd raster of 0
})

test_that("one draw per year shifts every pixel's logit spread probability by the same amount", {
  sp <- toySpreadProb(p = 0.3, barrier = 0.1)
  set.seed(11)
  q <- yearSpreadProb(sp, 0.8)
  shift <- stats::qlogis(q) - stats::qlogis(as.vector(terra::values(sp)))
  expect_equal(max(shift) - min(shift), 0, tolerance = 1e-9)       # same for every pixel: one year, one eps
  set.seed(11)
  expect_equal(shift[1], 0.8 * stats::rnorm(1))                    # eps = z * sd
})

test_that("an sd raster scales the year's shared draw per pixel (several ELFs)", {
  sp <- toySpreadProb(p = 0.3, barrier = 0.3)
  sdR <- sp
  terra::values(sdR) <- 0
  sdR[eastCells()] <- 1                                            # west: sd 0, east: sd 1
  set.seed(5)
  q <- yearSpreadProb(sp, sdR)
  shift <- stats::qlogis(q) - stats::qlogis(0.3)
  expect_equal(shift[westCells()], rep(0, 40))
  expect_equal(shift[eastCells()], rep(shift[eastCells()][1], 50))
  expect_false(isTRUE(all.equal(shift[eastCells()][1], 0)))
})

test_that("the year effect changes how much burns, and all fires in a year share it", {
  burned <- function(seed, sd) {
    set.seed(seed)
    s <- runFireSense(ig(c(1L, 10L), c(1L, 1L)),
                      objects = list(fireSense_SpreadPredicted = toySpreadProb(p = 0.3),
                                     fireSense_SpreadSD = sd))
    s$burnSummary$N
  }
  noEffect <- sapply(1:20, burned, sd = 0)
  withEffect <- sapply(1:20, burned, sd = 3)
  ## a large sd makes some years burn whole blocks and others almost nothing
  expect_gt(stats::var(colSums(withEffect)), stats::var(colSums(noEffect)))
  ## the two fires of a year move together: their sizes correlate across years
  expect_gt(stats::cor(withEffect[1, ], withEffect[2, ]), 0.5)
})

## rstCurrentBurn is this year's burn: CBM_dataPrep reads it every year as disturbance events
## (disturbanceMeta$sourceObjectName), so a year without fire must leave nothing burned in it.
test_that("a year without fire leaves no burn in rstCurrentBurn or rstAnnualBurnID", {
  noFire <- list(noIgnitions = ig(integer(0), integer(0)),         # burn() returns at its first check
                 noEscapes   = ig(1L, 0L))                          # no escape, no small-fire sizes
  for (nm in names(noFire)) {
    sim <- runFireSense(ig(1L, 1L), times = list(start = 1, end = 1), doSpades = FALSE)
    sim <- suppressMessages(SpaDES.core::spades(sim, debug = FALSE))
    expect_true(any(vals(sim$rstCurrentBurn) == 1, na.rm = TRUE), label = paste(nm, "year 1 burned"))
    burnMap1 <- vals(sim$burnMap)
    sim$ignitionsAndEscapes <- noFire[[nm]]
    SpaDES.core::end(sim) <- 2
    grDevices::pdf(NULL)
    sim <- suppressMessages(SpaDES.core::spades(sim, debug = FALSE))
    grDevices::dev.off()
    expect_false(any(vals(sim$rstCurrentBurn) == 1, na.rm = TRUE), label = paste(nm, "rstCurrentBurn after a no-fire year"))
    expect_true(all(is.na(vals(sim$rstAnnualBurnID))), label = paste(nm, "rstAnnualBurnID after a no-fire year"))
    expect_identical(vals(sim$burnMap), burnMap1, label = paste(nm, "burnMap unchanged by a no-fire year"))
  }
})

test_that("a year whose ignitions do not escape burns only its own small fires, not last year's", {
  ## 6.25 ha = 1 pixel exactly, so the ignition that did not escape burns its own pixel only
  sim <- runFireSense(ig(1L, 1L), objects = list(nonEscapedFireSizesHa = 6.25))
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), westCells())
  sim$ignitionsAndEscapes <- ig(10L, 0L) # east block, did not escape
  SpaDES.core::end(sim) <- 2
  grDevices::pdf(NULL)
  sim <- suppressMessages(SpaDES.core::spades(sim, debug = FALSE))
  grDevices::dev.off()
  expect_identical(which(vals(sim$rstCurrentBurn) == 1), 10L)
  expect_identical(which(!is.na(vals(sim$rstAnnualBurnID))), 10L)
  expect_identical(vals(sim$burnMap)[c(westCells(), 10L)], rep(1, 41)) # year 1's block, year 2's pixel
  expect_identical(sim$burnSummary[year == 2]$igLoc, 10L)
})

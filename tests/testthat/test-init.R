## The `init` event: burnMap, rstCurrentBurn, the first scheduled burn, and the early stop.

noFire <- data.table::data.table(pixelID = 1L, escapes = 0L, escaped = FALSE)

test_that("init makes burnMap 0 where flammable and NA on the barrier", {
  sim <- runFireSense(noFire, params = list(.runInitialTime = 99)) # no burn within 1..1
  bm <- vals(sim$burnMap)
  expect_identical(which(is.na(bm)), barrierCells())        # 10 barrier cells, col 5
  expect_identical(bm[-barrierCells()], rep(0, 90))          # 100 - 10 flammable cells
  expect_true(terra::compareGeom(sim$burnMap, sim$rasterToMatch))
})

test_that("init makes an empty rstCurrentBurn on the rasterToMatch grid", {
  sim <- runFireSense(noFire, params = list(.runInitialTime = 99))
  expect_false(terra::hasValues(sim$rstCurrentBurn)) # rast(rasterToMatch): geometry only
  expect_true(terra::compareGeom(sim$rstCurrentBurn, sim$rasterToMatch))
})

test_that("init schedules the first burn at .runInitialTime with priority 5.13", {
  sim <- runFireSense(noFire, times = list(start = 1, end = 10),
                      params = list(.runInitialTime = 4), doSpades = FALSE)
  sim <- suppressMessages(SpaDES.core::spades(sim, debug = FALSE,
                                              events = list(fireSense_burn = "init")))
  ev <- SpaDES.core::events(sim)
  ev <- ev[ev$moduleName == "fireSense_burn", ]
  expect_identical(nrow(ev), 1L)
  expect_identical(ev$eventType, "burn")
  expect_identical(as.numeric(ev$eventTime), 4)
  expect_identical(ev$eventPriority, 5.13)
})

test_that("init stops when the spread probability raster has no values", {
  allNA <- toySpreadProb()
  terra::values(allNA) <- NA_real_
  expect_error(
    runFireSense(noFire, objects = list(fireSense_SpreadPredicted = allNA)),
    "length\\(na.omit\\(sim\\$fireSense_SpreadPredicted\\[\\]\\)\\) > 0"
  )
})

test_that("init does not need fireSense_SpreadPredicted to exist yet", {
  ## SpreadPredict normally creates it later in the same year; init must not fail without it
  sim <- runFireSense(noFire, params = list(.runInitialTime = 99),
                      objects = list(fireSense_SpreadPredicted = NULL))
  expect_null(sim$fireSense_SpreadPredicted)
  expect_identical(sum(vals(sim$burnMap) == 0, na.rm = TRUE), 90L)
})

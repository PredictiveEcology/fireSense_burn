## Ignitions and escapes are drawn here, from the surfaces fireSense_ignitionPredict predicts.
## Toy: the 10 x 10 fine grid of helper-toy.R (column 5 not flammable) over a 2 x 2 coarse grid, so each coarse
## pixel holds 25 fine pixels (the two coarse pixels that contain column 5 have 20 flammable).

toyCoarseRTM <- function() {
  terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2500, ymin = 0, ymax = 2500, crs = "EPSG:3005", vals = 1)
}

## `igMean`, `escMean`: expected counts for coarse cells 1..4
toyProbRas <- function(igMean, escMean = igMean) {
  r <- c(toyCoarseRTM(), toyCoarseRTM())
  terra::values(r) <- cbind(igMean, escMean)
  names(r) <- c("ignitionProb", "escapeProb")
  r
}

toyDrawSim <- function(igMean, escMean = igMean, dist = list(ignition = "count:poisson", escape = "count:poisson")) {
  list(fireSense_IgAndEscapeProbRas = toyProbRas(igMean, escMean),
       fireSense_IgAndEscapeDistribution = dist,
       ignitionFitRTM = toyCoarseRTM(), flammableRTM = toyFlammable())
}

draw <- function(sim) drawIgnitionsAndEscapes(sim, store = new.env())

## coarse cell of a fine cell of the 10 x 10 grid, 2 x 2 coarse
coarseOf <- function(cell) {
  row <- (cell - 1) %/% 10 + 1
  col <- (cell - 1) %% 10 + 1
  (row > 5) * 2 + (col > 5) + 1
}

test_that("ignitions per coarse pixel are Poisson draws with the ignitionProb mean", {
  set.seed(1)
  n <- 400
  counts <- replicate(n, {
    ig <- draw(toyDrawSim(c(1, 1, 1, 1)))
    c(total = nrow(ig), first = sum(coarseOf(ig$pixelID) == 1))
  })
  ## 4 coarse pixels with mean 1: total ~ Poisson(4), first ~ Poisson(1)
  expect_equal(mean(counts["total", ]), 4, tolerance = 0.06)
  expect_equal(mean(counts["first", ]), 1, tolerance = 0.12)
  expect_equal(stats::var(counts["first", ]), 1, tolerance = 0.25)   # a Poisson has variance = mean
})

test_that("a pixel with mean 0 or NA has no ignitions; the others do", {
  set.seed(2)
  ig <- do.call(rbind, replicate(50, as.data.frame(draw(toyDrawSim(c(0, 1, NA, 1)))), simplify = FALSE))
  expect_true(all(coarseOf(ig$pixelID) %in% c(2, 4)))
  expect_gt(nrow(ig), 0)
})

test_that("escapes are drawn from the escapeProb mean and never exceed the ignitions", {
  set.seed(3)
  for (i in 1:30) {
    ig <- as.data.frame(draw(toyDrawSim(c(1, 1, 1, 1), escMean = 50)))   # the cap binds
    expect_identical(ig$escapes, ig$ignitions)
    ig <- as.data.frame(draw(toyDrawSim(c(1, 1, 1, 1), escMean = 0.5)))
    expect_true(all(ig$escapes <= ig$ignitions))
  }
  ## below the cap the escapes are Poisson: mean 0.1 escapes per ignited pixel, far fewer than ignitions
  set.seed(4)
  ig <- do.call(rbind, replicate(100, as.data.frame(draw(toyDrawSim(c(1, 1, 1, 1), escMean = 0.1))), simplify = FALSE))
  expect_lt(sum(ig$escaped) / nrow(ig), 0.2)
})

test_that("an escape mean of 0 gives no escapes, whatever the ignitions", {
  ## mean 0 for escapes: no escapes, whatever the ignitions
  set.seed(5)
  ig <- as.data.frame(draw(toyDrawSim(c(2, 2, 2, 2), escMean = 0)))
  expect_gt(nrow(ig), 0)
  expect_identical(ig$escapes, rep(0L, nrow(ig)))
  expect_false(any(ig$escaped))
})

test_that("exactly `escapes` of each coarse pixel's ignitions escaped", {
  set.seed(6)
  for (i in 1:20) {
    ig <- as.data.frame(draw(toyDrawSim(c(1.5, 1.5, 1.5, 1.5), escMean = 0.8)))
    if (!nrow(ig)) next
    per <- tapply(ig$escaped, coarseOf(ig$pixelID), sum)
    esc <- tapply(ig$escapes, coarseOf(ig$pixelID), `[`, 1)
    expect_identical(as.integer(per), as.integer(esc))
  }
})

test_that("each ignition is a distinct flammable fine pixel inside its own coarse pixel", {
  set.seed(7)
  ig <- as.data.frame(draw(toyDrawSim(c(2, 0, 2, 0))))
  expect_identical(names(ig), c("pixelID", "igProb", "ignitions", "escapeProb", "escapes", "escaped"))
  expect_false(anyDuplicated(ig$pixelID) > 0)
  expect_false(any(barrierCells() %in% ig$pixelID))
  expect_true(all(coarseOf(ig$pixelID) %in% c(1, 3)))
  expect_identical(as.vector(table(coarseOf(ig$pixelID))[as.character(coarseOf(ig$pixelID))]), as.integer(ig$ignitions))
})

test_that("a year with no ignitions has the columns and types of a year with ignitions", {
  set.seed(8)
  normal <- draw(toyDrawSim(c(1, 1, 1, 1)))
  none <- draw(toyDrawSim(c(0, 0, 0, 0)))
  expect_gt(nrow(normal), 0)
  expect_identical(nrow(none), 0L)
  expect_identical(names(none), names(normal))
  expect_identical(vapply(none, typeof, ""), vapply(normal, typeof, ""))
  expect_identical(none$escaped, logical(0))
})

test_that("an objective other than count:poisson stops, naming it", {
  expect_error(draw(toyDrawSim(c(1, 1, 1, 1), dist = list(ignition = "reg:tweedie", escape = "count:poisson"))),
               "cannot draw ignitions from objective 'reg:tweedie'")
  expect_error(draw(toyDrawSim(c(1, 1, 1, 1), dist = list(ignition = "count:poisson", escape = "reg:tweedie"))),
               "cannot draw escapes from objective 'reg:tweedie'")
})

test_that("a missing distribution stops", {
  sim <- toyDrawSim(c(1, 1, 1, 1)); sim$fireSense_IgAndEscapeDistribution <- NULL
  expect_error(draw(sim), "fireSense_IgAndEscapeDistribution")
})

test_that("the burn event draws each year from the surfaces and keeps the ignitionsAndEscapes columns", {
  sim <- runFireSense(NULL, times = list(start = 1, end = 3), params = list(.plotInterval = 99),
                      objects = list(fireSense_IgAndEscapeProbRas = toyProbRas(c(1, 1, 1, 1), 0.5),
                                     fireSense_IgAndEscapeDistribution = list(ignition = "count:poisson",
                                                                              escape = "count:poisson"),
                                     ignitionFitRTM = toyCoarseRTM()))
  ig <- sim$ignitionsAndEscapes
  expect_identical(names(ig), c("pixelID", "igProb", "ignitions", "escapeProb", "escapes", "escaped"))
  expect_true(all(sim$burnSummary$year %in% 1:3))
})

test_that("a burn event with a surface but an unsupported objective stops", {
  expect_error(
    runFireSense(NULL, objects = list(fireSense_IgAndEscapeProbRas = toyProbRas(c(1, 1, 1, 1)),
                                      fireSense_IgAndEscapeDistribution = list(ignition = "reg:tweedie",
                                                                               escape = "count:poisson"),
                                      ignitionFitRTM = toyCoarseRTM())),
    "reg:tweedie")
})

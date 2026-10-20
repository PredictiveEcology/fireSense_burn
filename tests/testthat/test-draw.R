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

test_that("the objective drawn from is fireSenseUtils::ignitionObjectiveTxt, not a copy", {
  testthat::local_mocked_bindings(ignitionObjectiveTxt = "reg:tweedie", .package = "fireSenseUtils")
  expect_length(drawCounts("reg:tweedie", c(1, 2), "ignition"), 2)
  expect_error(drawCounts("count:poisson", c(1, 2), "ignition"), "only 'reg:tweedie' is supported")
})

## ---- the year effect on ignitions and escapes: one z per year, shared with spread ----

## `toyProbRas()` plus the two sd layers fireSense_ignitionPredict adds when the fits have a year effect
toyProbRasSD <- function(igMean, escMean = igMean, igSD = 0, escSD = 0) {
  r <- toyProbRas(igMean, escMean)
  sdR <- c(toyCoarseRTM(), toyCoarseRTM())
  terra::values(sdR) <- cbind(rep_len(igSD, 4), rep_len(escSD, 4))
  r <- c(r, sdR)
  names(r) <- c("ignitionProb", "escapeProb", "ignitionYearSD", "escapeYearSD")
  r
}

toyDrawSimSD <- function(igMean, escMean = igMean, igSD = 0, escSD = 0) {
  s <- toyDrawSim(igMean, escMean)
  s$fireSense_IgAndEscapeProbRas <- toyProbRasSD(igMean, escMean, igSD, escSD)
  s
}

test_that("one z moves the ignition means, the escape means and the spread probability the same way", {
  s <- toyDrawSimSD(c(5, 5, 5, 5), escMean = 2, igSD = 0.5, escSD = 0.8)
  sp <- toySpreadProb(p = 0.3)
  for (z in c(1.5, -1.5)) {
    set.seed(1)
    ig <- drawIgnitionsAndEscapes(s, store = new.env(), z = z)
    ## the means drawn from are the surface times exp(sd * z - sd^2 / 2), the same multiplier for every pixel
    expect_equal(unique(ig$igProb), 5 * fireSenseUtils::yearEffectMultiplier(0.5, z))
    expect_equal(unique(ig$escapeProb), 2 * fireSenseUtils::yearEffectMultiplier(0.8, z))
    p <- yearSpreadProb(sp, 0.7, z = z)[westCells()]
    if (z > 0) {
      expect_true(all(ig$igProb > 5) && all(ig$escapeProb > 2) && all(p > 0.3))
    } else {
      expect_true(all(ig$igProb < 5) && all(ig$escapeProb < 2) && all(p < 0.3))
    }
  }
  ## yearZ() draws z only when an sd layer is above 0
  expect_null(yearZ(toyProbRas(c(1, 1, 1, 1))))
  expect_null(yearZ(toyProbRasSD(c(1, 1, 1, 1), igSD = 0, escSD = 0)))
  set.seed(2); z <- yearZ(toyProbRasSD(c(1, 1, 1, 1), igSD = 0, escSD = 0.3))
  set.seed(2); expect_identical(z, stats::rnorm(1))
})

test_that("an sd of 0, or no sd layer, reproduces the draws without a year effect exactly", {
  for (seed in 1:5) {
    set.seed(seed); a <- draw(toyDrawSim(c(2, 2, 2, 2), escMean = 0.5))
    set.seed(seed); b <- draw(toyDrawSimSD(c(2, 2, 2, 2), escMean = 0.5))                 # sd layers of 0
    set.seed(seed); d <- drawIgnitionsAndEscapes(toyDrawSimSD(c(2, 2, 2, 2), escMean = 0.5),
                                                 store = new.env(), z = 1.7)                # a z with sd 0
    expect_identical(a, b)
    expect_identical(a, d)
  }
  ## and in the burn event, with spread's own year effect: its z is drawn where it always was
  burnWith <- function(seed, ras) {
    set.seed(seed)
    s <- runFireSense(NULL, times = list(start = 1, end = 4), params = list(.plotInterval = 99),
                      objects = list(fireSense_IgAndEscapeProbRas = ras,
                                     fireSense_IgAndEscapeDistribution = list(ignition = "count:poisson",
                                                                              escape = "count:poisson"),
                                     ignitionFitRTM = toyCoarseRTM(),
                                     fireSense_SpreadPredicted = toySpreadProb(p = 0.3), fireSense_SpreadSD = 0.8))
    list(s$burnSummary, s$ignitionsAndEscapes)
  }
  expect_identical(burnWith(3, toyProbRas(c(2, 2, 2, 2), 1)), burnWith(3, toyProbRasSD(c(2, 2, 2, 2), 1)))
})

test_that("the year effect keeps the mean ignitions and escapes over many years", {
  set.seed(9)
  n <- 600
  ## small means: a coarse pixel has only 20-25 flammable fine pixels to place its ignitions on
  counts <- replicate(n, {
    s <- toyDrawSimSD(c(2, 2, 2, 2), escMean = 0.2, igSD = 0.5, escSD = 0.5)
    ig <- drawIgnitionsAndEscapes(s, store = new.env(), z = stats::rnorm(1))
    c(ignitions = nrow(ig), escapes = sum(ig$escaped), ignitedPixels = length(unique(coarseOf(ig$pixelID))))
  })
  expect_equal(mean(counts["ignitions", ]), 8, tolerance = 0.1)                        # 4 pixels x 2
  ## 0.2 expected escapes per ignited pixel (the cap at the ignitions seldom binds)
  expect_equal(sum(counts["escapes", ]) / sum(counts["ignitedPixels", ]), 0.2, tolerance = 0.15)
  ## but the years differ more than Poisson years would (variance = mean): 8 + 64 * (exp(0.25) - 1) = 26
  expect_gt(stats::var(counts["ignitions", ]), 2 * 8)
})

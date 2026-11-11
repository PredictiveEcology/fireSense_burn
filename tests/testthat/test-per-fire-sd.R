## A per-fire random effect (fireSense_SpreadFireSD above 0): each fire spreads with its own offset on the linear
## predictor, in SpaDES.tools::spreadCpp(link = "powerLaw"). Without it (0 or absent) the spread is that of earlier
## versions. Toy landscape of helper-toy.R: east block cols 6-10 (50 pixels, 6.25 ha each).

toyLinked <- function(x = 0, pars = c(pc = 0.5, gamma = 1, floor = 0.2, shape = 1)) {
  rtm <- toyRTM()
  lin <- rtm; terra::values(lin) <- x
  lin[barrierCells(rtm)] <- NA
  sp <- lin; terra::values(sp) <- fireSenseUtils::powerLawLink(vals(lin), pars[["pc"]], pars[["gamma"]], pars[["floor"]],
                                                              pars[["shape"]])
  list(sp = sp, lin = lin, pars = pars)
}

## 300 years, each one fire from cell 6, no year effect: the sizes of the fires
fireSizes <- function(fireSD, years = 300L) {
  t <- toyLinked()
  objs <- list(fireSense_SpreadPredicted = t$sp, fireSense_SpreadLinear = t$lin, fireSense_SpreadPowerLaw = t$pars,
               fireSense_SpreadFireSD = fireSD)
  ig <- data.table::data.table(pixelID = 6L, escapes = 1L, escaped = TRUE)
  set.seed(11)
  sim <- runFireSense(ig, times = list(start = 1, end = years), params = list(.plotInterval = 1e6, escapeSizeHa = NA),
                      objects = objs)
  sim$burnSummary$N
}

test_that("a per-fire effect widens the spread of fire sizes", {
  n0 <- fireSizes(0)
  n1 <- fireSizes(1.5)
  expect_length(n0, 300L)
  expect_gt(stats::sd(n1), 1.3 * stats::sd(n0))
})

test_that("a per-fire sd of 0 or absent is today's spread, same random numbers", {
  expect_identical(fireSizes(0), fireSizes(NULL))
  expect_identical(fireSizes(toySpreadProb(p = 0)), fireSizes(NULL))           # an sd raster of 0
})

test_that("a per-fire effect without a power-law fit, or without x, stops", {
  t <- toyLinked()
  ig <- data.table::data.table(pixelID = 6L, escapes = 1L, escaped = TRUE)
  expect_error(runFireSense(ig, objects = list(fireSense_SpreadPredicted = t$sp, fireSense_SpreadFireSD = 1)),
               "fireSense_SpreadPowerLaw")
  expect_error(runFireSense(ig, objects = list(fireSense_SpreadPredicted = t$sp, fireSense_SpreadFireSD = 1,
                                               fireSense_SpreadPowerLaw = t$pars)), "fireSense_SpreadLinear")
})

test_that("linkedSpread() gives the year effect on x and the probability yearSpreadProb() gives", {
  t <- toyLinked(x = 0.3)
  set.seed(5); ls <- linkedSpread(0.7, t$pars, t$lin)
  set.seed(5); p <- yearSpreadProb(t$sp, 0.7, powerLaw = t$pars, linear = t$lin)
  ok <- !is.na(vals(t$lin))
  expect_equal(ls$prob[ok], p[ok], tolerance = 1e-12)
  expect_true(all(is.na(ls$prob[!ok])))
  expect_false(anyNA(ls$pars))                                        # spreadCpp wants no NA rows
  expect_true(all(ls$pars[!ok, c("pc", "floor")] == 0))
})

test_that("a raster of link parameters per ELF reaches each cell", {
  t <- toyLinked()
  pl <- c(t$sp, t$sp, t$sp, t$sp); names(pl) <- c("pc", "gamma", "floor", "shape")
  terra::values(pl[["pc"]]) <- ifelse(toyCol(toyRTM()) <= 4, 0.5, 0.9)
  terra::values(pl[["gamma"]]) <- 1; terra::values(pl[["floor"]]) <- 0.2; terra::values(pl[["shape"]]) <- 1
  m <- powerLawPars(pl, terra::ncell(pl))
  expect_identical(dim(m), c(100L, 4L))
  expect_equal(m[westCells(), "pc"], rep(0.5, 40))
  expect_equal(m[eastCells(), "pc"], rep(0.9, 50))
})

## yearEffects = "fitted": a hindcast of a fit year multiplies the expected ignitions and escapes by the year's fitted
## multipliers (layers ignitionYearEffect, escapeYearEffect from fireSense_ignitionPredict) instead of a draw.
## Toy: the 2 x 2 coarse grid over the 10 x 10 fine grid of helper-toy.R.

coarse <- function() terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2500, ymin = 0, ymax = 2500, crs = "EPSG:3005")

## the surface with sd layers and, unless NULL, fitted-effect layers (one value or one per coarse cell; NA: none)
fittedRas <- function(ig = 0.5, esc = 0.3, igSD = 0.6, escSD = 0.9, igEff = 1.6, escEff = 1.4,
                      igShape = NULL, escShape = NULL) {
  vals <- list(ignitionProb = ig, escapeProb = esc, ignitionYearSD = igSD, escapeYearSD = escSD,
               ignitionYearEffect = igEff, escapeYearEffect = escEff,
               ignitionYearEffectShape = igShape, escapeYearEffectShape = escShape)
  vals <- vals[!vapply(vals, is.null, logical(1))]
  r <- terra::rast(lapply(vals, function(v) terra::setValues(coarse(), rep_len(v, 4))))
  names(r) <- names(vals)
  r
}

fittedSim <- function(ras) list(fireSense_IgAndEscapeProbRas = ras,
                                fireSense_IgAndEscapeDistribution = list(ignition = "count:poisson", escape = "count:poisson"),
                                ignitionFitRTM = coarse(), flammableRTM = toyFlammable())

test_that("with fitted, the year's fitted multipliers replace the draw where the surface has them", {
  ras <- fittedRas(igEff = c(1.6, NA, 1.6, NA), escEff = c(1.4, NA, 1.4, NA))
  z <- c(ignition = 1.2, escape = -0.7)
  drawn <- list(ignition = fireSenseUtils::yearEffectMultiplier(0.6, z[["ignition"]]),
                escape = fireSenseUtils::yearEffectMultiplier(0.9, z[["escape"]]))
  m <- yearMultipliers(ras, z, fitted = TRUE)
  expect_equal(m$ignition, c(1.6, drawn$ignition, 1.6, drawn$ignition))
  expect_equal(m$escape, c(1.4, drawn$escape, 1.4, drawn$escape))
  ## the default ignores them
  expect_equal(yearMultipliers(ras, z), list(ignition = rep(drawn$ignition, 4), escape = rep(drawn$escape, 4)))
  ## no sd anywhere (no z): the fitted multipliers alone
  expect_equal(yearMultipliers(fittedRas(igSD = 0, escSD = 0), NULL, fitted = TRUE),
               list(ignition = rep(1.6, 4), escape = rep(1.4, 4)))
})

test_that("the draw's means are the surfaces times the fitted multipliers, whatever z", {
  s <- fittedSim(fittedRas(ig = 5, esc = 2))
  for (z in c(-1.5, 1.5)) {
    set.seed(1)
    ig <- drawIgnitionsAndEscapes(s, store = new.env(), z = c(ignition = z, escape = z), fitted = TRUE)
    expect_equal(unique(ig$igProb), 5 * 1.6)
    expect_equal(unique(ig$escapeProb), 2 * 1.4)
  }
})

test_that("with fitted multipliers the draw expects lambda * u_I * escapeProbPerIgnition(u_E * e, lambda * u_I) escapes", {
  ## the expectation fireSense_ignitionFit's fittedYearEffects() solves its multipliers with
  s <- fittedSim(fittedRas())
  set.seed(21)
  n <- 3000
  got <- replicate(n, {
    ig <- drawIgnitionsAndEscapes(s, store = new.env(), z = yearZ(s$fireSense_IgAndEscapeProbRas), fitted = TRUE)
    c(ignitions = nrow(ig), escapes = sum(ig$escaped))
  })
  lam <- 0.5 * 1.6
  expect <- c(ignitions = 4 * lam, escapes = 4 * lam * fireSenseUtils::escapeProbPerIgnition(0.3 * 1.4, lam))
  se <- apply(got, 1, stats::sd) / sqrt(n)
  expect_true(all(abs(rowMeans(got) - expect) < 4 * se))
  ## and with no spread between years beyond Poisson: the fitted year has no draw left in it
  expect_lt(stats::var(got["ignitions", ]), 1.15 * expect[["ignitions"]])
})

test_that("in the burn event, yearEffects = \"fitted\" uses the layers; the default ignores them, draws unchanged", {
  burnWith <- function(ras, params = list()) {
    set.seed(3)
    s <- runFireSense(NULL, times = list(start = 1, end = 3), params = c(list(.plotInterval = 99), params),
                      objects = c(fittedSim(ras)[c("fireSense_IgAndEscapeProbRas", "fireSense_IgAndEscapeDistribution",
                                                   "ignitionFitRTM")],
                                  list(fireSense_SpreadPredicted = toySpreadProb(p = 0.3))))
    list(s$burnSummary, s$ignitionsAndEscapes)
  }
  withLayers <- fittedRas(ig = 2, esc = 1)
  without <- withLayers[[c("ignitionProb", "escapeProb", "ignitionYearSD", "escapeYearSD")]]
  expect_identical(burnWith(withLayers), burnWith(without))
  ## the posterior layers do not change the default's random numbers either
  expect_identical(burnWith(fittedRas(ig = 2, esc = 1, igShape = 30, escShape = 8)), burnWith(without))
  fitted <- burnWith(withLayers, list(yearEffects = "fitted"))
  expect_equal(unique(fitted[[2]]$igProb), 2 * 1.6)
  expect_equal(unique(fitted[[2]]$escapeProb), 1 * 1.4)
  expect_error(runFireSense(NULL, params = list(yearEffects = "fit")), "yearEffects must be")
})

test_that("with posterior shapes each rep-year draws its multiplier: mean the fitted one, the posterior's spread", {
  ras <- fittedRas(igEff = c(1.6, NA, 1.6, NA), igShape = c(30, NA, 30, NA), escShape = 8)
  set.seed(5)
  draws <- t(replicate(4000, {
    m <- yearMultipliers(ras, NULL, fitted = TRUE)
    c(ign1 = m$ignition[1], ign3 = m$ignition[3], ign2 = m$ignition[2], esc = m$escape[1])
  }))
  ## one draw shared by the cells of a process, none where there is no fitted effect
  expect_identical(draws[, "ign1"], draws[, "ign3"])
  expect_true(all(draws[, "ign2"] == 1))
  ## Gamma(shape, shape) times the multiplier: mean multiplier, sd multiplier / sqrt(shape)
  expect_equal(mean(draws[, "ign1"]), 1.6, tolerance = 0.01)
  expect_equal(stats::sd(draws[, "ign1"]), 1.6 / sqrt(30), tolerance = 0.05)
  expect_equal(mean(draws[, "esc"]), 1.4, tolerance = 0.02)
  expect_equal(stats::sd(draws[, "esc"]), 1.4 / sqrt(8), tolerance = 0.05)
  ## a shape of NA is no uncertainty
  m <- yearMultipliers(fittedRas(igShape = NA, escShape = NA), NULL, fitted = TRUE)
  expect_identical(m, list(ignition = rep(1.6, 4), escape = rep(1.4, 4)))
})

test_that("fitted without fitted effects for the year draws, with one message per run", {
  st <- new.env()
  none <- fittedRas(igEff = NA, escEff = NA)
  expect_message(expect_true(fittedYearEffectsUsed(none, "fitted", st, 2001)), "no fitted year effect for 2001")
  expect_no_message(fittedYearEffectsUsed(none, "fitted", st, 2002))
  expect_no_message(expect_false(fittedYearEffectsUsed(none, "draw", new.env(), 2001)))
  expect_no_message(fittedYearEffectsUsed(fittedRas(), "fitted", new.env(), 2001))
})

## fireSense_burn with the ledger row's link (fireSense_SpreadLink, from fireSense_spreadPredict): "powerLawSmooth" and
## "richards" have a lower asymptote, so a fire on a landscape of very low x still spreads (the power law's p is 0
## there, and an escaped fire stays at its first pixel). The year effect and the per-fire effect use the row's link,
## on both paths: spreadCpp(link = ) with per-cell parameters, and the probabilities from the link in yearSpreadProb().
## Toy landscape of helper-toy.R.

linkPars <- list(
  powerLaw = c(pc = 0.5, gamma = 1, floor = 0.2, shape = 1),
  powerLawSmooth = c(pc = 0.5, gamma = 1, floor = 0.2, shape = 1, lower = 0.13),
  richards = c(pc = 0.5, lower = 0.13, nu = 0.5, B = 1))

toyLinkedBy <- function(link, x, pars = linkPars[[link]]) {
  rtm <- toyRTM()
  lin <- rtm; terra::values(lin) <- x
  lin[barrierCells(rtm)] <- NA
  sp <- lin; terra::values(sp) <- fireSenseUtils::linearLinkProb(vals(lin), link, pars)
  list(sp = sp, lin = lin, pars = pars, link = link)
}

## 100 years, each one escaped fire from cell 6: the sizes
sizesBy <- function(link, x, fireSD, years = 100L, pars = linkPars[[link]]) {
  t <- toyLinkedBy(link, x, pars)
  objs <- list(fireSense_SpreadPredicted = t$sp, fireSense_SpreadLinear = t$lin, fireSense_SpreadPowerLaw = t$pars,
               fireSense_SpreadLink = link, fireSense_SpreadFireSD = fireSD)
  ig <- data.table::data.table(pixelID = 6L, escapes = 1L, escaped = TRUE)
  set.seed(4)
  sim <- runFireSense(ig, times = list(start = 1, end = years), params = list(.plotInterval = 1e6, escapeSizeHa = NA),
                      objects = objs)
  sim$burnSummary$N
}

test_that("with x = -20 the power law's fires stay at one pixel and the new links' fires spread, on both paths", {
  for (fireSD in list(0.0001, 0)) {        # the per-fire path (spreadCpp with per-cell link parameters), and the precomputed one
    expect_true(all(sizesBy("powerLaw", -20, fireSD) == 1))
    for (lk in c("powerLawSmooth", "richards")) expect_gt(mean(sizesBy(lk, -20, fireSD) > 1), 0.2)   # p = 0.13 on 5 or more neighbours
  }
})

test_that("the per-fire path gives spreadCpp the row's link and parameters", {
  for (lk in names(linkPars)) {
    t <- toyLinkedBy(lk, 0.3)
    ls <- linkedSpread(0, t$pars, t$lin, link = lk)
    expect_identical(ls$link, lk)
    expect_identical(colnames(ls$pars), fireSenseUtils::spreadLinkParNames[[lk]])
    ok <- !is.na(vals(t$lin))
    expect_equal(ls$prob[ok], vals(t$sp)[ok], tolerance = 1e-12)
    expect_true(all(is.na(ls$prob[!ok])))
    expect_false(anyNA(ls$pars))                    # spreadCpp wants no NA rows, and checks lower and nu
    ## spreadCpp accepts them
    expect_no_error(SpaDES.tools::spreadCpp(t$sp, loci = 6L, spreadProb = ls$linear, link = ls$link, linkPars = ls$pars))
  }
  ## no link given: the power law, as before
  t <- toyLinkedBy("powerLaw", 0.3)
  expect_identical(linkedSpread(0, t$pars, t$lin)$link, "powerLaw")
})

test_that("a year effect eps goes through the row's link: p = link(x + eps)", {
  for (lk in c("powerLawSmooth", "richards")) {
    t <- toyLinkedBy(lk, -2)
    set.seed(3); eps <- 0.6 * stats::rnorm(1)
    set.seed(3)
    q <- yearSpreadProb(t$sp, 0.6, powerLaw = t$pars, linear = t$lin, link = lk)
    ok <- !is.na(vals(t$lin))
    expect_equal(q[ok], fireSenseUtils::linearLinkProb(vals(t$lin)[ok] + eps, lk, t$pars), tolerance = 1e-12)
    expect_true(all(q[ok] >= t$pars[["lower"]]))
    expect_equal(yearSpreadProb(t$sp, 0.6, powerLaw = t$pars, linear = t$lin, z = 0, link = lk), vals(t$sp), tolerance = 1e-12)
  }
})

test_that("a SpreadPowerLaw raster of Richards parameters reaches each cell", {
  t <- toyLinkedBy("richards", 0)
  pl <- c(t$sp, t$sp, t$sp, t$sp); names(pl) <- c("pc", "lower", "nu", "B")
  terra::values(pl[["pc"]]) <- ifelse(toyCol(toyRTM()) <= 4, 0.5, 0.9)
  terra::values(pl[["lower"]]) <- 0.1; terra::values(pl[["nu"]]) <- 2; terra::values(pl[["B"]]) <- 1
  m <- powerLawPars(pl, terra::ncell(pl), "richards")
  expect_identical(dim(m), c(100L, 4L))
  expect_identical(colnames(m), c("pc", "lower", "nu", "B"))
  expect_equal(m[eastCells(), "pc"], rep(0.9, 50))
})

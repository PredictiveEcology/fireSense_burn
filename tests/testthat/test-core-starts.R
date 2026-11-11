## Fires start only in the core of rasterToMatchLargeELF (the buffer only removes edge effects), and still spread
## into the buffer. Toy landscape of helper-toy.R: west block cols 1-4, barrier col 5, east block cols 6-10.
## Here the core is cols 6-8, the buffer cols 9-10, and the west block is outside the ELF.

igRowsEsc <- function(pixelID)
  data.table::data.table(pixelID = pixelID, escapes = length(pixelID), escaped = rep(TRUE, length(pixelID)))

toyLargeELF <- function() {
  r <- toyRTM()
  col <- toyCol(r)
  terra::values(r) <- ifelse(col %in% 6:8, 2, ifelse(col %in% 9:10, 1, NA))
  r
}

test_that("a fire starting in the buffer or outside the ELF does not burn; one in the core spreads into the buffer", {
  ## cell 1 is outside the ELF, 6 is in the core, 10 is in the buffer
  sim <- runFireSense(igRowsEsc(c(1L, 6L, 10L)), objects = list(rasterToMatchLargeELF = toyLargeELF()))
  expect_identical(unique(sim$burnDT$initialPixels), 6L)
  expect_identical(sort(sim$burnDT$pixels), eastCells())                 # the buffer (cols 9-10) burned too
  ## the ignition table stays complete: only the starts that are spread are filtered
  expect_identical(sim$ignitionsAndEscapes$pixelID, c(1L, 6L, 10L))
  expect_false(any(vals(sim$rstCurrentBurn)[westCells()] %in% 1))
})

test_that("a year whose only start is in the buffer burns nothing", {
  sim <- runFireSense(igRowsEsc(10L), objects = list(rasterToMatchLargeELF = toyLargeELF()))
  expect_true(all(is.na(vals(sim$rstCurrentBurn))))
  expect_identical(NROW(sim$burnSummary), 0L)
})

test_that("without rasterToMatchLargeELF a fire may start anywhere, as before", {
  sim <- runFireSense(igRowsEsc(c(1L, 10L)))
  expect_identical(sort(unique(sim$burnDT$initialPixels)), c(1L, 10L))
})

test_that("a multi-ELF (categorical) raster has no buffer: every labelled cell is core", {
  r <- toyRTM()
  terra::values(r) <- ifelse(toyCol(r) <= 5, 1L, 2L)           # ELFs 1 and 2: 2 must not be read as 'core'
  levels(r) <- data.frame(value = 1:2, ELFind = c("a", "b"))
  r[1] <- NA
  sim <- runFireSense(igRowsEsc(c(2L, 10L)), objects = list(rasterToMatchLargeELF = r))
  expect_identical(sort(unique(sim$burnDT$initialPixels)), c(2L, 10L))
})

## fireSense_EscapeDefinition from fireSense_spreadPredict: one row per ELF, NA for a fit without a recorded definition
test_that("every non-NA row of the fit's escape definition must equal this run's", {
  def <- function(size) data.frame(escapeSizeHa = c(50, size), fireCauses = c("natural,unknown", if (is.na(size)) NA else "natural,unknown"),
                                   polygonID = c("1.1", "1.2"))
  d <- def(NA_real_); d$escapeSizeHa[1] <- 25
  expect_error(runFireSense(igRowsEsc(6L), objects = list(fireSense_EscapeDefinition = d)), "differs")
  d <- def(100)                                                        # the second row (100 ha) differs
  expect_error(runFireSense(igRowsEsc(6L), objects = list(fireSense_EscapeDefinition = d)), "ELF 1.2")
  expect_no_error(runFireSense(igRowsEsc(6L), objects = list(fireSense_EscapeDefinition = def(NA_real_))))
})

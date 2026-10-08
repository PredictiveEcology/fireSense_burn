## Escaped fires and the ignitions that did not escape (toy landscape in helper-toy.R: 250 m pixels,
## 6.25 ha each; west block cols 1-4, barrier col 5, east block cols 6-10).
##
## * One fire per escaped ignition (`escaped`), not `escapes` fires per row: `escapes` is the coarse
##   pixel's count, repeated on each of its ignitions, so 2 ignitions with 2 escapes gave 4 fires.
## * An escaped fire starts escaped: spreadCpp(minSize = escapeSizePixels(escapeSizeHa)), as in the fit.
## * An ignition that did not escape burns a small patch sized from nonEscapedFireSizesHa.

igRows <- function(pixelID, escaped, escapes = sum(escaped))
  data.table::data.table(pixelID = pixelID, escapes = escapes, escaped = escaped)

test_that("each escaped ignition is one fire, whatever `escapes` says", {
  ## two ignitions of one coarse pixel that had 2 escapes; only the first escaped
  sim <- runFireSense(igRows(c(1L, 10L), c(TRUE, FALSE), escapes = 2L))
  expect_identical(sim$burnSummary$igLoc, 1L)                 # the west block only
  expect_identical(sort(sim$burnDT$pixels), westCells())
})

test_that("escaped fires start escaped: minSize is the pixels in escapeSizeHa", {
  seen <- list()
  local_mocked_bindings(
    spreadCpp = function(...) {
      a <- list(...)
      seen[[length(seen) + 1L]] <<- a
      data.table::data.table(initialLocus = a$loci, indices = a$loci)
    },
    .package = "SpaDES.tools"
  )
  runFireSense(igRows(c(1L, 10L), c(TRUE, TRUE)),
               params = list(escapeSizeHa = 50, jumpTries = 3L, jumpMeanDist = 4))
  expect_length(seen, 1L)
  expect_identical(seen[[1]]$minSize, 8L)   # 8 pixels of 6.25 ha = 50 ha
  expect_identical(seen[[1]]$loci, c(1L, 10L))
  expect_identical(seen[[1]]$jumpTries, 3L)
  expect_identical(seen[[1]]$jumpMeanDist, 4)
})

test_that("an escaped fire with a low spread probability still reaches escapeSizeHa", {
  ## spread probability 0.02: without the minSize start this fire almost always stays at 1 pixel
  low <- toySpreadProb(p = 0.02)
  sizes <- vapply(1:20, function(i) {
    set.seed(i)
    sim <- runFireSense(igRows(1L, TRUE), objects = list(fireSense_SpreadPredicted = low))
    sim$burnSummary$N
  }, integer(1))
  expect_true(all(sizes >= 8L))   # 8 pixels of 6.25 ha = 50 ha
  expect_true(all(sizes <= 40L))  # and never across the barrier
})

test_that("escapeSizeHa = NA spreads escaped fires without a minSize start (minSize 0)", {
  seen <- list()
  local_mocked_bindings(
    spreadCpp = function(...) {
      a <- list(...)
      seen[[length(seen) + 1L]] <<- a
      data.table::data.table(initialLocus = a$loci, indices = a$loci)
    },
    .package = "SpaDES.tools"
  )
  runFireSense(igRows(1L, TRUE), params = list(escapeSizeHa = NA))
  expect_identical(seen[[1]]$minSize, 0L)
})

test_that("an ignition that did not escape burns a patch of a size drawn from nonEscapedFireSizesHa", {
  ## 25 ha = 4 pixels exactly, so the patch is 4 pixels, all in the east block
  sim <- runFireSense(igRows(10L, FALSE), objects = list(nonEscapedFireSizesHa = 25))
  expect_identical(sim$burnSummary$igLoc, 10L)
  expect_identical(sim$burnSummary$N, 4L)
  expect_true(all(sim$burnDT$pixels %in% eastCells()))
  expect_true(10L %in% sim$burnDT$pixels)
})

test_that("without nonEscapedFireSizesHa an ignition that did not escape burns nothing, as before", {
  sim <- runFireSense(igRows(10L, FALSE))
  expect_null(sim$burnSummary)
})

test_that("small fires keep the expected area and never burn pixels already burned", {
  set.seed(1)
  land <- toySpreadProb()
  sp <- as.vector(terra::values(land))
  ## 2.5 pixels: 2 or 3, 2.5 on average
  n <- vapply(1:400, function(i) NROW(smallFires(1L, 15.625, land, sp)), integer(1))
  expect_true(all(n %in% 2:3))
  expect_equal(mean(n), 2.5, tolerance = 0.1)
  ## an ignition on a burned pixel burns nothing; nor does one on the barrier
  expect_identical(NROW(smallFires(1L, 25, land, sp, burned = 1L)), 0L)
  expect_identical(NROW(smallFires(barrierCells()[1], 25, land, sp)), 0L)
  ## a patch next to a burned pixel goes around it
  b <- smallFires(1L, 25, land, sp, burned = 2L)
  expect_false(2L %in% b$pixels)
})

test_that("a clear error when ignitionsAndEscapes has no `escaped`", {
  expect_error(runFireSense(data.table::data.table(pixelID = 1L, escapes = 1L)), "escaped")
})

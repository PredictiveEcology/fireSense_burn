## burn() plots when (time - start) %% .plotInterval < 1, to the devices named in `.plots`.

ig <- data.table::data.table(pixelID = 1L, escapes = 1L, escaped = TRUE)
figDir <- function() file.path(toyPaths()$outputPath, "figures", "fireSense_burn")

test_that(".plots = 'png' writes one figure per plotting year and registers it", {
  unlink(figDir(), recursive = TRUE)
  sim <- runFireSense(ig, times = list(start = 1, end = 4),
                      params = list(.plots = "png", .plotInterval = 2))
  ## years 1 and 3: (1 - 1) %% 2 = 0 and (3 - 1) %% 2 = 0; years 2 and 4 give 1
  expect_identical(sort(list.files(figDir())),
                   c("Annual Fire Maps 1.png", "Annual Fire Maps 3.png"))
  expect_true(all(file.size(list.files(figDir(), full.names = TRUE)) > 0))
  out <- SpaDES.core::outputs(sim)
  expect_identical(basename(out$file), c("Annual Fire Maps 1.png", "Annual Fire Maps 3.png"))
  expect_identical(as.numeric(out$saveTime), c(1, 3))
  ## plotting does not change what burned
  expect_identical(sim$burnSummary$N, rep(40L, 4))
})

test_that("the default .plots = NULL writes no figure", {
  unlink(figDir(), recursive = TRUE)
  sim <- runFireSense(ig, times = list(start = 1, end = 2), params = list(.plotInterval = 1))
  expect_identical(length(list.files(figDir())), 0L)
  expect_identical(nrow(SpaDES.core::outputs(sim)), 0L)
})

test_that("no figure is written in a year without escapes", {
  unlink(figDir(), recursive = TRUE)
  sim <- runFireSense(data.table::data.table(pixelID = 1L, escapes = 0L, escaped = FALSE),
                      params = list(.plots = "png", .plotInterval = 1))
  expect_identical(length(list.files(figDir())), 0L)
})

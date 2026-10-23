## placeIgnitions() draws each ignited coarse pixel's ignitions from that coarse pixel's own fine pixels.

## fine pixels (not in pixelID order, as after a join) of coarse pixels 1-6; coarse pixel `ignited` have
## ignitions; coarse 3 has a single fine pixel, coarse 6 has none ignited
toyIgs <- function(ignitions = c(`1` = 2L, `2` = 1L, `3` = 1L, `4` = 3L, `5` = 0L, `6` = 0L),
                   ids = c(3L, 1L, 5L, 2L, 9L, 4L, 11L, 7L, 6L, 12L, 8L, 10L, 15L, 13L, 14L, 20L, 18L, 17L, 16L, 19L),
                   chunk = c(1, 1, 2, 1, 2, 2, 3, 4, 4, 4, 4, 4, 5, 5, 5, 6, 6, 6, 6, 6)) {
  igs <- data.table::data.table(pixelID = ids, chunkyPixels = chunk)
  igs[, `:=`(igProb = seq_len(.N) / 100, ignitions = ignitions[as.character(chunkyPixels)],
             escapeProb = seq_len(.N) / 50, escapes = 1L)]
  data.table::setcolorder(igs, c("pixelID", "igProb", "ignitions", "escapeProb", "escapes", "chunkyPixels"))
  igs
}
drawTableOf <- function(igs) unique(igs[ignitions > 0, .(chunkyPixels, ignitions, escapes)])

checkPlaced <- function(igs, res) {
  expected <- unique(igs[ignitions > 0, .(chunkyPixels, ignitions)])
  ## right count per coarse pixel (never more than its fine pixels)
  counts <- res[, .N, by = "chunkyPixels"]
  want <- igs[ignitions > 0, .(N = min(ignitions[1], .N)), by = "chunkyPixels"]
  expect_identical(counts[order(chunkyPixels)]$N, want[order(chunkyPixels)]$N)
  ## each drawn pixel belongs to its own coarse pixel
  expect_true(all(igs$chunkyPixels[match(res$pixelID, igs$pixelID)] == res$chunkyPixels))
  expect_false(anyDuplicated(res$pixelID) > 0)
}

test_that("placeIgnitions places the right count, within each coarse pixel, without duplicates", {
  igs <- toyIgs()
  for (seed in c(1, 2, 3, 42, 2024, 99999)) {
    set.seed(seed)
    checkPlaced(igs, placeIgnitions(igs, drawTableOf(igs)))
  }
})

test_that("coarse pixels with zero ignitions place nothing and use no random numbers", {
  igs <- toyIgs(ignitions = c(`1` = 0L, `2` = 0L, `3` = 0L, `4` = 0L, `5` = 0L, `6` = 0L))
  set.seed(5); before <- .Random.seed
  res <- placeIgnitions(igs, drawTableOf(igs))
  expect_identical(nrow(res), 0L)
  expect_identical(.Random.seed, before)
})

test_that("a coarse pixel with one fine pixel places its ignition on that pixel", {
  ## coarse 1: one fine pixel (ID 50), 1 ignition; coarse 2: pixels 1:40, no ignitions (escapes NA)
  igs <- data.table::data.table(pixelID = c(1:40, 50L), chunkyPixels = c(rep(2L, 40), 1L))
  igs[, `:=`(igProb = 0.1, escapeProb = 0.1, ignitions = ifelse(chunkyPixels == 1L, 1L, 0L),
             escapes = ifelse(chunkyPixels == 1L, 1L, NA_integer_))]
  for (seed in 1:20) {
    set.seed(seed)
    res <- placeIgnitions(igs, drawTableOf(igs))
    expect_identical(res$pixelID, 50L)
    expect_identical(res$chunkyPixels, 1L)
    expect_false(anyNA(res$escapes))
  }
})

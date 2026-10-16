## Placing ignitions on fine pixels must give the same pixels and the same random stream as the
## per-coarse-pixel scans of the whole fine-pixel table it replaced.

## reference: the code before placeIgnitions() (kept here only to compare against)
oldPlaceIgnitions <- function(igs, drawTable) {
  lapply(drawTable$chunkyPixels,
         FUN = function(n, draw = drawTable, ig = igs) {
           sampledChunk <- draw[chunkyPixels == n]
           pixelID_pop <- igs[chunkyPixels == sampledChunk$chunkyPixels]
           drawn <- sample(pixelID_pop$pixelID, size = sampledChunk$ignitions)
           ig[pixelID %in% drawn, .(pixelID, igProb, ignitions, escapeProb, escapes, chunkyPixels)]
         }) |>
    data.table::rbindlist()
}

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

compareToOld <- function(igs, seed) {
  drawTable <- drawTableOf(igs)
  set.seed(seed); old <- oldPlaceIgnitions(igs, drawTable); seedOld <- .Random.seed
  set.seed(seed); new <- placeIgnitions(igs, drawTable);    seedNew <- .Random.seed
  expect_identical(new, old)
  expect_identical(seedNew, seedOld)
  invisible(new)
}

test_that("placeIgnitions gives the old ignitions and random stream, for several seeds", {
  ## coarse 5 and 6 have no ignitions (no candidates drawn); coarse 3 has exactly one candidate but
  ## here its pixel ID is 11, so the single-candidate draw is from 1:11 -- the old behaviour, kept
  igs <- toyIgs()
  for (seed in c(1, 2, 3, 42, 2024, 99999)) compareToOld(igs, seed)
})

test_that("coarse pixels with zero ignitions place nothing and use no random numbers", {
  igs <- toyIgs(ignitions = c(`1` = 0L, `2` = 0L, `3` = 0L, `4` = 0L, `5` = 0L, `6` = 0L))
  set.seed(5); before <- .Random.seed
  res <- placeIgnitions(igs, drawTableOf(igs))
  expect_identical(nrow(res), 0L)
  expect_identical(.Random.seed, before)
})

test_that("a coarse pixel with one candidate keeps the sample(x, size) draw from 1:x", {
  ## only coarse 3 is ignited; its one fine pixel has ID 11. The old code draws from 1:11
  igs <- toyIgs(ignitions = c(`1` = 0L, `2` = 0L, `3` = 1L, `4` = 0L, `5` = 0L, `6` = 0L))
  for (seed in 1:20) compareToOld(igs, seed)
  ## an ID of 1 draws pixel 1 (from 1:1)
  igs1 <- toyIgs(ignitions = c(`1` = 0L, `2` = 0L, `3` = 1L, `4` = 0L, `5` = 0L, `6` = 0L))
  igs1[chunkyPixels == 3, pixelID := 1L]
  igs1[pixelID == 1L & chunkyPixels != 3, pixelID := 21L]
  for (seed in 1:5) compareToOld(igs1, seed)
})

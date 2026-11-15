## ignitionSource = "replay": a fast hindcast spreads, rep by rep, the ignitions and escapes of a reference hindcast,
## so hindcasts that differ in spread alone share them. Toy landscape of helper-toy.R (6.25 ha pixels, spread
## probability 1).

## the toy hindcast: `nReps` burn events at decimal times, as fireSenseUtils::hindcastSetup() runs them
hindcastTimes <- function(nReps) list(start = 2, end = 2 + (nReps - 0.5) * 0.001)

## run with `fun` of the module replaced by a wrapper that records what it returns for each burn event
runRecording <- function(fun, params, objects, nReps) {
  sim <- runFireSense(NULL, times = hindcastTimes(nReps), doSpades = FALSE, objects = objects,
                      params = c(params, list(.runInterval = 0.001)))
  mods <- environment(sim@.xData$.mods$fireSense_burn$burn)
  real <- mods[[fun]]
  got <- list()
  mods[[fun]] <- function(...) { out <- real(...); got[[length(got) + 1L]] <<- out[, c("pixelID", "escaped")]; out }
  sim <- suppressMessages(SpaDES.core::spades(sim, debug = FALSE))
  list(sim = sim, ignitions = got)
}

test_that("a replay spreads exactly the saved run's ignitions and escapes, rep by rep", {
  ref <- withr::local_tempdir()
  set.seed(11)
  saved <- runRecording("drawIgnitionsAndEscapes", list(replaySave = TRUE), predictedSurfaces(ign = 1, esc = 0.6),
                        nReps = 6)
  f <- file.path(SpaDES.core::outputPath(saved$sim), "hindcast_ignitions.csv")
  expect_true(file.exists(f))
  expect_gt(sum(vapply(saved$ignitions, function(i) sum(i$escaped), integer(1))), 0L)
  ## every rep is in the file, those without ignitions too
  expect_setequal(data.table::fread(f)$rep, 1:6)
  file.copy(f, ref)
  unlink(f)  # the toy runs share one outputPath

  set.seed(99)  # another stream: nothing of the replay may depend on it
  replay <- runRecording("replayedIgnitions", list(ignitionSource = "replay", replayFrom = ref),
                         predictedSurfaces(ign = 1, esc = 0.6), nReps = 6)
  expect_identical(length(replay$ignitions), 6L)
  expect_identical(lapply(replay$ignitions, as.data.frame), lapply(saved$ignitions, as.data.frame))
  ## and so the same fires start each rep (their sizes are spread's own draw: two fires in one block compete)
  fires <- function(s) sort(paste(s$burnSummary$year, s$burnSummary$igLoc))
  expect_identical(fires(replay$sim), fires(saved$sim))
})

test_that("the default draws and writes no replay file", {
  out <- runRecording("drawIgnitionsAndEscapes", list(), predictedSurfaces(), nReps = 2)
  expect_identical(length(out$ignitions), 2L)
  expect_false(file.exists(file.path(SpaDES.core::outputPath(out$sim), "hindcast_ignitions.csv")))
})

test_that("replay needs replayFrom, and a rep the reference has", {
  expect_error(runFireSense(NULL, params = list(ignitionSource = "replay")), "replayFrom")
  replay <- data.table::data.table(rep = 1:2, pixelID = c(3L, NA), escaped = c(TRUE, NA))
  expect_identical(replayedIgnitions(replay, 1L), data.table::data.table(pixelID = 3L, escaped = TRUE))
  expect_identical(nrow(replayedIgnitions(replay, 2L)), 0L)
  expect_error(replayedIgnitions(replay, 3L), "no rep 3")
})

test_that("replayRep() numbers the reps as fireSense_summary does", {
  p <- list(.runInitialTime = 2001, .runInterval = 0.001)
  expect_identical(replayRep(2001 + (0:19) * 0.001, p), 1:20)
  expect_identical(replayRep(5, list(.runInitialTime = 5, .runInterval = NA)), 1L)
})

## A hindcast made before replaySave (Nov 14 2026, ELF 11.4, 240 m pixels: an escape is 9 pixels) has no
## hindcast_ignitions.csv; its fires and per-rep counts are in tests/testthat/fixtures.
fixture <- function(year) testthat::test_path("fixtures", paste0("hindcast_11.4_", year))

test_that("without a replay file the ignitions are rebuilt from the reference's fires and match its escapes", {
  reps <- data.table::fread(file.path(fixture(2004), "hindcast_reps.csv"))
  got <- expect_no_warning(readReplayIgnitions(fixture(2004), 9L))
  expect_setequal(unique(got$rep), reps$rep)
  rebuilt <- vapply(reps$rep, function(r) sum(got$escaped[got$rep == r], na.rm = TRUE), integer(1))
  expect_identical(rebuilt, reps$escapes)
  ## every fire is an ignition of its rep, at its ignition pixel
  bs <- data.table::fread(file.path(fixture(2004), "fireSense_burnSummary.csv"))
  expect_identical(sort(got$pixelID[!is.na(got$pixelID)]), sort(as.integer(bs$igLoc)))
})

test_that("a rebuilt rep whose escapes differ from the recorded ones is named in a warning", {
  ## rep 4 of 2001 recorded 11 escapes; 10 of its fires reached 9 pixels (an escape blocked below 9 pixels, or two
  ## escapes on one pixel, cannot be told from its fires)
  expect_warning(got <- readReplayIgnitions(fixture(2001), 9L), "in 1 of 20 reps \\(rep: rebuilt/recorded 4: 10/11\\)")
  reps <- data.table::fread(file.path(fixture(2001), "hindcast_reps.csv"))
  rebuilt <- vapply(reps$rep, function(r) sum(got$escaped[got$rep == r], na.rm = TRUE), integer(1))
  expect_identical(rebuilt[-4], reps$escapes[-4])
})

test_that("a replay of a hindcast without the replay file spreads its rebuilt escapes", {
  ref <- withr::local_tempdir()
  set.seed(5)
  saved <- runRecording("drawIgnitionsAndEscapes", list(), predictedSurfaces(ign = 0.4, esc = 0.3), nReps = 4)
  ## the reference's files, as fireSense_summary writes them: its fires and its per-rep escapes
  times <- 2 + (0:3) * 0.001
  data.table::fwrite(saved$sim$burnSummary, file.path(ref, "fireSense_burnSummary.csv"))
  data.table::fwrite(data.table::data.table(rep = 1:4, time = times,
                                            escapes = vapply(saved$ignitions, function(i) sum(i$escaped), integer(1))),
                     file.path(ref, "hindcast_reps.csv"))
  replay <- runRecording("replayedIgnitions", list(ignitionSource = "replay", replayFrom = ref),
                         predictedSurfaces(ign = 0.4, esc = 0.3), nReps = 4)
  expect_identical(lapply(replay$ignitions, function(i) sort(i$pixelID[i$escaped])),
                   lapply(saved$ignitions, function(i) sort(unique(i$pixelID[i$escaped]))))
})

## Toy inputs for the fireSense_burn tests. Nothing is downloaded and nothing needs a
## package outside the module's `reqdPkgs`.
##
## The landscape is 10 x 10 pixels of 250 m, so one pixel is 250 * 250 / 1e4 = 6.25 ha.
## Column 5 is a non-flammable barrier. Cell numbers run row-wise from the top left,
## so cell 1 is (row 1, col 1), cell 10 is (row 1, col 10), cell 5 is on the barrier.
##
##   cols 1-4 : "west" block, 40 pixels (cells with col <= 4)
##   col  5   : barrier, 10 pixels
##   cols 6-10: "east" block, 50 pixels

toyRTM <- function(n = 10L, res = 250) {
  terra::rast(nrows = n, ncols = n, xmin = 0, xmax = n * res, ymin = 0, ymax = n * res,
              crs = "EPSG:3005", vals = 1)
}

toyCol <- function(r) terra::colFromCell(r, seq_len(terra::ncell(r)))

toyFlammable <- function(rtm = toyRTM()) {
  flam <- rtm
  flam[toyCol(rtm) == 5] <- 0
  flam
}

## Spread probability `p` where flammable, `barrier` on the barrier.
## p = 1 makes spread2() deterministic: a fire burns its whole block and nothing else.
toySpreadProb <- function(rtm = toyRTM(), p = 1, barrier = 0) {
  sp <- rtm
  terra::values(sp) <- p
  sp[toyCol(rtm) == 5] <- barrier
  sp
}

westCells <- function(rtm = toyRTM()) which(toyCol(rtm) <= 4)
eastCells <- function(rtm = toyRTM()) which(toyCol(rtm) >= 6)
barrierCells <- function(rtm = toyRTM()) which(toyCol(rtm) == 5)

## Helpers are sourced before setup.R and cannot see its objects, so the module's
## location is worked out here the same way: testthat runs in tests/testthat.
toyModuleRoot <- function() normalizePath(testthat::test_path("..", ".."), winslash = "/")

toyPaths <- function() {
  root <- file.path(tempdir(), "fireSenseToy")
  paths <- list(cachePath = file.path(root, "cache"), inputPath = file.path(root, "inputs"),
                modulePath = dirname(toyModuleRoot()), outputPath = file.path(root, "outputs"))
  for (p in paths[c("cachePath", "inputPath", "outputPath")])
    dir.create(p, recursive = TRUE, showWarnings = FALSE)
  paths
}

## simInit() + spades() on the toy inputs. `objects` and `params` override the defaults.
runFireSense <- function(ignitions, times = list(start = 1, end = 1), params = list(),
                         objects = list(), doSpades = TRUE) {
  rtm <- toyRTM()
  objs <- list(rasterToMatch = rtm,
               flammableRTM = toyFlammable(rtm),
               fireSense_SpreadPredicted = toySpreadProb(rtm),
               ignitionsAndEscapes = ignitions)
  objs[names(objects)] <- objects
  objs <- objs[!vapply(objs, is.null, logical(1))]

  ## burn() calls par(), which would otherwise open Rplots.pdf beside the tests
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)

  sim <- suppressMessages(SpaDES.core::simInit(
    times = times, modules = basename(toyModuleRoot()), objects = objs,
    params = stats::setNames(list(params), basename(toyModuleRoot())), paths = toyPaths()
  ))
  if (doSpades) sim <- suppressMessages(SpaDES.core::spades(sim, debug = FALSE))
  sim
}

vals <- function(r) as.vector(terra::values(r))

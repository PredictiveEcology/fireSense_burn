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

## surfaces that ignite and escape fires in every coarse pixel (2 x 2 pixels over the toy landscape), with
## `ignitionProb` and `escapeProb` of `ign` and `esc`
predictedSurfaces <- function(ign = 5, esc = 5) {
  coarse <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2500, ymin = 0, ymax = 2500,
                        crs = "EPSG:3005", vals = 1)
  ras <- c(coarse * ign, coarse * esc)
  names(ras) <- c("ignitionProb", "escapeProb")
  list(fireSense_IgAndEscapeProbRas = ras,
       fireSense_IgAndEscapeDistribution = list(ignition = "count:poisson", escape = "count:poisson"),
       ignitionFitRTM = coarse)
}

## fire polygons: a square of `side` pixels (all of them burnable) whose upper-left pixel is `cell`, with the fire's
## year and its whole size, its cause and, if given, `PRESCRIBED`
toyFirePolys <- function(cells, years, sizesHa, side = 3L, rtm = toyRTM(), causes = "Natural", prescribed = NULL) {
  xy <- terra::xyFromCell(rtm, cells)
  w <- terra::res(rtm)[1] * side
  one <- function(i) {   # cell `i` is the polygon's upper-left pixel
    x0 <- xy[i, 1] - 125; x1 <- x0 + w; y1 <- xy[i, 2] + 125; y0 <- y1 - w
    terra::vect(sprintf("POLYGON((%f %f, %f %f, %f %f, %f %f, %f %f))", x0, y0, x1, y0, x1, y1, x0, y1, x0, y0),
                crs = terra::crs(rtm))
  }
  p <- do.call(rbind, lapply(seq_along(cells), one))
  p$YEAR <- years
  p$POLY_HA <- sizesHa
  p$FIRECAUS <- causes
  if (!is.null(prescribed)) p$PRESCRIBED <- prescribed
  list(p)
}

## `postProcess()` is called by the module (coarseToFineMap()); in a project `reproducible` is attached
## from the module's reqdPkgs.
suppressPackageStartupMessages(library(reproducible))

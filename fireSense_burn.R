# Everything in this file gets sourced during simInit, and all functions and objects
# are put into the simList. To use objects and functions, use sim$xxx.
defineModule(sim, list(
  name = "fireSense_burn",
  description = "A landscape fire model, sensitive to environmental changes (e.g.
                 weather and land-cover).",
  keywords = c("fire", "percolation", "environmental control", "feedback",
               "weather", "vegetation", "land-cover"),
  authors = c(
    person("Eliot", "McIntire", email = "eliot.mcintire@nrcan-rncan.gc.ca", role = c("aut", "cre")),
    person("Jean", "Marchal", email = "jean.d.marchal@gmail.com", role = "aut"),
    person(c("Alex", "M."), "Chubaty", email = "achubaty@for-cast.ca", role = "ctb")
  ),
  childModules = character(),
  version = numeric_version("2.1.0"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  documentation = list("README.md", "fireSense_burn.Rmd"), ## same file
  reqdPkgs = list("data.table", "PredictiveEcology/fireSenseUtils@development (>= 0.2.3.9044)",
                  "ggplot2", "ggspatial", "PredictiveEcology/SpaDES.tools@development (>= 2.1.3.9009)",
                  "terra"),
  loadOrder = list(after = c("fireSense_ignitionPredict", "fireSense_spreadPredict")),
  parameters = rbind(
    defineParameter(".plots", "character|logical", default = NULL, ## TODO: use .plotInitialTime etc.
                    desc = "Passed to `types` in `Plots()`, e.g. \"screen\", \"png\". `NULL` or `NA` for no plots."),
    defineParameter(".plotInterval", "numeric", 10, NA, NA,
                    "Years between plots of annual fire IDs, cumulative burns and spread probability."),
    defineParameter(".runInitialTime", "numeric", start(sim), NA, NA,
                    "Time of the first `burn` event."),
    defineParameter(".runInterval", "numeric", 1, NA, NA,
                    "Years between `burn` events. `NA` burns once only."),
    defineParameter(".studyAreaName", "character", NA, NA, NA,
                    "Human-readable name for the study area used."),
    defineParameter("escapeSizeHa", "numeric", 50, 0, NA,
                    paste("Size (ha) a fire must reach to count as escaped, as in the spread fit: each escaped",
                          "fire burns this area first, whatever its spread probability, then spreads normally.",
                          "`NA` spreads escaped fires from their ignition pixel only.")),
    defineParameter("jumpTries", "integer", 20L, 0L, NA,
                    paste("Passed to `SpaDES.tools::spreadCpp()` for escaped fires: attempts to jump for a fire",
                          "still under `escapeSizeHa` that has nowhere left to spread. Default 20, as fireSense_spreadFit fits",
                          "with; 0 is off.")),
    defineParameter("jumpMeanDist", "numeric", 3, 0, NA,
                    "Passed to `SpaDES.tools::spreadCpp()`: mean jump distance, in cells."),
    defineParameter("whichModulesToPrepare", "character",
                    default = c("fireSense_spreadPredict", "fireSense_ignitionPredict", "fireSense_EscapePredict"),
                    NA, NA,
                    "Fires spread only if this includes `fireSense_spreadPredict`. Other values are ignored.")
  ),
  inputObjects = rbind(
    expectsInput("fireSense_SpreadPredicted", "SpatRaster",
                 "Per-pixel spread probability for the current year."),
    expectsInput("fireSense_SpreadSD", "SpatRaster|numeric",
                 paste("Sd of the per-year random effect on logit spread probability, as fitted by",
                       "fireSense_spreadFit (`yearSpreadSD`): a raster aligned with `fireSense_SpreadPredicted`",
                       "(from fireSense_spreadPredict, per ELF) or one number. Each year draws one z ~ N(0, 1);",
                       "all of that year's fires spread with plogis(qlogis(p) + z * sd). NULL or 0: no effect.")),
    expectsInput("flammableRTM", "SpatRaster", 
                 "Binary SpatRaster (1 = flammable, 0 = not). Non-flammable pixels are `NA` in `burnMap`."),
    expectsInput("ignitionsAndEscapes", "data.table",
                 paste("One row per ignition, with `pixelID` and `escaped` (logical), as fireSense_ignitionPredict",
                       "(>= 1.0.0.9003) makes it. Each escaped ignition is one fire.")),
    expectsInput("nonEscapedFireSizesHa", "numeric",
                 paste("Sizes (ha) of the study area's observed fires below `escapeSizeHa`, from",
                       "fireSense_dataPrepFit. Each ignition that did not escape burns a patch of a size drawn",
                       "from these. `NULL`: ignitions that did not escape burn nothing.")),
    expectsInput("rasterToMatch", "SpatRaster", sourceURL = NA,
                 "Template raster for the study area, ideally buffered to limit fire edge effects.")
  ),
  outputObjects = rbind(
    createsOutput("burnDT", "data.table",
                  paste("The most recent fire year's burned pixels: `initialPixels` (the fire's ignition pixel),",
                        "`pixels`, and `fire_id`.")),
    createsOutput("burnMap", "SpatRaster",
                  "Number of times each pixel has burned. `NA` where not flammable."),
    createsOutput("burnSummary", "data.table",
                  "One row per fire: `igLoc` (ignition pixel), `N` (pixels burned), `year`, `areaBurnedHa`."),
    createsOutput("rstAnnualBurnID", "SpatRaster",
                  "Fire ID of each pixel burned this year; `NA` elsewhere."),
    createsOutput("rstCurrentBurn", "SpatRaster",
                  "1 where burned this year; `NA` elsewhere.")
  )
))

#' Event dispatcher
#'
#' `init` creates `burnMap` and schedules the first `burn`; `burn` spreads this
#' year's escaped fires and reschedules itself.
#'
#' @param sim A `simList`.
#' @param eventTime Time of the event.
#' @param eventType `"init"` or `"burn"`.
#' @param debug Unused.
#'
#' @return The `simList`, invisibly.
doEvent.fireSense_burn = function(sim, eventTime, eventType, debug = FALSE) {
  moduleName <- current(sim)$moduleName

  switch(
    eventType,
    init = {
      ## bail early if there's a problem with ignition, escape, or spread rasters

      if (!is.null(sim$fireSense_SpreadPredicted))
        stopifnot(length(na.omit(sim$fireSense_SpreadPredicted[])) > 0)

      ## trying to avoid the raster warning no non-missing arguments to max
      sim$burnMap <- rast(sim$rasterToMatch)
      sim$rstCurrentBurn <- rast(sim$rasterToMatch)
      
      burnVals <- as.vector(sim$flammableRTM)
      sim$burnMap[burnVals == 0] <- NA
      sim$burnMap[burnVals == 1] <- 0
      rm(burnVals)
      gc()

      sim <- scheduleEvent(sim, eventTime = P(sim)$.runInitialTime, moduleName, "burn", 
                           eventPriority = 5.13)
    },
    burn = {
      sim <- burn(sim)

      if (!is.na(P(sim)$.runInterval))
        sim <- scheduleEvent(sim, time(sim) + P(sim)$.runInterval, moduleName, "burn", 
                             eventPriority = 5.13)
    },
    warning(paste("Undefined event type: '", current(sim)[1, "eventType", with = FALSE],
                  "' in module '", current(sim)[1, "moduleName", with = FALSE], "'", sep = ""))
  )
  invisible(sim)
}

#' Spread this year's escaped fires
#'
#' Spreads fires with `SpaDES.tools::spreadCpp()` from every pixel in
#' `sim$ignitionsAndEscapes` with `escapes > 0`, then updates the burn outputs.
#' Does nothing if there are no escapes.
#'
#' @param sim A `simList`.
#'
#' @return The `simList`, invisibly, with `burnDT`, `burnMap`, `burnSummary`,
#'   `rstAnnualBurnID` and `rstCurrentBurn` updated.
burn <- function(sim) {

  ## This year's burn starts empty (NA; burned pixels become 1), before any early return: a year
  ## without fire must not keep last year's pixels. CBM_dataPrep reads `rstCurrentBurn` every year as
  ## disturbance events, so a stale raster would burn the same pixels again.
  tmpl <- if (!is.null(sim$fireSense_SpreadPredicted)) sim$fireSense_SpreadPredicted else sim$rasterToMatch
  sim$rstCurrentBurn <- rast(tmpl)
  sim$rstAnnualBurnID <- rast(tmpl)

  ig <- sim$ignitionsAndEscapes
  if (NROW(ig) == 0L || !"fireSense_spreadPredict" %in% P(sim)$whichModulesToPrepare)
    return(invisible(sim))
  if (!"escaped" %in% names(ig))
    stop("ignitionsAndEscapes needs the column `escaped`, which ignitions escaped ",
         "(fireSense_ignitionPredict >= 1.0.0.9003). Its `escapes` is a coarse pixel's count, repeated ",
         "on each of that pixel's ignitions, so it cannot say which fires to spread.")

  ## this year's spread probability, with the year's random effect if the fit has one
  spreadProbYear <- yearSpreadProb(sim$fireSense_SpreadPredicted, sim$fireSense_SpreadSD)

  ## One fire per escaped ignition, spread with spreadCpp(), the spread the fit uses (fireSenseUtils'
  ## objective), so a forecast spreads fires as the fitted parameters assume: an escaped fire burns its
  ## first escapeSizeHa whatever the spread probability, then spreads. Several fires starting on one
  ## pixel are one fire: the first start burns the pixel and the others cannot.
  escLocs <- ig$pixelID[ig$escaped %in% TRUE]
  minPx <- if (length(Par$escapeSizeHa) && !is.na(Par$escapeSizeHa))
    fireSenseUtils::escapeSizePixels(Par$escapeSizeHa, sim$fireSense_SpreadPredicted) else 0L
  spreadState <- data.table(initialPixels = integer(), pixels = integer())
  if (length(escLocs)) {
    ss <- SpaDES.tools::spreadCpp(landscape = sim$fireSense_SpreadPredicted, loci = escLocs,
                                  spreadProb = spreadProbYear, directions = 8L, minSize = minPx,
                                  jumpTries = Par$jumpTries, jumpMeanDist = Par$jumpMeanDist)
    spreadState <- data.table(initialPixels = ss$initialLocus, pixels = ss$indices)
  }
  ## the ignitions that did not escape: a small patch each, sized from the observed small fires
  spreadState <- rbind(spreadState, smallFires(
    loci = ig$pixelID[!ig$escaped %in% TRUE], sizesHa = sim$nonEscapedFireSizesHa,
    landscape = sim$fireSense_SpreadPredicted, spreadProb = spreadProbYear, burned = spreadState$pixels))
  if (NROW(spreadState) == 0L) return(invisible(sim))

  spreadState[ , fire_id := .GRP, by = "initialPixels"] # Add an fire_id column
  sim$rstAnnualBurnID[spreadState$pixels] <- spreadState$fire_id
  sim$rstCurrentBurn[spreadState$pixels] <- 1
  sim$burnMap[spreadState$pixels] <- sim$burnMap[spreadState$pixels] + 1
  par("pin" = pmax(par()$pin, 0)) # not sure why par$pin is negative
  if ((time(sim) - start(sim) ) %% P(sim)$.plotInterval < 1) {
    Plots(c(sim$rstAnnualBurnID |> setNames(paste0("Annual Fire IDs ", time(sim))),
            sim$burnMap |> setNames(paste0("Cumulative Burn Map ", time(sim))),
            sim$fireSense_SpreadPredicted |> setNames(paste0("Spread Probability Map ", time(sim)))),
          types = Par$.plots, filename = paste0("Annual Fire Maps ", time(sim)),
          deviceArgs = list(width = 10, height = 8, units = "in", res = 144))
  }

  #get fire year, pixels burned, area burned, poly ID of all burned pixels
  # Make burnSummary --> similar to SCFM
  sim$burnDT <- spreadState

  tempDT <- sim$burnDT[, .(.N), by = "initialPixels"]
  tempDT$year <- time(sim)
  tempDT$areaBurnedHa <- tempDT$N * prod(res(sim$fireSense_SpreadPredicted)) * 1e-4
  setnames(tempDT, c("initialPixels"), c("igLoc"))
  sim$burnSummary <- rbind(sim$burnSummary, tempDT)

  invisible(sim)
}

#' Small fires for the ignitions that did not escape
#'
#' Each ignition gets a size drawn from `sizesHa` (the observed fires below `escapeSizeHa`), turned into
#' pixels with the expected area kept (a 2.5-pixel fire is 2 pixels half the time, 3 the other half), and
#' burns that many burnable pixels around it. Pixels already burned this year, and pixels with no spread
#' probability, do not burn. Fires of 0 pixels, and ignitions on such pixels, burn nothing.
#'
#' @param loci Ignition pixels (cell numbers of `landscape`).
#' @param sizesHa Numeric vector of fire sizes (ha) to draw from; `NULL` or empty: nothing burns.
#' @param landscape `SpatRaster` giving the grid and pixel size.
#' @param spreadProb Numeric vector, one per pixel: `NA` or 0 is not burnable.
#' @param burned Pixels already burned this year.
#' @return A `data.table` with `initialPixels` and `pixels`, one row per burned pixel.
smallFires <- function(loci, sizesHa, landscape, spreadProb, burned = integer()) {
  none <- data.table(initialPixels = integer(), pixels = integer())
  if (!length(loci) || !length(sizesHa)) return(none)
  pixHa <- prod(res(landscape)) / 1e4
  s <- sizesHa[sample.int(length(sizesHa), length(loci), replace = TRUE)] / pixHa
  px <- as.integer(floor(s) + (stats::runif(length(s)) < s - floor(s)))
  burnable <- !is.na(spreadProb) & spreadProb > 0
  burnable[burned] <- FALSE
  keep <- px >= 1L & burnable[loci] & !duplicated(loci)
  if (!any(keep)) return(none)
  ss <- SpaDES.tools::spreadCpp(landscape = landscape, loci = loci[keep], spreadProb = as.numeric(burnable),
                                maxSize = px[keep], directions = 8L)
  data.table(initialPixels = ss$initialLocus, pixels = ss$indices)
}

#' This year's spread probability, with the per-year random effect
#'
#' The fit (`fireSenseUtils::.objfunSpreadFit()` with `yearSpreadSD`) gives each year one eps on logit
#' spread probability, shared by all that year's fires. Here each year draws z ~ N(0, 1) and uses
#' plogis(qlogis(p) + z * sd). With a raster `sd` (several ELFs, each with its own fitted sd) the ELFs
#' share the year's z, each scaled by its own sd.
#'
#' @param spreadProbRas `SpatRaster` of spread probability.
#' @param sd `NULL`, one number, or a `SpatRaster` aligned with `spreadProbRas`.
#' @return Numeric vector of spread probability, one per pixel.
yearSpreadProb <- function(spreadProbRas, sd) {
  p <- terra::values(spreadProbRas, mat = FALSE)
  if (is.null(sd)) return(p)
  s <- if (inherits(sd, "SpatRaster")) terra::values(sd, mat = FALSE) else rep_len(sd, length(p))
  s[is.na(s)] <- 0
  if (!any(s > 0)) return(p)
  z <- stats::rnorm(1)
  stats::plogis(stats::qlogis(p) + z * s)
}

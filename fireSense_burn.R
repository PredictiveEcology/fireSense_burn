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
  version = numeric_version("2.2.0.9014"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list("citation.bib"),
  documentation = list("README.md", "fireSense_burn.Rmd"), ## same file
  reqdPkgs = list("data.table", "httr2", "PredictiveEcology/SpaDES.core@development (>= 3.0.4)",
                  "PredictiveEcology/fireSenseUtils@development (>= 0.2.3.9158)", # 9138: powerLawShape
                  "ggplot2", "ggspatial", "PredictiveEcology/reproducible@development",
                  "PredictiveEcology/SpaDES.tools@development (>= 2.2.0.9003)", "terra"),
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
    defineParameter("escapeSizeHa", "numeric", fireSenseUtils::fireSenseEscapeSizeHa, 0, NA,
                    paste("Size (ha) of the whole fire polygon at and above which a fire escaped: the definition of the fit",
                          "(`fireSenseUtils::escapeDefinition()`). Each escaped fire burns this area first, whatever its",
                          "spread probability, then spreads normally. Must equal the `escapeSizeHa` of every other module in",
                          "the simList (an error otherwise) and of the fit (`fireSense_EscapeDefinition`, an error otherwise).",
                          "`NA` spreads escaped fires from their ignition pixel only, with no escape definition.")),
    defineParameter("fireCauses", "character", fireSenseUtils::fireSenseFireCauses, NA, NA,
                    paste("The fire cause groups of the escape definition, as in `fireSense_dataPrepFit` (which must agree:",
                          "an error otherwise; so must the fit, `fireSense_EscapeDefinition`). Also the causes whose observed",
                          "sizes the ignitions that do not escape draw from, when `.inputObjects` makes `nonEscapedFireSizesHa`.")),
    defineParameter("fireYears", "integer", fireSenseUtils::defaultFireYears(), NA, NA,
                    paste("As in `fireSense_dataPrepFit`: the years of those observed fires, when `.inputObjects`",
                          "makes `nonEscapedFireSizesHa`.")),
    defineParameter("ignitionSource", "character", "predicted", NA, NA,
                    paste("Where each year's fires start. `\"predicted\"`: ignitions and escapes are drawn from",
                          "`fireSense_IgAndEscapeProbRas`. `\"observedEscapes\"` (for hindcasts that test spread alone):",
                          "the year's observed escapes in `firePolys` (the escape definition, year `floor(time(sim))`) are spread",
                          "from the snapped centroids of their polygons, the starts of the spread fit",
                          "(`fireSenseUtils::escapeFireSet()`), and nothing is drawn from the predicted surfaces.",
                          "Either way a fire starts only in the core of `rasterToMatchLargeELF`; it still spreads into the buffer.")),
    defineParameter("jumpTries", "integer", 20L, 0L, NA,
                    paste("Passed to `SpaDES.tools::spreadCpp()` for escaped fires: attempts to jump for a fire",
                          "still under `escapeSizeHa` that has nowhere left to spread. Default 20, as fireSense_spreadFit fits",
                          "with; 0 is off.")),
    defineParameter("jumpMeanDist", "numeric", 3, 0, NA,
                    "Passed to `SpaDES.tools::spreadCpp()`: mean jump distance, in cells."),
    defineParameter("whichModulesToPrepare", "character",
                    default = c("fireSense_spreadPredict", "fireSense_ignitionPredict"),
                    NA, NA,
                    "Fires spread only if this includes `fireSense_spreadPredict`. Other values are ignored.")
  ),
  inputObjects = rbind(
    expectsInput("fireSense_SpreadPredicted", "SpatRaster",
                 "Per-pixel spread probability for the current year."),
    expectsInput("fireSense_SpreadSD", "SpatRaster|numeric",
                 paste("Sd of the per-year random effect (on logit spread probability; on x with `fireSense_SpreadPowerLaw`), as fitted by",
                       "fireSense_spreadFit (`yearSpreadSD`): a raster aligned with `fireSense_SpreadPredicted`",
                       "(from fireSense_spreadPredict, per ELF) or one number. Each year draws one z ~ N(0, 1), independent of the",
                       "z that scales that year's ignitions and escapes (`fireSense_IgAndEscapeProbRas`); all of that",
                       "year's fires spread with plogis(qlogis(p) + z * sd). NULL or 0: no effect.")),
    expectsInput("fireSense_SpreadLink", "character",
                 paste("From fireSense_spreadPredict, only for a fit made with `spreadLink = \"powerLaw\"`, `\"powerLawSmooth\"` or",
                       "`\"richards\"`: the link the ledger row records, which `fireSense_SpreadPowerLaw` holds the parameters of.",
                       "NULL with `fireSense_SpreadPowerLaw`: \"powerLaw\" (spreadPredict before it had the others).")),
    expectsInput("fireSense_SpreadPowerLaw", "SpatRaster|numeric",
                 paste("From fireSense_spreadPredict, only for a fit made with `spreadLink = \"powerLaw\"`, `\"powerLawSmooth\"` or",
                       "`\"richards\"`: the parameters of the link `fireSense_SpreadLink`, named as",
                       "`fireSenseUtils::spreadLinkParNames` says (\"powerLaw\": `pc`, `gamma`, `floor` and `shape`, 1 if absent, of",
                       "`fireSenseUtils::powerLawLink()`; \"powerLawSmooth\" also `lower`; \"richards\": `pc`, `lower`, `nu`, `B`), as a",
                       "numeric vector with these names (one ELF) or a",
                       "raster aligned with `fireSense_SpreadPredicted`. The year effect is then added to the linear",
                       "predictor x, as in the fit: p = link(x + z * sd) (`fireSenseUtils::linearLinkProb()`), with x from",
                       "`fireSense_SpreadLinear`. NULL: the effect is added on the logit.")),
    expectsInput("fireSense_SpreadLinear", "SpatRaster",
                 paste("From fireSense_spreadPredict, only for a fit made with `spreadLink = \"powerLaw\"`: the linear",
                       "predictor x of each flammable pixel, aligned with `fireSense_SpreadPredicted`. Required whenever",
                       "`fireSense_SpreadPowerLaw` is set and the year effect is above 0: the power law clips a pixel with a low x",
                       "to p = 0, so x cannot be recovered from p, yet the fit adds the year effect to x of every pixel.")),
    expectsInput("flammableRTM", "SpatRaster", 
                 "Binary SpatRaster (1 = flammable, 0 = not). Non-flammable pixels are `NA` in `burnMap`."),
    expectsInput("fireSense_IgAndEscapeProbRas", "SpatRaster",
                 paste("Two layers at the resolution of `ignitionFitRTM`, from fireSense_ignitionPredict:",
                       "`ignitionProb`, the expected ignitions per pixel and year, and `escapeProb`, the expected",
                       "escapes per pixel and year given an ignition. Ignitions and escapes are drawn from these each year.",
                       "Optional layers `ignitionYearSD` and `escapeYearSD`: the sd of the year effect of each; a year",
                       "multiplies the means by exp(sd * z - sd^2 / 2), with the year's z, which spread does not share.",
                       "Absent or 0: no year effect.")),
    expectsInput("fireSense_IgAndEscapeDistribution", "list",
                 paste("`list(ignition = , escape = )`, from fireSense_ignitionPredict: the objective the ignition and",
                       "escape models were fitted with. Only `\"count:poisson\"` can be drawn from.")),
    expectsInput("firePolys", "list",
                 paste("Only with `ignitionSource = \"observedEscapes\"`: the annual fire polygons (`YEAR`, `POLY_HA`,",
                       "`FIRECAUS`), as in fireSense_dataPrepFit.")),
    expectsInput("fireSense_SpreadFireSD", "SpatRaster|numeric",
                 paste("From fireSense_spreadPredict: the sd of the per-fire random effect on the linear predictor x of a",
                       "spread fit made with `spreadLink = \"powerLaw\"`, `\"powerLawSmooth\"` or `\"richards\"` (`fireSpreadSD`), a raster aligned with",
                       "`fireSense_SpreadPredicted` (per ELF) or one number. Above 0, each fire spreads with its own",
                       "offset ~ N(0, sd) on x, with the link parameters of its pixel (`SpaDES.tools::spreadCpp(link =)`),",
                       "which needs `fireSense_SpreadPowerLaw` and `fireSense_SpreadLinear`. NULL or 0: no effect, and the",
                       "spread is that of earlier versions.")),
    expectsInput("fireSense_EscapeDefinition", "data.frame",
                 paste("From fireSense_spreadPredict: the escape definition (`escapeSizeHa`, `fireCauses`) of each fitted",
                       "ELF (one row each, with `polygonID`). Every row that is not `NA` must equal this module's",
                       "`escapeSizeHa` and `fireCauses` (an error otherwise). `NA` rows (fits made before the definition was",
                       "recorded) and NULL are not checked.")),
    expectsInput("rasterToMatchLargeELF", "SpatRaster",
                 paste("From fireSense_ELFs. Fires start only in its core: the cells with `fireSenseUtils::fireSenseELFCoreValue`",
                       "(2; the buffer is 1) of a one-ELF raster, every labelled cell of a multi-ELF (categorical) raster, which",
                       "has no buffer. The fires spread into the buffer. NULL: a fire may start anywhere.")),
    expectsInput("ignitionFitRTM", "SpatRaster",
                 "The coarse raster the ignition and escape models were fitted on (from fireSense_dataPrepFit)."),
    expectsInput("nonEscapedFireSizesHa", "numeric",
                 paste("Sizes (ha) of the study area's observed fires below `escapeSizeHa`, from",
                       "fireSense_dataPrepFit. Each ignition that did not escape burns a patch of a size drawn",
                       "from these. Unsupplied, with a `studyArea` (a run without fireSense_dataPrepFit), `.inputObjects`",
                       "makes them the same way, from the NFDB fires of `fireCauses` in `fireYears`. `NULL`: ignitions",
                       "that did not escape burn nothing.")),
    expectsInput("studyArea", "SpatVector",
                 "Only for making `nonEscapedFireSizesHa`: the study area whose NFDB fires give the sizes."),
    expectsInput("rasterToMatch", "SpatRaster", sourceURL = NA,
                 "Template raster for the study area, ideally buffered to limit fire edge effects.")
  ),
  outputObjects = rbind(
    createsOutput("ignitionsAndEscapes", "data.table",
                  paste("This year's ignitions, one row per ignited pixel, in random order: `pixelID` (cell index of",
                        "`flammableRTM`), `igProb`, `ignitions`, `escapeProb`, `escapes` of the coarse pixel it was drawn",
                        "from, and `escaped`, whether this ignition escaped: exactly `escapes` of a coarse pixel's rows",
                        "are TRUE. Drawn each year from `fireSense_IgAndEscapeProbRas`; without that raster a supplied",
                        "`ignitionsAndEscapes` is used as it is. With `ignitionSource = \"observedEscapes\"`: the",
                        "year's observed escapes, with only `pixelID` and `escaped` (all TRUE).")),
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
      if (!P(sim)$ignitionSource %in% c("predicted", "observedEscapes"))
        stop("fireSense_burn: ignitionSource must be \"predicted\" or \"observedEscapes\"")
      if (identical(P(sim)$ignitionSource, "observedEscapes") &&
          is.null(sim$firePolys))
        stop("fireSense_burn: ignitionSource = \"observedEscapes\" needs `firePolys`")
      fireSenseUtils::escapeDefinitionOf(sim)

      ## trying to avoid the raster warning no non-missing arguments to max
      sim$burnMap <- rast(sim$rasterToMatch)
      sim$rstCurrentBurn <- emptyBurnRaster(sim$rasterToMatch)
      
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

#' An empty burn raster
#'
#' A raster on the grid of `template` with every pixel `NA`. It has cell values, unlike `rast(template)`,
#' so `terra::writeRaster()` accepts it in a year without fire.
#'
#' @param template A `SpatRaster`.
#'
#' @return A `SpatRaster`.
emptyBurnRaster <- function(template) rast(template, vals = NA)

#' Draw this year's ignitions and escapes, then spread this year's escaped fires
#'
#' Draws the year's z for ignitions and escapes (`yearZ()`), each its own draw as spread's is, and the ignitions and escapes
#' (`drawIgnitionsAndEscapes()`), then spreads fires with `SpaDES.tools::spreadCpp()` from every pixel in
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
  sim$rstCurrentBurn <- emptyBurnRaster(tmpl)
  sim$rstAnnualBurnID <- emptyBurnRaster(tmpl)

  ## Every random draw of ignitions and escapes is made here, from the surfaces fireSense_ignitionPredict
  ## predicts. Without the surface, a supplied `ignitionsAndEscapes` is spread as it is.
  ## The year's z for ignitions and for escapes, one independent draw each per burn event. NULL when their fits
  ## have no year effect. Spread draws its own z in yearSpreadProb() below. Drought already enters every model as a
  ## covariate, so the random year effect is what is left after climate, and nothing says that a year with many
  ## ignitions is a year in which each ignition escapes more often, or spreads hard: in the fit data the escape
  ## model's year residual is uncorrelated with the ignition model's (r = -0.001). Escapes are drawn only where an
  ## ignition fell, so a shared z multiplied the two: escapes were inflated by exp(ignitionYearSD * escapeYearSD),
  ## and sharing spread's z burned about twice the area.
  ## With ignitionSource = "observedEscapes" the year's observed escapes are spread instead and nothing is drawn,
  ## so a hindcast tests spread alone.
  definition <- fireSenseUtils::escapeDefinitionOf(sim)
  fireSenseUtils::checkEscapeDefinition(sim$fireSense_EscapeDefinition, definition, "fireSense_spreadPredict's fit")
  if (identical(Par$ignitionSource, "observedEscapes")) {
    ## the starts of the year's observed escapes: the spread fit's, found once (all years) and kept in `mod`
    if (is.null(mod$observedStarts))
      mod$observedStarts <- observedEscapeStarts(sim$firePolys, sim$flammableRTM, definition)
    sim$ignitionsAndEscapes <- observedEscapes(mod$observedStarts, floor(time(sim) + 1e-9))
  } else {
    z <- yearZ(sim$fireSense_IgAndEscapeProbRas)
    if (!is.null(sim$fireSense_IgAndEscapeProbRas))
      sim$ignitionsAndEscapes <- drawIgnitionsAndEscapes(sim, store = mod, z = z)
  }

  ## A fire starts only in the core (the buffer removes edge effects, it has no fires of its own): the ignition
  ## surfaces stay complete, only the starts are dropped. The fire spreads into the buffer from a core start.
  ig <- sim$ignitionsAndEscapes
  if (!is.null(sim$rasterToMatchLargeELF) && NROW(ig))
    ig <- ig[fireSenseUtils::inELFCore(ig$pixelID, sim$rasterToMatchLargeELF), ]
  if (NROW(ig) == 0L || !"fireSense_spreadPredict" %in% P(sim)$whichModulesToPrepare)
    return(invisible(sim))
  if (!"escaped" %in% names(ig))
    stop("ignitionsAndEscapes needs the column `escaped`, which ignitions escaped ",
         "(fireSense_ignitionPredict >= 1.0.0.9003). Its `escapes` is a coarse pixel's count, repeated ",
         "on each of that pixel's ignitions, so it cannot say which fires to spread.")

  ## this year's spread probability, with the year's random effect if the fit has one. With a per-fire effect
  ## (fireSense_SpreadFireSD above 0) the fires spread on the linear predictor, each with its own offset
  ## (`linkedSpread()`); `spreadProbYear` is then the probability without the per-fire offset, for `smallFires()`.
  fireSD <- cellValues(sim$fireSense_SpreadFireSD, terra::ncell(sim$fireSense_SpreadPredicted))
  perFire <- any(fireSD > 0)
  linked <- if (perFire) linkedSpread(sim$fireSense_SpreadSD, sim$fireSense_SpreadPowerLaw, sim$fireSense_SpreadLinear,
                                      link = sim$fireSense_SpreadLink)
  spreadProbYear <- if (perFire) linked$prob else
    yearSpreadProb(sim$fireSense_SpreadPredicted, sim$fireSense_SpreadSD, sim$fireSense_SpreadPowerLaw,
                   linear = sim$fireSense_SpreadLinear, link = sim$fireSense_SpreadLink)

  ## One fire per escaped ignition, spread with spreadCpp(), the spread the fit uses (fireSenseUtils'
  ## objective), so a forecast spreads fires as the fitted parameters assume: an escaped fire burns its
  ## first escapeSizeHa whatever the spread probability, then spreads. Several fires starting on one
  ## pixel are one fire: the first start burns the pixel and the others cannot.
  escLocs <- unique(ig$pixelID[ig$escaped %in% TRUE])
  minPx <- if (length(Par$escapeSizeHa) && !is.na(Par$escapeSizeHa))
    fireSenseUtils::escapeSizePixels(Par$escapeSizeHa, sim$fireSense_SpreadPredicted) else 0L
  spreadState <- data.table(initialPixels = integer(), pixels = integer())
  if (length(escLocs)) {
    args <- list(landscape = sim$fireSense_SpreadPredicted, loci = escLocs, directions = 8L, minSize = minPx,
                 jumpTries = Par$jumpTries, jumpMeanDist = Par$jumpMeanDist)
    args <- c(args, if (perFire) {
      ## each fire's own offset: N(0, sd of the ELF its start pixel is in), on top of the year's effect in x
      list(spreadProb = linked$linear, link = linked$link, linkPars = linked$pars,
           linkOffset = stats::rnorm(length(escLocs)) * fireSD[escLocs])
    } else list(spreadProb = spreadProbYear))
    ss <- do.call(SpaDES.tools::spreadCpp, args)
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

#' Draw a count from its fitted distribution
#'
#' The only family drawn from is the Poisson (`"count:poisson"`, as both the ignition and the escape models
#' are fitted). Another objective, e.g. `"reg:tweedie"`, would need a dispersion the fit does not pass on.
#'
#' @param objective The model objective, from `fireSense_IgAndEscapeDistribution`.
#' @param mean Numeric vector of expected counts; `NA` is 0.
#' @param what `"ignition"` or `"escape"`, for the error message.
#'
#' @return An integer vector of counts, one per `mean`.
drawCounts <- function(objective, mean, what) {
  mean[is.na(mean)] <- 0
  checkDrawable(objective, what)
  stats::rpois(length(mean), lambda = mean)
}

## Stops unless `objective` is the one family that can be drawn from (see `drawCounts()`).
checkDrawable <- function(objective, what) {
  if (!identical(objective, fireSenseUtils::ignitionObjectiveTxt))
    stop("fireSense_burn: cannot draw ", what, "s from objective '", objective, "'; only '",
         fireSenseUtils::ignitionObjectiveTxt, "' is supported")
}

#' Draw the escapes of ignited coarse pixels
#'
#' The escape model is fitted on ignited pixel-years only, so its mean `escapeMean` is the expected escapes of a
#' pixel that has at least one ignition. Each ignition escapes with probability
#' `q = escapeMean * (1 - exp(-ignitionMean)) / ignitionMean`, capped at 1, and a pixel's escapes are binomial over
#' its `ignitions`. For Poisson ignitions `(1 - exp(-ignitionMean)) / ignitionMean` is `1 / E[ignitions | ignitions > 0]`,
#' so the expected escapes of an ignited pixel are `escapeMean` (more ignitions, more escapes) and never exceed the
#' ignitions. Drawing `rpois(escapeMean)` and truncating it at the ignitions would lower the mean.
#'
#' @param objective The escape model objective, from `fireSense_IgAndEscapeDistribution$escape`.
#' @param escapeMean Numeric vector of expected escapes of an ignited pixel; `NA` is 0.
#' @param ignitionMean Numeric vector, the mean the pixel's ignitions were drawn from (after the year effect).
#' @param ignitions Integer vector of the pixel's ignitions, each at least 1.
#' @param what `"escape"`, for the error message.
#'
#' @return An integer vector of escapes, one per `ignitions`.
drawEscapes <- function(objective, escapeMean, ignitionMean, ignitions, what) {
  checkDrawable(objective, what)
  escapeMean[is.na(escapeMean)] <- 0
  q <- pmin(1, escapeMean * (-expm1(-ignitionMean)) / ignitionMean)
  stats::rbinom(length(ignitions), size = ignitions, prob = q)
}

#' Draw this year's ignitions and escapes
#'
#' Draws ignitions per coarse pixel from `fireSense_IgAndEscapeDistribution$ignition` with mean `ignitionProb`;
#' for coarse pixels with ignitions, draws escapes from `$escape` with mean `escapeProb`, at most one per ignition
#' (`drawEscapes()`: binomial over the ignitions, so an ignited pixel has `escapeProb` escapes on average).
#' With `z`, both means are first multiplied by the year effect (`fireSenseUtils::yearEffectMultiplier()` with
#' the `ignitionYearSD` and `escapeYearSD` layers), each with its own z and its own sd: a year with a high
#' ignition z does not have a high escape z, nor more spread (spread has its own z, `yearSpreadProb()`).
#' Each ignition is placed in a random flammable `flammableRTM` pixel inside its coarse pixel, and
#' which of a coarse pixel's ignitions escaped is drawn: exactly `escapes` of them.
#'
#' @param sim A `simList`.
#' @param store An environment to keep the coarse-to-fine mapping in (the module's `mod`).
#' @param z The year's z (`yearZ()`: `c(ignition = , escape = )`), or `NULL`: no year effect.
#'
#' @return A `data.table`, one row per ignition, in random order: `pixelID`, `igProb`, `ignitions`,
#'   `escapeProb`, `escapes`, `escaped`. `igProb` and `escapeProb` are the means drawn from, after the year effect.
drawIgnitionsAndEscapes <- function(sim, store, z = NULL) {
  dist <- sim$fireSense_IgAndEscapeDistribution
  if (is.null(dist$ignition) || is.null(dist$escape))
    stop("fireSense_burn: fireSense_IgAndEscapeProbRas needs fireSense_IgAndEscapeDistribution ",
         "(list(ignition = , escape = )) to say how to draw from it")
  ## one row per coarse pixel with an expected ignition count (the others are non-flammable or have no covariates)
  coarse <- data.table(pixelID = seq_len(terra::ncell(sim$fireSense_IgAndEscapeProbRas)),
                       igProb = terra::values(sim$fireSense_IgAndEscapeProbRas[["ignitionProb"]], mat = FALSE),
                       escapeProb = terra::values(sim$fireSense_IgAndEscapeProbRas[["escapeProb"]], mat = FALSE))
  if (!is.null(z)) {
    ## the year's multiplier has mean 1 over z, so the long-run means are kept and stay valid Poisson means
    ras <- sim$fireSense_IgAndEscapeProbRas
    set(coarse, NULL, c("igProb", "escapeProb"),
        list(coarse$igProb * fireSenseUtils::yearEffectMultiplier(yearSDLayer(ras, "ignitionYearSD"), z[["ignition"]]),
             coarse$escapeProb * fireSenseUtils::yearEffectMultiplier(yearSDLayer(ras, "escapeYearSD"), z[["escape"]])))
  }
  coarse <- coarse[!is.na(coarse$igProb), ]
  igns <- drawCounts(dist$ignition, coarse$igProb, "ignition")
  whHasIgns <- which(igns > 0)
  escs <- drawEscapes(dist$escape, coarse$escapeProb[whHasIgns], coarse$igProb[whHasIgns], igns[whHasIgns], "escape")
  set(coarse, NULL, c("ignitions", "escapes"), list(igns, NA_integer_))
  set(coarse, whHasIgns, "escapes", escs)

  ## accounting for spatial resolution of models: ignitions are drawn on the smaller pixels of flammableRTM
  ## The fine-to-coarse cell mapping does not change within a run, so it is computed once (in `store`).
  igRasDT <- fineCoarseTable(coarseToFineMap(sim$ignitionFitRTM, sim$flammableRTM, store = store),
                             sim$flammableRTM)
  # nomatch = NULL --> removes pixels that aren't in `coarse`, which are non flammable
  igs <- igRasDT[coarse, on = c("chunkyPixels" = "pixelID"), nomatch = NULL]
  # use unique because of multiple pixelID per chunkyPixel
  drawTable <- unique(igs[ignitions > 0, .(chunkyPixels, ignitions, escapes)])
  pixelID_igs <- placeIgnitions(igs, drawTable)

  ## `escapes` counts the coarse pixel's escapes and is repeated on each of its ignitions, so which of
  ## them escaped is drawn here: exactly `escapes` of the coarse pixel's rows. Drawn after every pixel
  ## is placed, so the placements do not change.
  if (NROW(pixelID_igs)) {
    pixelID_igs[, escaped := seq_len(.N) %in% sample.int(.N, min(escapes[1], .N)), by = "chunkyPixels"]
  } else {
    set(pixelID_igs, NULL, "escaped", logical(0))
  }
  set(pixelID_igs, NULL, "chunkyPixels", NULL)
  randomOrder <- sample.int(nrow(pixelID_igs)) # sample(1:0) would give 2 rows
  pixelID_igs[randomOrder, ] #Randomize order
}

#' The starts of every observed escape, the spread fit's
#'
#' `fireSenseUtils::escapeFireSet()` with the escape definition (`escapeSizeHa`, `fireCauses`) and `starts = NULL`:
#' each escape polygon's centroid moved to the nearest burnable pixel of the fire, as the spread fit has it, never an
#' NFDB point. Starts in the buffer are dropped later, with those of predicted fires (`fireSenseUtils::inELFCore()`).
#'
#' @param firePolys Annual fire polygons (a list of `SpatVector`s, or one) with `YEAR`, `POLY_HA` and `FIRECAUS`.
#' @param flammableRTM `SpatRaster` of the burnable pixels, core and buffer; its cell numbers are `pixelID`.
#' @param definition The escape definition, from `fireSenseUtils::escapeDefinitionOf()`.
#'
#' @return A `data.table` with `YEAR` and `pixelID`, one row per escape.
observedEscapeStarts <- function(firePolys, flammableRTM, definition) {
  st <- fireSenseUtils::escapeFireSet(firePolys, flammableRTM, definition = definition)
  data.table(YEAR = as.integer(st$YEAR), pixelID = as.integer(st$pixelID))
}

#' A year's observed escapes, as ignitions to spread
#'
#' @param starts The result of `observedEscapeStarts()`.
#' @param year The fire year.
#'
#' @return A `data.table` with `pixelID` and `escaped` (all `TRUE`), one row per escape of `year` with a start.
observedEscapes <- function(starts, year) {
  cells <- starts$pixelID[starts$YEAR == year & !is.na(starts$pixelID)]
  data.table(pixelID = cells, escaped = rep(TRUE, length(cells)))
}

#' A raster's values, or one number, as a vector of `n`; `NA` is 0 and `NULL` is all 0
#'
#' @param x `NULL`, a number or a `SpatRaster` aligned with the landscape.
#' @param n Number of cells.
#' @return A numeric vector of length `n`.
cellValues <- function(x, n) {
  v <- if (is.null(x)) rep(0, n) else if (inherits(x, "SpatRaster")) terra::values(x, mat = FALSE) else rep_len(x, n)
  v[is.na(v)] <- 0
  v
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

#' The year's z, when the ignition or escape fits have a year effect
#'
#' Two independent z ~ N(0, 1) per `burn` event, one for the ignitions and one for the escapes; spread
#' (`yearSpreadProb()`) draws its own third.
#' It is drawn here only when `ignitionYearSD` or `escapeYearSD` is above 0 somewhere; otherwise `NULL`.
#'
#' @param probRas `fireSense_IgAndEscapeProbRas`, or `NULL`.
#' @return `c(ignition = , escape = )`, or `NULL`.
yearZ <- function(probRas) {
  if (is.null(probRas)) return(NULL)
  sds <- intersect(c("ignitionYearSD", "escapeYearSD"), names(probRas))
  if (length(sds) && any(terra::values(probRas[[sds]], mat = FALSE) > 0, na.rm = TRUE))
    c(ignition = stats::rnorm(1), escape = stats::rnorm(1))
}

#' One year-effect sd layer of `fireSense_IgAndEscapeProbRas`, as a vector; 0 where it is absent
#'
#' @param probRas `fireSense_IgAndEscapeProbRas`.
#' @param layer `"ignitionYearSD"` or `"escapeYearSD"`.
#' @return Numeric vector, one per cell.
yearSDLayer <- function(probRas, layer) {
  if (!layer %in% names(probRas)) return(rep(0, terra::ncell(probRas)))
  terra::values(probRas[[layer]], mat = FALSE)
}

#' The year's random effect on every cell
#'
#' eps = z * sd with one z ~ N(0, 1) per call (or `z`). `NULL` when there is no effect: no `sd`, or `sd` 0 everywhere
#' (and then nothing is drawn).
#'
#' @param sd `NULL`, one number, or a `SpatRaster` aligned with the landscape.
#' @param n Number of cells.
#' @param z The year's z; `NULL` draws one.
#' @return A numeric vector of length `n`, or `NULL`.
yearSpreadEps <- function(sd, n, z = NULL) {
  if (is.null(sd)) return(NULL)
  s <- cellValues(sd, n)
  if (!any(s > 0)) return(NULL)
  if (is.null(z)) z <- stats::rnorm(1)
  z * s
}

#' The link parameters of every cell
#'
#' @param powerLaw `fireSense_SpreadPowerLaw`: a numeric vector or `SpatRaster` with the parameters of `link`
#'   (`fireSenseUtils::spreadLinkParNames`); for `"powerLaw"`, `shape` is 1 (`fireSenseUtils::spreadPowerLawShape`) when absent: a
#'   fit made before `shape` existed.
#' @param n Number of cells.
#' @param link `fireSense_SpreadLink`; `NULL` is `"powerLaw"`.
#' @return A numeric matrix, `n` rows and a column per parameter of the link: `pc`, `gamma`, `floor`, `shape` for `"powerLaw"`.
powerLawPars <- function(powerLaw, n, link = NULL) {
  nms <- fireSenseUtils::spreadLinkParNames[[if (is.null(link)) "powerLaw" else link]]
  one <- function(nm) {
    if (nm == "shape" && !"shape" %in% names(powerLaw)) return(rep(fireSenseUtils::spreadPowerLawShape, n))
    if (inherits(powerLaw, "SpatRaster")) terra::values(powerLaw[[nm]], mat = FALSE) else rep_len(powerLaw[[nm]], n)
  }
  matrix(unlist(lapply(nms, one)), ncol = length(nms), dimnames = list(NULL, nms))
}

## The parameters of a cell that cannot burn (no x, or no link parameters): spreadCpp() wants no `NA` in `linkPars`, and
## the cell's `NA` linear predictor already makes it unburnable. Valid for every link (`lower` 0 is within 0 and `floor`/`pc`).
unburnablePars <- c(pc = 0, gamma = 1, floor = 0, shape = 1, lower = 0, nu = 0, B = 1)

## stops unless a power-law fit gave the year effect its linear predictor, which a year effect needs
needsLinear <- function(linear)
  if (is.null(linear))
    stop("fireSense_burn: a power-law or Richards spread fit (fireSense_SpreadPowerLaw) with a year or per-fire effect needs ",
         "fireSense_SpreadLinear, the linear predictor from fireSense_spreadPredict (>= its PR 33). The effect ",
         "cannot be added to x recovered from fireSense_SpreadPredicted: the power law clips low x to p = 0.",
         call. = FALSE)

#' This year's spread probability, with the per-year random effect
#'
#' The fit (`fireSenseUtils::.objfunSpreadFit()` with `yearSpreadSD`) gives each year one eps, shared by all that
#' year's fires. Here each year draws z ~ N(0, 1), independent of
#' the ignitions' and escapes' z (`yearZ()`), and uses eps = z * sd (`yearSpreadEps()`). With a raster `sd` (several
#' ELFs, each with its own fitted sd) the ELFs share the year's z, each scaled by its own sd. Without `powerLaw` eps is
#' added on the logit: plogis(qlogis(p) + eps). With `powerLaw` (a fit with `spreadLink = "powerLaw"`, `"powerLawSmooth"` or
#' `"richards"`) eps is added to the linear predictor x, as in the fit: p is the link
#' (`fireSenseUtils::linearLinkProb()`) of `x + eps` with the pixel's parameters, for every
#' pixel with an x (`linear`). With `"powerLaw"` a flammable pixel with a low x has p of 0 in `spreadProbRas` (the link clips it), so x
#' cannot be recovered from p, and `linear` is required. Pixels without an x (not flammable) keep their p.
#'
#' @param spreadProbRas `SpatRaster` of spread probability.
#' @param sd `NULL`, one number, or a `SpatRaster` aligned with `spreadProbRas`.
#' @param powerLaw `NULL` (logit), or `fireSense_SpreadPowerLaw`: a numeric vector or `SpatRaster` with
#'   `pc`, `gamma`, `floor` and `shape` (1 when absent).
#' @param linear `fireSense_SpreadLinear`: the linear predictor x, a `SpatRaster` aligned with `spreadProbRas`; required
#'   with `powerLaw` (and an `sd` above 0), else the function stops.
#' @param link `fireSense_SpreadLink`: the link `powerLaw` holds the parameters of; `NULL` is `"powerLaw"`.
#' @param z The year's z; `NULL` (what `burn` passes) draws one here.
#' @return Numeric vector of spread probability, one per pixel.
yearSpreadProb <- function(spreadProbRas, sd, powerLaw = NULL, z = NULL, linear = NULL, link = NULL) {
  p <- terra::values(spreadProbRas, mat = FALSE)
  eps <- yearSpreadEps(sd, length(p), z)
  if (is.null(eps)) return(p)
  if (is.null(powerLaw)) return(stats::plogis(stats::qlogis(p) + eps))

  linked <- linkedSpread(sd, powerLaw, linear, eps = eps, link = link)
  ok <- !is.na(linked$linear)
  p[ok] <- linked$prob[ok]
  p
}

#' The year's linear predictor and link parameters, for spreading fires with a per-fire effect
#'
#' With a per-fire effect each fire has its own offset on x (`SpaDES.tools::spreadCpp(link = )`), so the
#' fires spread on x, not on p. The year's effect (`yearSpreadEps()`, one z, as in `yearSpreadProb()`) is added to the
#' x of every cell here, so an `sd` per ELF is each ELF's own; the per-fire offsets are added by `spreadCpp()`.
#' Cells with no x or no link parameters are unburnable (`unburnablePars`, as `spreadCpp()` wants no `NA` rows).
#'
#' @inheritParams yearSpreadProb
#' @param eps The year's effect on every cell; default `yearSpreadEps(sd, <number of cells>)`, which draws a z.
#'   `yearSpreadProb()` passes the one it has drawn.
#' @return A list: `link` (the link's name, for `spreadCpp(link =)`), `linear` (x + eps, `NA` where unburnable), `pars`
#'   (`powerLawPars()` per cell) and `prob` (the probability of each cell without a per-fire offset, `NA` where unburnable).
linkedSpread <- function(sd, powerLaw, linear, eps = yearSpreadEps(sd, length(x)), link = NULL) {
  if (is.null(powerLaw))
    stop("fireSense_burn: a per-fire spread effect (fireSense_SpreadFireSD) needs fireSense_SpreadPowerLaw: it is ",
         "fitted only with spreadLink = \"powerLaw\", \"powerLawSmooth\" or \"richards\"", call. = FALSE)
  needsLinear(linear)
  if (is.null(link)) link <- "powerLaw"
  x <- terra::values(linear, mat = FALSE)
  pars <- powerLawPars(powerLaw, length(x), link)
  if (!is.null(eps)) x <- x + eps
  bad <- is.na(x) | is.na(rowSums(pars))
  x[bad] <- NA
  pars[bad, ] <- rep(unburnablePars[colnames(pars)], each = sum(bad))
  prob <- fireSenseUtils::linearLinkProb(ifelse(bad, 0, x), link, pars)
  prob[bad] <- NA
  list(link = link, linear = x, pars = pars, prob = prob)
}

#' Which coarse cell each fine cell falls in
#'
#' Regridding the coarse ignition raster onto `flammableRTM` ("near", because the cells may not be
#' round multiples) took about 3 s a year at 6.7M cells, and the mapping never changes within a run.
#' It is computed once, from the coarse cell numbers, and kept in `store`; it is rebuilt if the extent,
#' dimensions or crs of either raster change.
#'
#' @param coarse,fine `SpatRaster`s: `ignitionFitRTM` and `flammableRTM`.
#' @param store An environment to keep the mapping in (the module's `mod`).
#'
#' @return A vector with one element per fine cell: its coarse cell number, `NA` outside the coarse raster.
coarseToFineMap <- function(coarse, fine, store) {
  gridKey <- function(r) list(as.vector(terra::ext(r)), dim(r), terra::crs(r))
  key <- list(gridKey(coarse), gridKey(fine))
  if (!is.null(store$coarseToFine) && identical(store$coarseToFine$key, key))
    return(store$coarseToFine$map)

  coarseIds <- rast(coarse)
  coarseIds[] <- seq_len(ncell(coarseIds))
  coarseIds <- postProcess(coarseIds, to = fine, method = "near")
  map <- as.vector(terra::values(coarseIds, mat = FALSE))
  store$coarseToFine <- list(key = key, map = map)
  map
}

#' The fine cells and their coarse cells, for one year
#'
#' @param map The result of `coarseToFineMap()`.
#' @param fine `flammableRTM`: cells not equal to 1 are left out.
#'
#' @return A `data.table` with `pixelID` (fine cell) and `chunkyPixels` (coarse cell).
fineCoarseTable <- function(map, fine) {
  flam <- fine[]
  keep <- which(!is.na(map) & !(!is.na(flam) & flam != 1))
  data.table(pixelID = keep, chunkyPixels = map[keep])
}

#' Place each coarse pixel's ignitions on its fine pixels
#'
#' For each row of `drawTable`, draws `ignitions` of the fine pixels of that coarse pixel and returns
#' their rows of `igs`, in `igs` row order. One `split()` of the candidate rows replaces a scan of all of
#' `igs` for every ignited coarse pixel. The draw is by row (`sample.int()`), so a coarse pixel with a
#' single fine pixel places its ignition on that pixel. A coarse pixel that drew more ignitions than it has
#' fine pixels gets one on each fine pixel and the excess on fine pixels drawn with replacement, so every
#' drawn ignition is placed (one row each) and a `pixelID` can repeat.
#'
#' @param igs `data.table` of fine pixels with `pixelID`, `igProb`, `ignitions`, `escapeProb`, `escapes`
#'   and `chunkyPixels` (the coarse pixel).
#' @param drawTable `data.table` with one row per ignited coarse pixel: `chunkyPixels`, `ignitions`.
#'
#' @return A `data.table` with the `igs` columns `pixelID`, `igProb`, `ignitions`, `escapeProb`,
#'   `escapes`, `chunkyPixels`, for the drawn pixels.
placeIgnitions <- function(igs, drawTable) {
  sel <- which(igs$chunkyPixels %in% drawTable$chunkyPixels)
  rowsByChunk <- split(sel, igs$chunkyPixels[sel])
  cols <- c("pixelID", "igProb", "ignitions", "escapeProb", "escapes", "chunkyPixels")
  out <- vector("list", nrow(drawTable))
  for (i in seq_len(nrow(drawTable))) {
    rows <- rowsByChunk[[as.character(drawTable$chunkyPixels[i])]]
    n <- drawTable$ignitions[i]
    drawn <- rows[sample.int(length(rows), size = min(n, length(rows)))]
    ## more ignitions than fine pixels: every fine pixel has one, the excess goes on random fine pixels
    if (n > length(rows)) drawn <- c(drawn, rows[sample.int(length(rows), size = n - length(rows), replace = TRUE)])
    out[[i]] <- igs[sort(drawn), ..cols]
  }
  ## no ignited coarse pixel: rbindlist(list()) has no columns, so keep the schema of a normal year
  if (!length(out)) return(igs[integer(0), ..cols])
  rbindlist(out)
}

#' Supply default inputs
#'
#' `nonEscapedFireSizesHa`, in a run without `fireSense_dataPrepFit` (which makes it): the sizes of the
#' study area's NFDB fires (of `fireCauses`, in `fireYears`) below `escapeSizeHa`. Without them every
#' ignition that did not escape burned nothing in a run that only predicts. Not without a `studyArea`.
#'
#' @param sim A `simList`.
#'
#' @return The `simList`, invisibly.
.inputObjects <- function(sim) {
  if (!suppliedElsewhere("nonEscapedFireSizesHa", sim) && !is.null(sim$studyArea)) {
    shp <- fireSenseUtils::fireRecordShapefile(fireSenseUtils::nfdbPointUrl(), destinationPath = inputPath(sim))
    pts <- fireSenseUtils::nfdbFirePointsOfCauses(shp, studyArea = sim$studyArea, years = P(sim)$fireYears,
                                                  causes = P(sim)$fireCauses)
    sim$nonEscapedFireSizesHa <- fireSenseUtils::nonEscapedFireSizes(pts, P(sim)$escapeSizeHa)
  }
  invisible(sim)
}

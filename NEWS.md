# fireSense_burn (development version)

- Ignitions and escapes draw independent year effects: `yearZ()` now returns two independent z ~ N(0, 1), `c(ignition = , escape = )`, each scaled by its own model's `ignitionYearSD` or `escapeYearSD`, where one z was shared. Escapes are drawn only where an ignition fell, so the shared z multiplied the two year effects and inflated the expected escapes by `exp(ignitionYearSD * escapeYearSD)` (1.43 for ELF 6.6.1), while in the fit data the two models' year residuals are uncorrelated (r = -0.001). Simulations with a year effect now have fewer escaped fires and burn less area. Without `ignitionYearSD` and `escapeYearSD`, or with 0, nothing changes and a seed reproduces earlier runs exactly.
- New parameter `ignitionSource` (default `"predicted"`, unchanged behaviour). With `"observedEscapes"` each burn event spreads the observed escapes of year `floor(time(sim))` from the new optional input `ignitionFirePoints` (fireSense_dataPrepFit's NFDB natural-cause points): fires of at least `escapeSizeHa` and larger than a pixel (`fireSenseUtils::escapedFires()`), each from the pixel its point falls in, and nothing is drawn from `fireSense_IgAndEscapeProbRas`. Observed fires that did not escape are left out. A hindcast with it tests spread alone (`observedEscapes()`).
- Spread draws its own year effect: `burn` no longer passes the z of the ignitions and escapes (`yearZ()`) to `yearSpreadProb()`, which draws an independent z ~ N(0, 1) per burn event. One shared z made years with many escapes also spread hard, and hindcasts burned 1.7-2 times the area the fit implies, where the fit draws the spread year effect independently of the escapes. Drought already enters every model as a covariate, so the random year effect is what is left after climate and need not be shared. The ignitions' and escapes' random stream is unchanged for a seed; spread's z is now the draw after theirs, so area burned changes in runs with `ignitionYearSD` or `escapeYearSD` above 0 and a spread year effect. Other runs are unchanged. Fits are unaffected.
- `placeIgnitions()` places every drawn ignition: a coarse pixel that drew more ignitions than it has fine pixels gets one on each fine pixel and the excess on fine pixels drawn with replacement (a `pixelID` can repeat, each row its own chance to escape), instead of stopping the run with "cannot take a sample larger than the population". Several escaped ignitions on one pixel are one fire. Runs without such pixels are unchanged.
- `placeIgnitions()` draws a coarse pixel's ignitions by row, not by `sample(pixelID, n)`. A coarse pixel with exactly one fine pixel drew from `1:pixelID`, placing its ignition on an unrelated pixel, which could leave `escapes` `NA` and stop the run with "vector size cannot be NA". Ignition placement, and so results, change in every run with such pixels.
- The year effect is now shared by spread, ignitions and escapes: `burn` draws one `z ~ N(0, 1)` per year (`yearZ()`) and uses it for all three, so a bad spread year is also a bad ignition and escape year. Spread is unchanged (`x + z * yearSpreadSD`, `yearSpreadProb()` now takes `z`). The expected ignitions and escapes of each coarse pixel are multiplied by `fireSenseUtils::yearEffectMultiplier(sd, z) = exp(sd * z - sd^2 / 2)`, which has mean 1, so the long-run means are kept; `sd` comes from the new optional layers `ignitionYearSD` and `escapeYearSD` of `fireSense_IgAndEscapeProbRas` (fireSense_ignitionPredict, from the fits' `yearSD` estimated by fireSense_ignitionFit). Without those layers, or with 0, nothing changes: `z` is then drawn in `yearSpreadProb()` as before, so a seed reproduces earlier runs exactly. Needs fireSenseUtils (>= 0.2.3.9112).
- A fit made with `fireSense_spreadFit`'s `spreadLink = "powerLaw"` adds its year effect to the linear predictor `x`, not to the logit of `p`; `burn` now does the same. New input `fireSense_SpreadPowerLaw` (from `fireSense_spreadPredict`: `pc`, `gamma`, `floor`) lets `yearSpreadProb()` recover `x` from `p`, add `z * sd`, and map back with `fireSenseUtils::powerLawLink()`. Without it (the ceiling and climateOutside links, every earlier run) the year effect is added on the logit exactly as before. Needs fireSenseUtils (>= 0.2.3.9107) and fireSense_spreadPredict's PR 31.
- `drawCounts()` takes the objective it can draw from, `"count:poisson"`, from `fireSenseUtils::ignitionObjectiveTxt` (the objective the ignition and escape models are fitted with) instead of its own copy; same behaviour. Needs fireSenseUtils (>= 0.2.3.9104).
- Breaking: `burn` now draws the ignitions and escapes (it makes `ignitionsAndEscapes`) from `fireSense_IgAndEscapeProbRas` and `fireSense_IgAndEscapeDistribution`, made by `fireSense_ignitionPredict` (>= its PR 33). `placeIgnitions()`, `coarseToFineMap()` and `fineCoarseTable()` moved here from that module. New inputs: those two and `ignitionFitRTM`; `reproducible` is in `reqdPkgs`.
- Ignitions are Poisson draws with mean `ignitionProb`, escapes Poisson with mean `escapeProb`, capped at the ignitions (was `rbinom(ignitions, min(mean, 1))`); other objectives stop. A seed no longer reproduces earlier runs.
- Without `fireSense_IgAndEscapeProbRas`, a supplied `ignitionsAndEscapes` is spread as it is.

- `SpaDES.core` is now in `reqdPkgs` (`scheduleEvent()`, `P()`, `Plots()` are used).
- `rstCurrentBurn` and `rstAnnualBurnID` are now all-`NA` rasters in a year without fire, not grids with no cell values, so `terra::writeRaster()` can save them (`emptyBurnRaster()`).

# fireSense_burn 2.2.0

This release makes the fire simulation behave the way the fitted models assume. Fires now spread with the same method used when fitting, each escaped ignition becomes exactly one fire, and ignitions that do not escape burn a small, realistic area instead of none. Year-to-year variation in fire spread, estimated during fitting, is applied each year. The burn maps start empty every year, so a year without fire no longer shows the previous year's fires.

The module was renamed from `fireSense` to `fireSense_burn`, since `fireSense` is now the parent module for the whole family; projects need to use the new name. Unused settings were removed, and the module is now licensed under GPL-3.

- License: GPL-3.

# fireSense_burn 2.1.0

- Renamed from `fireSense` to `fireSense_burn` (module naming convention `<model>_<camelCaseComponent>`); projects must rename the module and its `params` key. `loadOrder` and the `whichModulesToPrepare` default now name `fireSense_ignitionPredict` and `fireSense_spreadPredict` (renamed from `fireSense_IgnitionPredict` and `fireSense_SpreadPredict`); a project that sets `whichModulesToPrepare` must use the new names. The default no longer lists `fireSense_EscapePredict`, a module that no longer exists (fireSense_ignitionPredict predicts escapes).

- New parameter `.studyAreaName` (default `NA`), the name PredictiveEcology modules use for the study area. This module does not use it yet.
- `rstCurrentBurn` and `rstAnnualBurnID` now start empty in every burn event. In a year with no fire (no
  ignitions, or none escaped and no small fires) `burn()` returned before rebuilding them, so they kept the
  previous fire year's pixels; CBM_dataPrep, which reads `rstCurrentBurn` yearly as disturbance events, would have
  disturbed those pixels again. `burnMap` and `burnSummary` were not affected.
- `jumpTries` defaults to 20, as fireSense_SpreadFit's fit does (>= 1.0.6.9013), so a forecast spreads
  escaped fires the way they were fitted. 0 turns jumping off.
- One fire per escaped ignition. `ignitionsAndEscapes` must have `escaped` (fireSense_IgnitionPredict >=
  1.0.0.9003); `escapes` is a coarse pixel's count repeated on each of its ignitions, and spreading `escapes`
  fires from every row gave, e.g., 8 fires where there were 2 escapes.
- New parameter `escapeSizeHa` (default 50), as in the spread fit: each escaped fire burns its first 50 ha
  whatever its spread probability (`SpaDES.tools::spreadCpp(minSize =)`), then spreads normally. `jumpTries`
  (default 0, off) and `jumpMeanDist` (default 3 cells) pass through to `spreadCpp()` for fires stuck under
  that size.
- New input `nonEscapedFireSizesHa` (from fireSense_dataPrepFit): each ignition that did not escape burns a
  small patch with a size drawn from the study area's observed fires below `escapeSizeHa`. Without it, as
  before, those ignitions burn nothing.
- Needs SpaDES.tools >= 2.1.3.9009 and fireSenseUtils >= 0.2.3.9044. Version 2.0.2.9002.
- New `loadOrder = list(after = c("fireSense_IgnitionPredict", "fireSense_SpreadPredict"))`. Without it, ties in
  event time and priority fall back to a dependency-graph sort that does not always put `burn` after that
  year's ignition and spread predictions. Version 2.0.2.9005.

- Fires spread with `SpaDES.tools::spreadCpp()`, the spread the fit uses (fireSenseUtils' objective), instead
  of `spread2()`, so a forecast spreads fires as the fitted parameters assume. Several escapes on one pixel are one
  fire; `spread2()` stopped with "start has duplicates" at three or more. `burnDT` now holds `initialPixels`,
  `pixels` and `fire_id`.
- New input `fireSense_SpreadSD`, the per-year random effect fitted by fireSense_SpreadFit (`yearSpreadSD`): each
  year draws one z ~ N(0, 1) and every fire that year spreads with plogis(qlogis(p) + z * sd). A seasonal
  departure: a bad year makes every fire bigger. A raster sd (one per ELF) scales the shared z per ELF. `NULL`
  or 0: no effect.


## Breaking changes

- Removed parameters that nothing read: `plotIgnitions`, `.saveInitialTime`, `.saveInterval`. Stop setting them.
- Input `flammableRTM` is now declared `SpatRaster` (was `list`), which is how it was always used.

# fireSense 2.0.2

First release from `development` since `master` was last updated (2022-02-17). Full history: https://github.com/PredictiveEcology/fireSense_burn/compare/504f990...v2.0.2

## Breaking changes

- Removed input `fireSense_EscapePredicted` (RasterLayer).
- Removed input `fireSense_IgnitionPredicted` (data.frame).
- Input `fireSense_SpreadPredicted` is now `SpatRaster` (was `RasterLayer`).
- Output `burnMap` is now `SpatRaster` (was `RasterLayer`).
- Output `rstAnnualBurnID` is now `SpatRaster` (was `RasterLayer`).
- Output `rstCurrentBurn` is now `SpatRaster` (was `RasterLayer`).
- Removed parameter: `.plotInitialTime`.

## New features

- New inputs: `flammableRTM`, `ignitionsAndEscapes`, `rasterToMatch`.
- New parameters: `.plots`, `plotIgnitions`.

## Dependencies

- No longer depends on `raster`.
- Now depends on `terra`.

## Testing

- testthat suite and CI (`testthat-module`), including a snapshot of the module's inputs, outputs and parameters in `tests/testthat/test-metadata.R`.

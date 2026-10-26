---
title: "fireSense_burn Manual"
subtitle: "v.0.0.0.9000"
date: "Last updated: 2026-10-26"
output:
  bookdown::html_document2:
    toc: true
    toc_float: true
    theme: sandstone
    number_sections: false
    df_print: paged
    keep_md: yes
editor_options:
  chunk_output_type: console
  bibliography: citations/references_fireSense_burn.bib
link-citations: true
always_allow_html: true
---

# fireSense_burn Module

<!-- the following are text references used in captions for LaTeX compatibility -->
(ref:fireSense_burn) *fireSense_burn*



[![made-with-Markdown](figures/markdownBadge.png)](https://commonmark.org)

<!-- if knitting to pdf remember to add the pandoc_args: ["--extract-media", "."] option to yml in order to get the badge images -->

#### Authors:

Eliot McIntire <eliot.mcintire@nrcan-rncan.gc.ca> [aut, cre], Jean Marchal <jean.d.marchal@gmail.com> [aut], Alex M. Chubaty <achubaty@for-cast.ca> [ctb]
<!-- ideally separate authors with new lines, '\n' not working -->

## Module Overview

A landscape fire model sensitive to environmental changes (e.g., weather and land cover) [@Marchal:2017a; @Marchal:2017b; @Marchal:2019].

### Module summary

Each year, `fireSense_burn` spreads fires from the pixels where fires escaped, using `SpaDES.tools::spread2()` with the per-pixel spread probabilities in `fireSense_SpreadPredicted`.
Ignitions and escapes are drawn here, each year, from the expected counts `fireSense_ignitionPredict` predicts (`fireSense_IgAndEscapeProbRas`), using the objective of the fitted models (`fireSense_IgAndEscapeDistribution`, only `count:poisson`); escapes are capped at the ignitions. The result is `ignitionsAndEscapes`.
The module records the pixels burned that year, a cumulative burn map, and a per-fire summary of area burned.

### Module inputs and parameters

Table \@ref(tab:moduleInputs-fireSense_burn) shows the full list of module inputs.

<table class="table" style="margin-left: auto; margin-right: auto;">
<caption>(\#tab:moduleInputs-fireSense_burn)(\#tab:moduleInputs-fireSense_burn)List of (ref:fireSense_burn) input objects and their description.</caption>
 <thead>
  <tr>
   <th style="text-align:left;"> objectName </th>
   <th style="text-align:left;"> objectClass </th>
   <th style="text-align:left;"> desc </th>
   <th style="text-align:left;"> sourceURL </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> fireSense_SpreadPredicted </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> Per-pixel spread probability for the current year. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> fireSense_SpreadSD </td>
   <td style="text-align:left;"> SpatRaster&amp;#124;numeric </td>
   <td style="text-align:left;"> Sd of the per-year random effect (on logit spread probability; on x with `fireSense_SpreadPowerLaw`), as fitted by fireSense_spreadFit (`yearSpreadSD`): a raster aligned with `fireSense_SpreadPredicted` (from fireSense_spreadPredict, per ELF) or one number. Each year draws one z ~ N(0, 1), independent of the z that scales that year's ignitions and escapes (`fireSense_IgAndEscapeProbRas`); all of that year's fires spread with plogis(qlogis(p) + z sd). NULL or 0: no effect. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> fireSense_SpreadPowerLaw </td>
   <td style="text-align:left;"> SpatRaster&amp;#124;numeric </td>
   <td style="text-align:left;"> From fireSense_spreadPredict, only for a fit made with `spreadLink = "powerLaw"`: `pc`, `gamma` and `floor` of `fireSenseUtils::powerLawLink()`, as a numeric vector with these names (one ELF) or a 3-layer raster aligned with `fireSense_SpreadPredicted`. The year effect is then added to the linear predictor x, as in the fit: p = powerLawLink(x + z sd), with x recovered from p. NULL: the effect is added on the logit. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> flammableRTM </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> Binary SpatRaster (1 = flammable, 0 = not). Non-flammable pixels are `NA` in `burnMap`. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> fireSense_IgAndEscapeProbRas </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> Two layers at the resolution of `ignitionFitRTM`, from fireSense_ignitionPredict: `ignitionProb`, the expected ignitions per pixel and year, and `escapeProb`, the expected escapes per pixel and year given an ignition. Ignitions and escapes are drawn from these each year. Optional layers `ignitionYearSD` and `escapeYearSD`: the sd of the year effect of each; a year multiplies the means by exp(sd z - sd^2 / 2), with the year's z, which spread does not share. Absent or 0: no year effect. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> fireSense_IgAndEscapeDistribution </td>
   <td style="text-align:left;"> list </td>
   <td style="text-align:left;"> `list(ignition = , escape = )`, from fireSense_ignitionPredict: the objective the ignition and escape models were fitted with. Only `"count:poisson"` can be drawn from. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> ignitionFirePoints </td>
   <td style="text-align:left;"> SpatVector </td>
   <td style="text-align:left;"> Only with `ignitionSource = "observedEscapes"`: observed fire points with columns `YEAR` and `SIZE_HA`, in the CRS of `rasterToMatch` (from fireSense_dataPrepFit: the NFDB natural-cause points). </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> ignitionFitRTM </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> The coarse raster the ignition and escape models were fitted on (from fireSense_dataPrepFit). </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> nonEscapedFireSizesHa </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> Sizes (ha) of the study area's observed fires below `escapeSizeHa`, from fireSense_dataPrepFit. Each ignition that did not escape burns a patch of a size drawn from these. `NULL`: ignitions that did not escape burn nothing. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
  <tr>
   <td style="text-align:left;"> rasterToMatch </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> Template raster for the study area, ideally buffered to limit fire edge effects. </td>
   <td style="text-align:left;"> NA </td>
  </tr>
</tbody>
</table>

Summary of user-visible parameters (Table \@ref(tab:moduleParams-fireSense_burn))


<table class="table" style="margin-left: auto; margin-right: auto;">
<caption>(\#tab:moduleParams-fireSense_burn)(\#tab:moduleParams-fireSense_burn)List of (ref:fireSense_burn) parameters and their description.</caption>
 <thead>
  <tr>
   <th style="text-align:left;"> paramName </th>
   <th style="text-align:left;"> paramClass </th>
   <th style="text-align:left;"> default </th>
   <th style="text-align:left;"> min </th>
   <th style="text-align:left;"> max </th>
   <th style="text-align:left;"> paramDesc </th>
   <th style="text-align:left;"> cacheKey </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> .plots </td>
   <td style="text-align:left;"> characte.... </td>
   <td style="text-align:left;">  </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Passed to `types` in `Plots()`, e.g. "screen", "png". `NULL` or `NA` for no plots. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .plotInterval </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 10 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Years between plots of annual fire IDs, cumulative burns and spread probability. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .runInitialTime </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Time of the first `burn` event. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .runInterval </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 1 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Years between `burn` events. `NA` burns once only. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> .studyAreaName </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Human-readable name for the study area used. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> escapeSizeHa </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 50 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Size (ha) a fire must reach to count as escaped, as in the spread fit: each escaped fire burns this area first, whatever its spread probability, then spreads normally. `NA` spreads escaped fires from their ignition pixel only. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> ignitionSource </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> predicted </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Where each year's fires start. `"predicted"`: ignitions and escapes are drawn from `fireSense_IgAndEscapeProbRas`. `"observedEscapes"` (for hindcasts that test spread alone): the year's observed escapes in `ignitionFirePoints` (fires of at least `escapeSizeHa` and larger than a pixel, of year `floor(time(sim))`) are spread from the pixels of their points, and nothing is drawn from the predicted surfaces. Observed fires that did not escape are left out. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> jumpTries </td>
   <td style="text-align:left;"> integer </td>
   <td style="text-align:left;"> 20 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Passed to `SpaDES.tools::spreadCpp()` for escaped fires: attempts to jump for a fire still under `escapeSizeHa` that has nowhere left to spread. Default 20, as fireSense_spreadFit fits with; 0 is off. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> jumpMeanDist </td>
   <td style="text-align:left;"> numeric </td>
   <td style="text-align:left;"> 3 </td>
   <td style="text-align:left;"> 0 </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Passed to `SpaDES.tools::spreadCpp()`: mean jump distance, in cells. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
  <tr>
   <td style="text-align:left;"> whichModulesToPrepare </td>
   <td style="text-align:left;"> character </td>
   <td style="text-align:left;"> fireSens.... </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> NA </td>
   <td style="text-align:left;"> Fires spread only if this includes `fireSense_spreadPredict`. Other values are ignored. </td>
   <td style="text-align:left;"> TRUE </td>
  </tr>
</tbody>
</table>

### Events

- `init`: creates `burnMap` (0 where flammable, `NA` elsewhere) and schedules the first `burn` at `.runInitialTime`.
- `burn`: draws the year's ignitions and escapes, then spreads fires from every pixel with `escaped`, updates the outputs, and reschedules itself every `.runInterval` years.
  Nothing burns in a year with no escapes, or if `whichModulesToPrepare` does not include `fireSense_spreadPredict`.

### Plotting

Every `.plotInterval` years the `burn` event plots annual fire IDs, the cumulative burn map and the spread probability map, to the devices named in `.plots`.

### Saving

The module saves nothing itself; use the `outputs` argument of `simInit()`.

### Module outputs

Description of the module outputs (Table \@ref(tab:moduleOutputs-fireSense_burn)).

<table class="table" style="margin-left: auto; margin-right: auto;">
<caption>(\#tab:moduleOutputs-fireSense_burn)(\#tab:moduleOutputs-fireSense_burn)List of (ref:fireSense_burn) outputs and their description.</caption>
 <thead>
  <tr>
   <th style="text-align:left;"> objectName </th>
   <th style="text-align:left;"> objectClass </th>
   <th style="text-align:left;"> desc </th>
  </tr>
 </thead>
<tbody>
  <tr>
   <td style="text-align:left;"> ignitionsAndEscapes </td>
   <td style="text-align:left;"> data.table </td>
   <td style="text-align:left;"> This year's ignitions, one row per ignited pixel, in random order: `pixelID` (cell index of `flammableRTM`), `igProb`, `ignitions`, `escapeProb`, `escapes` of the coarse pixel it was drawn from, and `escaped`, whether this ignition escaped: exactly `escapes` of a coarse pixel's rows are TRUE. Drawn each year from `fireSense_IgAndEscapeProbRas`; without that raster a supplied `ignitionsAndEscapes` is used as it is. With `ignitionSource = "observedEscapes"`: the year's observed escapes, with only `pixelID` and `escaped` (all TRUE). </td>
  </tr>
  <tr>
   <td style="text-align:left;"> burnDT </td>
   <td style="text-align:left;"> data.table </td>
   <td style="text-align:left;"> The most recent fire year's burned pixels: `initialPixels` (the fire's ignition pixel), `pixels`, and `fire_id`. </td>
  </tr>
  <tr>
   <td style="text-align:left;"> burnMap </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> Number of times each pixel has burned. `NA` where not flammable. </td>
  </tr>
  <tr>
   <td style="text-align:left;"> burnSummary </td>
   <td style="text-align:left;"> data.table </td>
   <td style="text-align:left;"> One row per fire: `igLoc` (ignition pixel), `N` (pixels burned), `year`, `areaBurnedHa`. </td>
  </tr>
  <tr>
   <td style="text-align:left;"> rstAnnualBurnID </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> Fire ID of each pixel burned this year; `NA` elsewhere. </td>
  </tr>
  <tr>
   <td style="text-align:left;"> rstCurrentBurn </td>
   <td style="text-align:left;"> SpatRaster </td>
   <td style="text-align:left;"> 1 where burned this year; `NA` elsewhere. </td>
  </tr>
</tbody>
</table>

### Usage

`fireSense_burn` needs the objects made by the predict modules, so run it with them:


``` r
library(SpaDES.core)

modules <- list("fireSense_dataPrepPredict", "fireSense_ignitionPredict",
                "fireSense_spreadPredict", "fireSense_burn")

mySim <- simInit(times = list(start = 2011, end = 2100),
                 params = list(fireSense_burn = list(.plots = "png", .plotInterval = 10)),
                 modules = modules,
                 objects = objects, ## fitted fireSense models, rasterToMatch, flammableRTM, etc.
                 paths = list(modulePath = ".."))
spades(mySim)
```

### Links to other modules

- `fireSense_ignitionPredict` supplies `fireSense_IgAndEscapeProbRas` and `fireSense_IgAndEscapeDistribution`.
- `fireSense_spreadPredict` supplies `fireSense_SpreadPredicted`.
- Vegetation modules (e.g. `Biomass_regeneration`) use `rstCurrentBurn`.

### Getting help

- <https://github.com/PredictiveEcology/fireSense_burn/issues>

## References

<!-- autogenerated from bibligraphy -->

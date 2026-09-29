## The module's metadata is its public contract: a project using this module binds
## to these names, classes and defaults. Any removal, rename or retype must fail here.
##
## When a change is deliberate, update this file in the same commit and bump the
## module version to match: removed, renamed or retyped is a MAJOR bump.

md <- SpaDES.core::moduleMetadata(module = moduleName, path = modulePath)

test_that("module metadata parses and names the module", {
  expect_identical(md$name, "fireSense_burn")
  expect_identical(md$timeunit, "year")
  expect_identical(md$childModules, character())
})

test_that("inputs are the expected names and classes", {
  inputs <- stats::setNames(md$inputObjects$objectClass, md$inputObjects$objectName)
  expect_identical(
    inputs[order(names(inputs))],
    c(fireSense_SpreadPredicted = "SpatRaster",
      fireSense_SpreadSD        = "SpatRaster|numeric",
      flammableRTM              = "SpatRaster",
      ignitionsAndEscapes       = "data.table",
      nonEscapedFireSizesHa     = "numeric",
      rasterToMatch             = "SpatRaster")
  )
})

test_that("outputs are the expected names and classes", {
  outputs <- stats::setNames(md$outputObjects$objectClass, md$outputObjects$objectName)
  expect_identical(
    outputs[order(names(outputs))],
    c(burnDT          = "data.table",
      burnMap         = "SpatRaster",
      burnSummary     = "data.table",
      rstAnnualBurnID = "SpatRaster",
      rstCurrentBurn  = "SpatRaster")
  )
})

test_that("parameters are the expected names and classes", {
  classes <- stats::setNames(unlist(md$parameters$paramClass), unlist(md$parameters$paramName))
  expected <- c(.plotInterval         = "numeric",
                .plots                = "character|logical",
                .runInitialTime       = "numeric",
                .runInterval          = "numeric",
                .studyAreaName        = "character",
                escapeSizeHa          = "numeric",
                jumpMeanDist          = "numeric",
                jumpTries             = "integer",
                whichModulesToPrepare = "character")
  expect_identical(classes[order(names(classes))], expected[order(names(expected))])
})

test_that("parameter defaults are unchanged", {
  ## a simInit with no params gives the defaults; `.runInitialTime` defaults to start(sim)
  sim <- runFireSense(data.table::data.table(pixelID = 1L, escapes = 0L, escaped = FALSE),
                      times = list(start = 7, end = 7), doSpades = FALSE)
  p <- SpaDES.core::params(sim)$fireSense_burn
  expect_null(p$.plots)
  expect_identical(p$.plotInterval, 10)
  expect_identical(as.numeric(p$.runInitialTime), 7)
  expect_identical(p$.runInterval, 1)
  expect_identical(p$escapeSizeHa, 50)
  expect_identical(p$jumpTries, 20L)
  expect_identical(p$jumpMeanDist, 3)
  expect_identical(p$whichModulesToPrepare,
                   c("fireSense_spreadPredict", "fireSense_ignitionPredict", "fireSense_EscapePredict"))
})

test_that("every parameter, input and output has a description", {
  expect_false(anyNA(md$parameters$paramDesc))
  expect_true(all(nzchar(unlist(md$parameters$paramDesc))))
  expect_true(all(nzchar(md$inputObjects$desc)))
  expect_true(all(nzchar(md$outputObjects$desc)))
})

test_that("required packages are unchanged", {
  expect_setequal(unlist(md$reqdPkgs), c("data.table", "PredictiveEcology/fireSenseUtils@development (>= 0.2.3.9044)",
                                         "ggplot2", "ggspatial",
                                         "PredictiveEcology/SpaDES.tools@development (>= 2.1.3.9009)", "terra"))
})

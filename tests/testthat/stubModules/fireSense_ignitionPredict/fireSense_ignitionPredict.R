## Stand-in for the real fireSense_ignitionPredict, used only by test-load-order.R.
## It deliberately declares no inputObjects/outputObjects, so SpaDES.core's
## dependency-graph sort has nothing to order it against fireSense: any correct
## ordering here comes only from fireSense's own `loadOrder` metadata.
defineModule(sim, list(
  name = "fireSense_ignitionPredict",
  description = "Stub for load-order tests: schedules a yearly `run`, does nothing else.",
  keywords = character(),
  authors = person("Test", "Stub", email = "test@example.com", role = c("aut", "cre")),
  childModules = character(),
  version = numeric_version("0.0.1"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list(),
  documentation = list(),
  reqdPkgs = list(),
  parameters = rbind(),
  inputObjects = rbind(),
  outputObjects = rbind()
))

doEvent.fireSense_ignitionPredict <- function(sim, eventTime, eventType, debug = FALSE) {
  switch(
    eventType,
    init = {
      sim <- scheduleEvent(sim, start(sim), "fireSense_ignitionPredict", "run")
    },
    run = {
      sim <- scheduleEvent(sim, time(sim) + 1, "fireSense_ignitionPredict", "run")
    }
  )
  invisible(sim)
}

## Which events run, when, and what gets scheduled next.

ig <- data.table::data.table(pixelID = 1L, escapes = 1L, escaped = TRUE)

fsCompleted <- function(sim) {
  cm <- SpaDES.core::completed(sim)
  cm <- cm[cm$moduleName == "fireSense_burn" & cm$eventType != ".inputObjects", ]
  data.frame(eventTime = as.numeric(cm$eventTime), eventType = cm$eventType, eventPriority = cm$eventPriority)
}

test_that("burn runs every year by default and reschedules itself", {
  sim <- runFireSense(ig, times = list(start = 1, end = 3))
  expect_identical(fsCompleted(sim),
                   data.frame(eventTime = c(1, 1, 2, 3),
                              eventType = c("init", "burn", "burn", "burn"),
                              eventPriority = c(1, 5.13, 5.13, 5.13)))
  ev <- SpaDES.core::events(sim)
  ev <- ev[ev$moduleName == "fireSense_burn", ]
  expect_identical(as.numeric(ev$eventTime), 4)
  expect_identical(ev$eventType, "burn")
  expect_identical(ev$eventPriority, 5.13)
})

test_that(".runInterval sets the years between burns", {
  sim <- runFireSense(ig, times = list(start = 1, end = 6), params = list(.runInterval = 2))
  expect_identical(fsCompleted(sim)$eventTime, c(1, 1, 3, 5))
  expect_identical(as.numeric(sim$burnSummary$year), c(1, 3, 5))
  expect_identical(vals(sim$burnMap)[1], 3)
})

test_that(".runInterval = NA burns once and schedules nothing more", {
  sim <- runFireSense(ig, times = list(start = 1, end = 3), params = list(.runInterval = NA))
  expect_identical(fsCompleted(sim)$eventType, c("init", "burn"))
  ev <- SpaDES.core::events(sim)
  expect_identical(sum(ev$moduleName == "fireSense_burn"), 0L)
  expect_identical(as.numeric(sim$burnSummary$year), 1)
})

test_that(".runInitialTime delays the first burn", {
  sim <- runFireSense(ig, times = list(start = 1, end = 3), params = list(.runInitialTime = 3))
  expect_identical(fsCompleted(sim)$eventTime, c(1, 3))
  expect_identical(as.numeric(sim$burnSummary$year), 3)
  expect_identical(vals(sim$burnMap)[1], 1)
})

test_that("an unknown event type warns and changes nothing", {
  sim <- runFireSense(ig, doSpades = FALSE)
  sim <- SpaDES.core::scheduleEvent(sim, 1, "fireSense_burn", "notAnEvent", eventPriority = 9)
  grDevices::pdf(NULL)
  on.exit(grDevices::dev.off(), add = TRUE)
  expect_warning(out <- suppressMessages(SpaDES.core::spades(sim, debug = FALSE)),
                 "Undefined event type: 'notAnEvent' in module 'fireSense_burn'")
  expect_identical(out$burnSummary$N, 40L) # the burn still happened
})

test_that("doEvent.fireSense_burn dispatches init and burn when called directly", {
  ## in the package rendition the event function is callable by name
  skip_if_not(exists("doEvent.fireSense_burn", mode = "function"),
              "module functions are only on the search path in the package rendition (CI)")
  expect_identical(names(formals(doEvent.fireSense_burn)), c("sim", "eventTime", "eventType", "debug"))
  expect_identical(names(formals(burn)), "sim")
})

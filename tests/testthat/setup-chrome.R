# Headless Chrome can take more than chromote's default 10 seconds to open its
# debugging port on a busy CI machine; give it a minute before the Chrome tests
# fail.
withr::local_options(chromote.timeout = 60, .local_envir = testthat::teardown_env())

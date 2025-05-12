# Compare some different approaches to parallelization in R with large datasets
# Compare benchmarking alternatives (base::system.time, tictoc, microbenchmark)
# 
# NOTE: Using three cores for these tests so they can be run on a 4-core system.
# 
# Methodology:
#
# Create a simple (toy) version of your workflow, simulate data if necessary, 
# then try processing variations to optimize. If still under-performing, then 
# divide the problem into steps which can be run in parallel from those which 
# cannot (i.e., must be run serially). Parallelize those steps which can be, 
# using various techniques and with varying numbers of processor (CPU) cores, 
# to identify the "sweet spot" where there is a maximum gain in performance up  
# to the point at which adding more cores does not offer much more improvement.
#
# Apply these modifications to your production code, but with a subset of your 
# data to confirm that this offers the improvements you need, and if so, then 
# try with your entire dataset. Run on a larger system like an HPC cluster if 
# your current system is lacking. Hopefully, the performance gain was worth it.
# 
# If all goes well, you can generally expect up to a 2x speed improvement for 
# every 2x cores used, but this varies quite a bit depending on the situation. 
# In the example below, our best result showed a 2x speed gain with 3x cores, 
# but we did not test with more cores than three.
# 
# ------------------------------------------------------------------
# Setup
# ------------------------------------------------------------------

# Attach packages, installing as needed
if (!requireNamespace('pacman', quietly = TRUE)) install.packages('pacman')
pacman::p_load(parallel, furrr, purrr, dplyr, tidyr, broom, MASS,
               tictoc, microbenchmark)

# Assign number of processor cores to use
cores <- 3

# ------------------------------------------------------------------
# Create a toy example of our workflow
# ------------------------------------------------------------------

# Run lm() with formula(Price ~ Horsepower) on Cars93, grouped by "Cylinders"

# Get data from Cars93 and filter on number of Cylinders (4, 6, or 8)
df <- Cars93
df <- df %>% filter(Cylinders %in% c(4, 6, 8))

# Create a function to use for test processing
fun <- function(.x, .f = formula(Price ~ Horsepower)) broom::tidy(lm(.f, .x))

# Create a list of data subsetted by number of Cylinders
cyl <- c(4, 6, 8)
lst <- map(cyl, ~ df %>% filter(Cylinders %in% .x)) %>% set_names(cyl)

# Apply the function to our toy dataset
result_single <- lapply(lst, fun)

# Count number of observations per group (N)
df %>% group_by(Cylinders) %>% summarise(N = n())

# Ns are too low (code runs too fast) to see performance improvements, so...

# ------------------------------------------------------------------
# Simulate a larger dataset to measure performance differences
# ------------------------------------------------------------------

# We will simulate a larger version of the Cars93 dataset for these examples

# Get some basic stats so that our simulated data will be realistic
df_stats <- df %>%
  group_by(Cylinders) %>%
  summarize(across(.cols = c(Price, Horsepower),
                   .fns = c(mean = mean, sd = sd)))
df_stats

# Let's simulate a bigger dataset to get a larger N
set.seed <- 42
N <- 1000000
df_sim <- df_stats %>% group_by(Cylinders) %>% nest() %>%
  mutate(Price =
           map(.x = data, ~ rnorm(N, .x$Price_mean, .x$Price_sd)),
         Horsepower =
           map(.x = data, ~ rnorm(N, .x$Horsepower_mean, .x$Horsepower_sd))) %>%
  unnest(c(Price, Horsepower)) %>% dplyr::select(-data)

# Get size of simulated dataset
dim(df_sim)

# Check stats to make sure they match original dataset, roughly
df_sim_stats <- df_sim %>% group_by(Cylinders) %>%
  summarize(across(.cols = c(Price, Horsepower),
                   .fns = c(mean = mean, sd = sd)))
df_sim_stats

# Yes they are very close, and now the number of rows per Cylinder group is N.

# Create a list of data subsetted by number of Cylinders
cyl <- c(4, 6, 8)
lst <- map(cyl, ~ df_sim %>% filter(Cylinders %in% .x)) %>% set_names(cyl)

# Cleanup memory by removing objects no longer needed
rm(df, df_sim, df_stats, df_sim_stats)
gc()

# ------------------------------------------------------------------
# Parallelization tests
# ------------------------------------------------------------------

# Compare single core and parallel processing using the {parallel} package

# Single core version using `lappy()`
system.time(result_single <- lapply(lst, fun))

# Elapsed time: ~2.2s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~1.0s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~2.0s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# Compare results using tictoc
tic()
res <- result_single <- lapply(lst, fun)
toc()

# Compare results using microbenchmark
res <- microbenchmark(result_single <- lapply(lst, fun), 
                      times = 10, unit = 'seconds')
res
paste(signif(mean(res$time)/10^9, 7), attributes(res)$unit)
# NOTE: Results from using system.time, tictoc, and microbenchmark are similar.

# Parallel (multicore) version using `mclapply()`
# Note: Windows only supports mc.cores = 1 so we assign mc.cores by OS type.
mccores <- ifelse(Sys.info()[['sysname']] == 'Windows', 1, cores)
system.time(result_multi <- mclapply(lst, fun, mc.cores = mccores))

# Elapsed time: ~1.1s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~0.5s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.5s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# Compare results using tictoc
tic()
result_multi <- mclapply(lst, fun, mc.cores = mccores)
toc()

# Compare results using microbenchmark
res <- microbenchmark(result_multi <- mclapply(lst, fun, mc.cores = mccores), 
                      times = 10, unit = 'seconds')
res
paste(signif(mean(res$time)/10^9, 7), attributes(res)$unit)
# NOTE: Results from using system.time, tictoc, and microbenchmark are similar.

# Alternative: Parallel version using `parLapply()` and `makeCluster()`
cl <- makeCluster(cores)
system.time(result_multi <- parLapply(cl, lst, fun))
stopCluster(cl)

# Elapsed time: ~1.8s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~0.8s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.6s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# NOTE: Here `parLapply()` performs marginally better than single-core, but
# with smaller datasets the results should be more comparable to `mclapply()`.

# Tidyverse alternative: Do the same, using {purrr} and {furrr} packages

# Single core version using `map()`
system.time(result_single <- map(lst, fun))

# Elapsed time: ~1.8s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~0.8s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.6s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# Parallel (multicore) version using `future_map()`
plan(multisession, workers = cores)
system.time(result_multi <- future_map(lst, fun))

# Elapsed time: ~2.3s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~1.1s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.9s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# We see that mclapply is faster than both parLapply and future_map.
# With smaller datasets and more intensive processing, this relation could be
# different, so always test with your own workflow and various sizes of data.

# Now try using pipes (%>%) from the {magrittr} package (tidyverse)
# and measure time with `tic()` and `toc()` from the {tictoc} package
tic()
result_multi <- lst %>% future_map(fun)
toc()

# Elapsed time: ~0.8s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~0.4s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~0.8s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# This is roughly comparable to `mclapply()` run earlier. So now we see a
# performance improvement using `future_map()` with pipes with larger datasets.
# However, this multicore approach is supported on Windows, unlike mclapply().

# ----------------------------------------------------------------------

# Using base-R and (mc)lapply ... and joining results with dplyr::bind_rows()

# Single core
tic()
result_single <- bind_rows(lapply(lst, fun), .id = 'Cylinders')
toc()

# Elapsed time: ~1.7s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~0.7s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.4s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# Multicore
# Note: Windows only supports mc.cores = 1. See previous mclapply() example.
tic()
result_multi <- bind_rows(mclapply(lst, fun, mc.cores = mccores),
                          .id = 'Cylinders')
toc()

# Elapsed time: ~1.2s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~0.6s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.7s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# We see a similar performance boost using mclapply() vs. lapply() that we saw
# earlier for Linux, whereas macOS showed a more significant improvement.
# Windows performance was the same, since it only supports mc.cores = 1.

# Check to see results are the same
all.equal(result_single, result_multi)

# TRUE

# Now try with pipes:

# Multicore with pipes
# Note: Windows only supports mc.cores = 1. See previous mclapply() examples.
tic()
result_multi <- lst %>%
  mclapply(fun, mc.cores = mccores) %>% bind_rows(.id = 'Cylinders')
toc()

# Elapsed time: ~1.2s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~0.5s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.6s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)


# ----------------------------------------------------------------------

# Now compare with `map()`, `future_map()`, and `list_rbind()` (with pipes)

# Single core version using `map()`
tic()
result_single <- lst %>% map(fun) %>% list_rbind()
toc()

# Elapsed time: ~1.9s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~0.9s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.6s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# Parallel (multicore) version using `future_map()`
plan(multisession, workers = cores)
tic()
result_multi <- lst %>% future_map(fun) %>% list_rbind()
toc()

# Elapsed time: ~2.6s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~1.0s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.9s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# The times are comparable with using `bind_rows()` instead of `list_rbind()`.

# Check to see results are the same
all.equal(result_single, result_multi)

# ----------------------------------------------------------------------

# What about data nesting (structure)?
# use tidyr nesting so that your code will be more tidyversy
# ?nest
# ?unnest

# Setup nesting
df_sim_nested <- lst %>% bind_rows() %>% group_by(Cylinders) %>% nest()

# Cleanup memory by removing objects no longer needed
rm(lst)
gc()

# Single core
tic()
result_single <- df_sim_nested %>%
  mutate(rc = map(data, fun)) %>%
  unnest(rc) %>% dplyr::select(-data)
toc()

# Elapsed time: ~1.9s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~1.1s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~1.8s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# Multicore
plan(multisession, workers = cores)
tic()
result_multi <- df_sim_nested %>%
  mutate(rc = future_map(data, fun)) %>%
  unnest(rc) %>% dplyr::select(-data)
toc()

# Elapsed time: ~3.0s on Ubuntu Linux virtual machine (10-vcore, 164 GB RAM)
# Elapsed time: ~1.5s on Macbook Pro (macOS Sequoia, M1, 2020, 16 GB RAM)
# Elapsed time: ~2.4s on Lenovo Thinkpad T490s (Win11, i7-8665U, 16 GB RAM)

# We see that multicore processing actually took _longer_ using `future_map()`.
# We have seen this before with trivial examples, as the overhead is not worth
# the benefits of parallel processing.

# Check to see results are the same, after converting both results to tibbles
res_lst <- map(list(result_single, result_multi), as_tibble)
all.equal(res_lst[[1]], res_lst[[2]])

# TRUE

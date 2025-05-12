# Determine the optimal number of CPU cores to use for the fastest processing of 
# an analysis. This example uses the flights dataset from {nycflights13} and  
# lm() is run in parallel with mclapply() on Linux or macOS systems and with 
# parLapply() on Windows systems. Times are measured with microbenchmark().
#
# Tested on UW Hyak (klone) with 16 CPU cores and 4 GB RAM allocated to 1 node.
# Tested on macOS Sequoia 15.4.1 on a 2020 M1 Macbook Pro with 16 GB RAM.
# Tested on Windows Server 2022 Standard on a virtual machine with 128 GB RAM.

# Load packages, installing as needed.
if (!requireNamespace('pacman', quietly = TRUE)) install.packages('pacman')
pacman::p_load(broom, microbenchmark, nycflights13, parallel, dplyr, ggplot2)

# Load data and determine the dimensions of the dataset.
df <- flights
dim(df)

# Subset by the columns we will use so that we're not wasting memory
df <- df[, c('arr_delay', 'distance', 'carrier', 'origin', 'hour')]
dim(df)

# Make the dataset 8x bigger ("big data") by combining 8 copies of it, as 
# otherwise, our test function may run too quickly for accurate measurements.
df <- do.call('rbind', lapply(1:8, function(x) df))
dim(df)

# Set the number of groups to the max number of cores we might use.
num_groups <- 16

# Set the number of times to run each benchmark
num_bench <- 5

# If the number of rows is not an even multiple of num_groups, trim extra rows.
# Otherwise, the extra rows will make the results less comparable.
trim_df_length <- function(df, num_groups) {
  if (nrow(df) %% num_groups != 0) {
    group_size <- round(nrow(df) / num_groups)
    df[1:(num_groups * group_size), ]
  }
  return(df)
}
df <- trim_df_length(df, num_groups)

# Define a function to subset by the number of cores we want to test.
df_split <- function(df, n) {
  rows <- 1:nrow(df)
  groups <- split(rows, cut(rows, breaks = n, labels = FALSE)) 
  lapply(groups, function(x) df[x, ])
}

# Test with n = 4, initially.
lst <- df_split(df, n = 4)
length(lst)           # a list of 4 subsets
sapply(lst, nrow)     # each subset has same number of rows

# Create a function to use for test processing.
fmla <- formula(arr_delay ~ distance + carrier + origin + hour)
fun <- function(.x, .f = fmla) broom::tidy(lm(.f, .x))

# Single core version using `lapply()`
res <- microbenchmark(lapply(lst, fun), times = num_bench, unit = 'seconds')
mean(res$time)/10^9

# Multicore version using `mclapply()`
if (Sys.info()["sysname"][['sysname']] != 'Windows') {
  res <- microbenchmark(mclapply(lst, fun, .f = fmla, mc.cores = 4), 
                        times = num_bench, unit = 'seconds')
  mean(res$time)/10^9
  # Multicore was about 2x faster (on a Linux system).
}

# Note: If you want to run this on Windows, you should know that Windows does
# not support mclapply() with multiple cores. So, here is a version which can 
# also run on Windows:

# Multicore version using `parLapply()`
cl <- makeCluster(getOption('cl.cores', 4))
res <- microbenchmark(parLapply(cl, lst, fun, .f = fmla),
                      times = num_bench, unit = 'seconds')
stopCluster(cl)
mean(res$time)/10^9
# This multicore result was ~ 35% slower than the mclapply() version, above.

# Define a function to use mclapply() unless you are running on Windows, in 
# which case it will use parLapply().
multiLapply <- function(lst, fun, .f, cores, times, unit = 'seconds') {
  if (Sys.info()["sysname"][['sysname']] == 'Windows') {
    cl <- makeCluster(getOption('cl.cores', cores))
    res <- microbenchmark(parLapply(cl, lst, fun, .f),
                          times = times, unit = unit)
    stopCluster(cl)
  } else {
    res <- microbenchmark(mclapply(lst, fun, .f, mc.cores = cores), 
                          times = times, unit = unit)
  }
  return(res)
}

# Now test this function...
res <- multiLapply(lst, fun, .f = fmla, cores = 4, times = num_bench)
mean(res$time)/10^9
# Seems to be about as fast as simply running with mclapply() directly on Linux.

# Automate testing with 1, 2, 4, 8, and 16 cores.
ncores <- sapply(0:log2(16), function(n) 2^n)
ncores

# Define a function to test processing with various numbers of CPU cores
mctest <- function(cores, lst, fun, .f, times) {
  res <- multiLapply(lst, fun, .f, cores = cores, times = times)
  time_s <- mean(res$time)/10^9
  return(data.frame(num_cores = cores, time_s = time_s))
}

# Run the test.
res <- lapply(ncores, mctest, lst, fun, .f = fmla, times = num_bench)

# Show results.
res_df <- do.call('rbind', res)
res_df
plot(res_df)

# Fastest was with 4 cores. After that it mostly flat-lined. We can do better.

# Let's try again, but in batches where the # of subsets matches the # of cores.

# Define a function to test processing with various numbers of cores, subsetting
# the dataset by the number of cores (batched with num_groups = num_cores).
mctest_batched <- function(cores, df, fun, .f, times) {
  lst <- ifelse(cores == 1, list(df), 
                df_split(trim_df_length(df, num_groups = cores), cores))
  res <- multiLapply(lst, fun, .f, cores = cores, times = times)
  time_s <- mean(res$time)/10^9
  return(data.frame(num_cores = cores, time_s = time_s))
}

# Run the test.
res_batched <- lapply(ncores, mctest_batched, df, fun, fmla, num_bench)

# Show results.
res_df_batched <- do.call('rbind', res_batched)
res_df_batched
plot(res_df_batched)

# Combine the results into a single plot using ggplot.
gg_data <- bind_rows(list(N = res_df, Y = res_df_batched), .id = 'batched')
ggplot(gg_data, aes(num_cores, time_s, color = batched)) + geom_point() + 
  geom_line() + theme_minimal() + 
  ggtitle(
    paste(c('Multi-core test of lm() with nycflights13::flights data on node'), 
          Sys.info()["nodename"])
  )

# With batching, we not only see better multicore results, but we also see 
# that we can take advantage of more cores to see real gains. So, the take-away 
# is that you should try to subset your data by the number of cores you are 
# going to use, if possible, even if you could subset further (smaller).

# Compare the decrese in runtime as a function of the increase in # of cores
res_df_batched_delta <- res_df_batched %>% mutate(
  cores_delta =  num_cores - lag(num_cores),
  cores_delta_pct = scales::percent(cores_delta / lag(num_cores)),
  time_delta = time_s - lag(time_s),
  time_delta_pct = scales::percent(time_delta / lag(time_s))
) %>% select(-cores_delta, -time_delta)

res_df_batched_delta

# We see that for every 100% increase (doubling) in number of cores, we see 
# about 50%  decrease (halving) in runtime. While this is a diminishing return, 
# it's about the best you can expect to see, generally. If you want, try with 
# 32 or even 64 cores and see if this pattern holds true. In practice, these 
# resources are limited, especially on a shared system like a compute cluster 
# such as hyak, so limiting to 4 or 8 cores might be "fast enough" and would 
# allow others to use those remaining cores.

# Find out how much memory (RAM) was used (maximum).
paste(as.character(round(sum(sum(gc()[, 6]))/1000, 2)), "Gbytes RAM 'max used'")

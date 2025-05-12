# Install all R packages used by scripts in this repository

# Force use of personal R library folder, creating as needed
lib_dir <- Sys.getenv("R_LIBS_USER")
if (!dir.exists(lib_dir)) dir.create(lib_dir, recursive = TRUE)
.libPaths(lib_dir, include.site = FALSE)

# Set repository URL
r <- getOption("repos")
r["CRAN"] <- "https://cloud.r-project.org"
options(repos = r)

# Install pacman, as needed
if (!requireNamespace("pacman", quietly = TRUE)) install.packages("pacman")

# Install other packages, as needed
pacman::p_load(benchmarkme, memuse, parallel, robustbase, MASS, here, tibble, 
               ggplot2, broom, microbenchmark, nycflights13, dplyr, furrr, 
               purrr, tidyr, tictoc)

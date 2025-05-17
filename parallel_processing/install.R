# Install all R packages used by scripts in this repository

# Clear workspace of all objects and unload all extra (non-base) packages.
rm(list = ls(all = TRUE))
if (!is.null(sessionInfo()$otherPkgs)) {
  res <- suppressWarnings(
    lapply(paste('package:', names(sessionInfo()$otherPkgs), sep=""),
           detach, character.only=TRUE, unload=TRUE, force=TRUE))
}

# Force use of personal R library folder, creating as needed
lib_dir <- Sys.getenv("R_LIBS_USER")
if (!dir.exists(lib_dir)) dir.create(lib_dir, recursive = TRUE)
.libPaths(lib_dir, include.site = FALSE)

# Choose appropriate repository URL based on operating system
if (Sys.info()["sysname"] == "Linux") {
  # Find linux distribution and version
  lsb_release <- system(command = "lsb_release -a", intern = TRUE, 
                        ignore.stderr = TRUE)
  x <- as.data.frame(lsb_release)
  df <- data.frame(strsplit(x$lsb_release, ":\\t"))
  names(df) <- lapply(df[1, ], as.character)
  df <- df[-1,] 
  
  if (df$`Distributor ID` %in% c("Debian", "Ubuntu")) {
    # Set repository URL for binary packages hosted by Posit
    repo_url <- 
      sprintf("https://packagemanager.posit.co/cran/__linux__/%s/latest", 
              df$Codename)
  } else {
    # Set repository URL for CRAN mirror
    repo_url <- "https://cloud.r-project.org"
  }
  
} else {
  # Set repository URL for CRAN mirror
  #repo_url <- "https://packagemanager.posit.co/cran/latest"
  repo_url <- "https://cloud.r-project.org"
}

# Set option for HTTP User Agent to include R version information in header
# See: https://www.r-bloggers.com/2023/07/posit-package-manager-for-linux-r-binaries/
local(options(HTTPUserAgent = sprintf(
  "R/%s R (%s)",
  getRversion(),
  paste(
    getRversion(),
    R.version["platform"],
    R.version["arch"],
    R.version["os"]
  )
)))

# Set CRAN package repository URL
local(options(repos = c(CRAN = repo_url)))

# Define a function to conditionally install packages, if needed
pkg_inst <- function(pkgs) {
  if (!requireNamespace("pak", quietly = TRUE)) install.packages("pak")
  res <- sapply(pkgs, function(pkg) {
    if (!requireNamespace(pkg, quietly = TRUE)) pak::pkg_install(pkg)
  })
}

# Install packages, as needed
pkgs <- c("parallel", "benchmarkme", "memuse", "robustbase", "MASS", "here", 
          "tibble", "dplyr", "tidyr", "purrr", "furrr", "ggplot2", "broom", 
          "nycflights13", "microbenchmark", "tictoc", "pacman", "rsample")
pkg_inst(pkgs)

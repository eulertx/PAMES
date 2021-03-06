#' Select informative CpG sites
#'
#' This function generates a list of informative CpG sites to be used to estimate
#' the purity of a set of tumor samples.
#'
#' Informative sites are divided into \code{hyper} and \code{hypo} depending
#' on their level of
#' methylation with respect to the average beta-score of normal samples.
#' Both sets will be used to compute purity.
#'
#' @param tumor a matrix of beta scores generated by an Illumina BeadChip.
#' @param auc a vector of AUC scores generated by \code{compute_AUC}.
#' @param max_sites maximum number of sites to retrieve (half hyper-, half hypo-methylated)
#' (default = 20).
#' @param min_distance measured in bps (base pairs), used to avoid selection
#' of CpG sites located within such distancce from one another (default = 1e6).
#' @param hyper_range a vector of length two with minimum lower and upper values required to
#' select hyper-methylated informative sites
#' @param hypo_range a vector of length two with minimum lower and upper values required to
#' select hypo-methylated informative sites
#' @param platform which Illumina platform was the experiment perfromed on
#' (either \strong{450k} or \strong{27k}).
#' @param genome which genome version to use to map probes and
#' exclude probes located too close to each other (either \strong{hg19} or \strong{hg38}).
#' @return a named list of indexes of informative sites ("hyper-" and "hypo-methylated").
#' @export
#' @examples
#' auc_data <- compute_AUC(tumor_toy_data, control_toy_data)
#' ## WARNING: The following code doesn't retrieve any informative site
#' ## Its only purpose is to show how to use the tool
#' info_sites <- select_informative_sites(tumor_toy_data, auc_data, platform="27k")
#' info_sites.hg38 <- select_informative_sites(tumor_toy_data, auc_data,
#'                                             platform="27k", genome="hg38")
select_informative_sites <- function(tumor, auc, max_sites = 20,
  min_distance = 1e6, hyper_range = c(min = .40, max = .90),
  hypo_range = c(min = .10, max = .60),
  genome = c("hg19", "hg38"), platform = c("450k", "27k")){
  # check parameters ---------------------------------------------------------
  platform <- match.arg(platform)
  platform_data <- get(paste0("illumina", platform, "_", genome))
  genome <- match.arg(genome)
  tumor <- as.matrix(tumor)
  auc <- as.vector(auc)
  if (any(tumor < 0, na.rm = T) || any(tumor > 1, na.rm = T) ||
      any(auc   < 0, na.rm = T) || any(auc   > 1, na.rm = T)){
    stop("'tumor' and 'auc' must be numeric matrixes.")
  }
  if ((nrow(tumor) != length(auc)) || (nrow(tumor) != nrow(platform_data)))
    stop(paste0(sprintf("'tumor' and 'auc' must have %i number of rows.\n", nrow(platform_data)),
      "Be sure to use every 'cg' probe and remove any 'non-cg' probe."))

  if (max_sites %% 2 != 0 & !is.integer(max_sites))
    stop ("'max_sites' must be an integer and even number.")

  min_distance <- as.integer(min_distance)
  if (min_distance < 0)
    stop("'min_distance' must be positive.")

  if (!is.numeric(hyper_range) || length(hyper_range) != 2 || !is.numeric(hypo_range) || length(hypo_range) != 2)
    stop("'hyper_range' and 'hypo_range' must be numeric vectors of length 2.")

  stopifnot(length(hyper_range) == 2 || length(hypo_range) == 2)

  message(sprintf("Genome: %s", genome))
  message(sprintf("Platform: %s", platform))
  message(sprintf("Number of sites: %i", max_sites))
  message(sprintf("Miniminum distance between sites: %i bp", min_distance))
  message(sprintf("Hyper-methylated sites range: %s", paste(hyper_range, collapse = " - ")))
  message(sprintf("Hypo-methylated sites range: %s",  paste(hypo_range, collapse = " - ")))

  # minimum and maximum beta per site ----------------------------------------
  beta_max <- suppressWarnings(apply(tumor, 1, max, na.rm = T))
  beta_min <- suppressWarnings(apply(tumor, 1, min, na.rm = T))
  hyper_idx <- which(beta_min < hyper_range[1] & beta_max > hyper_range[2] & auc > .80)
  hypo_idx  <- which(beta_min < hypo_range[1]  & beta_max > hypo_range[2]  & auc < .20)

  message(sprintf("[%s] Total hyper-methylated sites = %i", Sys.time(), length(hyper_idx)))
  message(sprintf("[%s] Total hypo-methylated sites = %i",  Sys.time(), length(hypo_idx)))

  ordered_hyper_idx <- hyper_idx[order(auc[hyper_idx], decreasing = T)]
  ordered_hypo_idx  <- hypo_idx[order(auc[hypo_idx],   decreasing = F)]

  message(sprintf("[%s] Hyper-methylated sites cluster reduction...", Sys.time()))
  top_hyper_idx <- cluster_reduction(ordered_hyper_idx, max_sites/2, min_distance, platform_data)
  message(sprintf("[%s] Hypo-methylated sites cluster reduction...", Sys.time()))
  top_hypo_idx <- cluster_reduction(ordered_hypo_idx, max_sites/2, min_distance, platform_data)

  list(hyper = top_hyper_idx, hypo = top_hypo_idx)
}

#' Remove CpG sites too close to each other
#'
#' Remove sites within 'min_distance' (keep only one, per 'cluster'), keeping at most N sites
#' accoring to their order.
#' @param sites_idx a vector of integers
#' @param N number of sites to retrieve
#' @param min_distance an integer (in basepairs)
#' @param platform_data a data.frame with info about probes location
#' (either \strong{450k} or \strong{27k}).
#' @keywords internal
#' @return a vector of indexes with close sites removed.
cluster_reduction <- function(sites_idx, N, min_distance, platform_data){
  top_idx <- rep(NA, length(sites_idx))
  i <- 1
  n <- 1
  while (n <= N & i <= length(sites_idx)) {
    idx <- sites_idx[i]
    if (!too_close(idx, top_idx[!is.na(top_idx)], min_distance, platform_data)) {
      top_idx[n] <- idx
      n <- n + 1
    }
    i <- i+1
  }
  top_idx <- top_idx[!is.na(top_idx)]
  message(sprintf("[%s] %s sites retrieved after 'cluster reduction'.",
    Sys.time(), length(top_idx)))
  return(top_idx)
}

#' Check whether a site is too close to the other sites or not
#'
#' Used in "cluster_redution" function only, given the index of a CpG site and
#' a set of indexes of other sites, check if last added site is less than
#' "min_distance" basepair distant from previously retrieved sites.
#' @param new_idx an index (integer)
#' @param prev_idxs a vector of indexes (integer)
#' @param min_distance an integer. Distance in basepairs
#' @param platform_data a data.frame with info about probes location
#' (either \strong{450k} or \strong{27k}).
#' @keywords internal
#' @return logical
too_close <- function(new_idx, prev_idxs, min_distance, platform_data){
  if (length(prev_idxs) == 0) {
    answer <- FALSE
  } else {
    new_site <- platform_data[new_idx,]
    other_sites <- platform_data[prev_idxs,]
    same_chromosome <- other_sites[["Chromosome"]] == new_site[["Chromosome"]]
    if ("Start" %in% names(platform_data)){
      within_min_distance <- abs(other_sites[["Start"]] - new_site[["Start"]]) < min_distance
    } else {
      within_min_distance <-
        abs(other_sites[["Genomic_Coordinate"]] - new_site[["Genomic_Coordinate"]]) < min_distance
    }
    # pairwise comparision of chromosome location and distance
    answer <- any(same_chromosome & within_min_distance)
  }
  return(ifelse(test = is.na(answer), yes = F, no = answer))
}


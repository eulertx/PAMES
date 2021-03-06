% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/select_informative_sites.R
\name{cluster_reduction}
\alias{cluster_reduction}
\title{Remove CpG sites too close to each other}
\usage{
cluster_reduction(sites_idx, N, min_distance, platform_data)
}
\arguments{
\item{sites_idx}{a vector of integers}

\item{N}{number of sites to retrieve}

\item{min_distance}{an integer (in basepairs)}

\item{platform_data}{a data.frame with info about probes location
(either \strong{450k} or \strong{27k}).}
}
\value{
a vector of indexes with close sites removed.
}
\description{
Remove sites within 'min_distance' (keep only one, per 'cluster'), keeping at most N sites
accoring to their order.
}
\keyword{internal}

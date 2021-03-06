% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/dplyr-verbs.R
\name{group_by_key}
\alias{group_by_key}
\title{Group by key variables}
\usage{
group_by_key(.data, ..., .drop = FALSE)
}
\arguments{
\item{.data}{A \code{tbl_ts} object.}

\item{...}{Ignored.}

\item{.drop}{When \code{.drop = TRUE}, empty groups are dropped.}
}
\description{
Group by key variables
}
\examples{
tourism \%>\%
  group_by_key()
}

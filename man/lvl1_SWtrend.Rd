% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/lvl1_SWtrend.R
\name{lvl1_SWtrend}
\alias{lvl1_SWtrend}
\title{Calculate a trend for the share weights based on the EDGE scenario and the regional clusters.}
\usage{
lvl1_SWtrend(calibration_output, clusters, years, REMIND_scenario,
  EDGE_scenario)
}
\arguments{
\item{EDGE_scenario}{in order to avoid inconsistencies, only the combinations present in dt_tmp are to be taken from dt, which instead is based on a cartesian product.
If the sum of all years present in the group is 2100, i.e. 2100 is the only year present, the column has to be deleted}
}
\description{
Calculate a trend for the share weights based on the EDGE scenario and the regional clusters.
}

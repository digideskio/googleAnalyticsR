##docs: https://developers.google.com/analytics/trusted-testing/reporting/
## https://developers.google.com/analytics/trusted-testing/reporting/rest/v4/reports/batchGet#Dimension

## TODO:
##       segments

#' Google Analytics v4 API fetch
#'
#' @param viewId viewId of data to get.
#' @param date_range character or date vector of format c(start, end). Optional c(s1,e1,s2,e2)
#' @param metrics Metric to fetch. Required. Supports calculated metrics.
#' @param dimensions Dimensions to fetch.
#' @param filters A list of dimensionFilterClauses or metricFilterClauses
#' @param segments Segments of the data
#' @param pivots Pivots of the data
#' @param samplingLevel Sample level
#' @param metricFormat If supplying calculated metrics, specify the metric type
#'
#' @description
#'   This function constructs the Google Analytics API v4 call to be called
#'   via \code{fetch_google_analytics_4}
#'
#'
#' @section Metrics:
#'   Metrics support calculated metrics like ga:users / ga:sessions if you supply
#'   them in a named vector.
#'
#'   You must supply the correct 'ga:' prefix unlike normal metrics
#'
#'   You can mix calculated and normal metrics like so:
#'
#'   \code{customMetric <- c(sessionPerVisitor = "ga:sessions / ga:visitors",
#'                           "bounceRate",
#'                           "entrances")}
#'
#'    You can also optionally supply a \code{metricFormat} parameter that must be
#'    the same length as the metrics.  \code{metricFormat} can be:
#'    \code{METRIC_TYPE_UNSPECIFIED, INTEGER, FLOAT, CURRENCY, PERCENT, TIME}
#'
#'    All metrics are currently parsed to as.numeric when in R.
#'
#' @section Dimensions:
#'
#'   Supply a character vector of dimensions, with or without \code{ga:} prefix.
#'
#'   Optionally for numeric dimension types such as
#'   \code{ga:hour, ga:browserVersion, ga:sessionsToTransaction}, etc. supply
#'   histogram buckets suitable for histogram plots.
#'
#'   If non-empty, we place dimension values into buckets after string to int64.
#'   Dimension values that are not the string representation of an integral value
#'   will be converted to zero. The bucket values have to be in increasing order.
#'   Each bucket is closed on the lower end, and open on the upper end.
#'   The "first" bucket includes all values less than the first boundary,
#'   the "last" bucket includes all values up to infinity.
#'   Dimension values that fall in a bucket get transformed to a new dimension
#'   value. For example, if one gives a list of "0, 1, 3, 4, 7", then we
#'   return the following buckets: -
#'
#'   bucket #1: values < 0, dimension value "<0"
#'   bucket #2: values in [0,1), dimension value "0"
#'   bucket #3: values in [1,3), dimension value "1-2"
#'   bucket #4: values in [3,4), dimension value "3"
#'   bucket #5: values in [4,7), dimension value "4-6"
#'   bucket #6: values >= 7, dimension value "7+"
#'
#' @export
make_ga_4_req <- function(viewId,
                          date_range,
                          metrics,
                          dimensions=NULL,
                          dim_filters=NULL,
                          met_filters=NULL,
                          filtersExpression=NULL,
                          orderBys=NULL,
                          segments=NULL,
                          pivots=NULL,
                          max=1000,
                          samplingLevel=c("DEFAULT", "SMALL","LARGE"),
                          metricFormat=NULL,
                          histogramBuckets=NULL) {

  samplingLevel <- match.arg(samplingLevel)

  id <- sapply(viewId, checkPrefix, prefix = "ga")

  date_list_one <- date_ga4(date_range[1:2])
  if(length(date_range) == 4){
    date_list_two <- date_ga4(date_range[3:4])
  } else {
    date_list_two <- NULL
  }

  dim_list <- dimension_ga4(dimensions, histogramBuckets)
  met_list <- metric_ga4(metrics, metricFormat)

  # order the dimensions if histograms
  if(all(is.null(orderBys), !is.null(histogramBuckets))){
    bys <- intersect(dimensions, names(histogramBuckets))
    orderBys <- lapply(bys,
                       order_type,
                       FALSE,
                       "HISTOGRAM_BUCKET")
  }


  request <-
    structure(
      list(
        viewId = id,
        dateRanges = list(
          date_list_one,
          date_list_two
        ),
        samplingLevel = samplingLevel,
        dimensions = dim_list,
        metrics = met_list,
        dimensionFilterClauses = dim_filters,
        metricFilterClauses = met_filters,
        filtersExpression = filtersExpression,
        orderBys = orderBys,
        segments = segments,
        pivots = pivots,
        pageSize = max,
        includeEmptyRows = TRUE
      ),
      class = "ga4_req")


  request <- rmNullObs(request)

}



#' Do a single request
#'
#' @inheritParams make_ga_4_req
#' @export
google_analytics_4 <- function(viewId,
                               date_range,
                               metrics,
                               dimensions=NULL,
                               date_range_two=NULL,
                               dim_filters=NULL,
                               met_filters=NULL,
                               filtersExpression=NULL,
                               segments=NULL,
                               pivots=NULL,
                               max=1000,
                               samplingLevel=c("DEFAULT", "SMALL","LARGE"),
                               metricFormat=NULL,
                               histogramBuckets=NULL){

  req <- make_ga_4_req(viewId=viewId,
                       date_range=date_range,
                       metrics=metrics,
                       dimensions=dimensions,
                       dim_filters=dim_filters,
                       met_filters=met_filters,
                       filtersExpression = filtersExpression,
                       segments=segments,
                       pivots=pivots,
                       max=max,
                       samplingLevel=samplingLevel,
                       metricFormat=metricFormat,
                       histogramBuckets=histogramBuckets)

  fetch_google_analytics_4(req)
}

#' Fetch multiple GAv4 requests
#'
#' @param requests A list of GAv4 requests created by make_ga_4_req
#'
#' @return dataframe of GA results
#'
#' @importFrom googleAuthR gar_api_generator
#' @export
fetch_google_analytics_4 <- function(request_list){

  testthat::expect_type(request_list, "list")

  raw <- getOption("googleAnalyticsR.raw_req")

  if(raw) {
    warning("No data parsing due to 'getOption('googleAnalyticsR.raw_req')' set to TRUE")
    dpf <- function(x) x
    } else {
      dpf <- google_analytics_4_parse_batch
    }

  body <- list(
    reportRequests = request_list
  )

  f <- gar_api_generator("https://analyticsreporting.googleapis.com/v4/reports:batchGet",
                         "POST",
                         data_parse_function = dpf, 
                         simplifyVector = FALSE)

  message("Fetching Google Analytics v4 API data")

  out <- f(the_body = body)

  attr(out, "dates") <- request_list$dateRanges

  out
}

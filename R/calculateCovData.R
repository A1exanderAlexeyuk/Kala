#' Generate Feature Extraction Reports by Time Windows
#'
#' @description
#' This function generates detailed reports from feature extraction data, analyzing covariates
#' across different time windows. It processes both binary and continuous covariates, and can
#' handle time-varying and non-time-varying features. The function supports filtering by
#' covariate IDs, formatting according to table specifications, and pivoting results for
#' easier interpretation.
#'
#' @param covariateData A covariateData object containing feature extraction results with components:
#'   \itemize{
#'     \item analysisRef (analysisId, analysisName, domainId, isBinary, missingMeansZero)
#'     \item covariateRef (covariateId, covariateName, analysisId, conceptId, valueAsConceptId, collisions)
#'     \item covariates (cohortDefinitionId, covariateId, timeId, sumValue, averageValue)
#'     \item covariatesContinuous (cohortDefinitionId, covariateId, countValue, minValue, maxValue, 
#'           averageValue, standardDeviation, medianValue, p10Value, p25Value, p75Value, p90Value, timeId)
#'     \item timeRef (timeId, startDay, endDay)
#'   }
#' @param startDays Vector of start days for time windows to include in the report. If NULL, all available
#'   time windows from covariateData$timeRef will be used.
#' @param endDays Vector of end days for time windows to include in the report. If NULL, all available
#'   time windows from covariateData$timeRef will be used.
#' @param includeNonTimeVarying Boolean indicating whether to include non-time-varying covariates.
#'   Default is FALSE.
#' @param minAverageValue Minimum average value threshold for including covariates. Default is 0.01.
#' @param includedCovariateIds Vector of covariate IDs to include. If NULL, all covariates will be included
#'   (subject to other filters).
#' @param excludedCovariateIds Vector of covariate IDs to exclude. If NULL, no covariates will be explicitly
#'   excluded.
#' @param table1Specifications Optional data frame with specifications for formatting as a Table 1, containing
#'   columns for label and covariateIds.
#' @param cohortId The cohort definition ID to generate the report for.
#' @param cohortDefinitionSet A data frame containing cohort definitions.
#' @param databaseId Optional database ID to include in the report header.
#' @param cohortName Optional cohort name to include in the report header.
#' @param reportName Optional report name to include in the report header.
#' @param format Boolean indicating whether to format the values in the report (e.g., as percentages).
#'   Default is TRUE.
#' @param distributionStatistic Character vector of statistics to include for continuous variables.
#'   Default includes "averageValue", "standardDeviation", "medianValue", "p25Value", "p75Value".
#' @param pivot Boolean indicating whether to pivot the report to have time periods as columns.
#'   Default is TRUE.
#'
#' @return A list with two components:
#'   \itemize{
#'     \item raw: The raw data frame with all covariate information before formatting
#'     \item formatted: The formatted report, either in long format or pivoted (if pivot = TRUE)
#'   }
#'   
#' @details
#' The function processes both binary and continuous covariates from the provided covariateData object.
#' For binary covariates, it reports counts and percentages. For continuous covariates, it reports
#' the specified distribution statistics. The function can filter covariates based on minimum average
#' value and specific inclusion/exclusion lists.
#' 
#' Time windows are specified using startDays and endDays parameters. If these are NULL, all time
#' windows in the covariateData will be used. Non-time-varying covariates can be included by setting
#' includeNonTimeVarying to TRUE.
#' 
#' The table1Specifications parameter allows for organizing covariates into logical groups in the
#' report, similar to a Table 1 in clinical papers.
#'
#' @examples
#' \dontrun{
#' # Load covariate data
#' covariateData <- FeatureExtraction::loadCovariateData("path/to/covariateData")
#' 
#' # Generate report for specific time windows
#' report <- getFeatureExtractionReportByTimeWindows(
#'   covariateData = covariateData,
#'   startDays = c(-365, -30, 0),
#'   endDays = c(-1, -1, 0),
#'   includeNonTimeVarying = TRUE,
#'   cohortId = 1
#' )
#' 
#' # View the formatted report
#' View(report$formatted)
#' }
#'
#'
#' @export
getFeatureExtractionReportByTimeWindows <- function(
    covariateData,
    startDays = NULL,
    endDays = NULL,
    includeNonTimeVarying = FALSE,
    minAverageValue = 0.01,
    includedCovariateIds = NULL,
    excludedCovariateIds = NULL,
    table1Specifications = NULL,
    cohortId,
    cohortDefinitionSet,
    databaseId = NULL,
    cohortName = NULL,
    reportName = NULL,
    format = TRUE,
    distributionStatistic = c(
      "averageValue",
      "standardDeviation",
      "medianValue",
      "p25Value",
      "p75Value"
    ),
    pivot = TRUE) {
  
  # Check if table1Specifications is provided and process covariateIds
  if (!is.null(table1Specifications)) {
    if (nrow(table1Specifications) == 0) {
      stop("please check table1Specifications")
    }
    includedCovariateIdsFromTable1Specifications <-
      table1Specifications$covariateIds |>
      paste(collapse = ",") |>
      commaSeparaedStringToIntArray()
    
    if (!is.null(includedCovariateIds)) {
      includedCovariateIds <- intersect(
        includedCovariateIds,
        includedCovariateIdsFromTable1Specifications
      )
    } else {
      includedCovariateIds <- includedCovariateIdsFromTable1Specifications
    }
  }
  
  # Join covariateRef and analysisRef to get full covariate information
  covariateAnalysisId <- covariateData$covariateRef |>
    dplyr::select(
      covariateId,
      analysisId,
      covariateName,
      conceptId
    ) |>
    dplyr::inner_join(
      covariateData$analysisRef |>
        dplyr::select(
          analysisId,
          analysisName,
          domainId
        ),
      by = "analysisId"
    )
  
  # Filter by included/excluded covariateIds if specified
  if (!is.null(includedCovariateIds)) {
    covariateAnalysisId <- covariateAnalysisId |>
      dplyr::filter(covariateId %in% includedCovariateIds)
  }
  
  if (!is.null(excludedCovariateIds)) {
    covariateAnalysisId <- covariateAnalysisId |>
      dplyr::filter(!covariateId %in% excludedCovariateIds)
  }
  
  reportTimeVarying <- dplyr::tibble()
  reportNonTimeVarying <- dplyr::tibble()
  
  # If no specific time windows provided, use all from covariateData$timeRef
  if (all(
    is.null(startDays),
    is.null(endDays),
    "timeRef" %in% (names(covariateData))
  )) {
    startDays <-
      covariateData$timeRef |>
      dplyr::collect() |>
      dplyr::pull(startDay)
    endDays <-
      covariateData$timeRef |>
      dplyr::collect() |>
      dplyr::pull(endDay)
  }
  
  # Process time-varying covariates
  if (any(!is.null(startDays), !is.null(endDays))) {
    # Binary covariates
    reportTimeVarying1 <- covariateData$covariates |>
      dplyr::filter(cohortDefinitionId == cohortId) |>
      dplyr::inner_join(
        covariateData$timeRef |>
          dplyr::filter(
            startDay %in% startDays,
            endDay %in% endDays
          ) |>
          dplyr::mutate(
            periodName = paste0(
              "d",
              startDay |> as.integer(),
              "d",
              endDay |> as.integer()
            )
          ),
        by = "timeId"
      ) |>
      dplyr::inner_join(covariateAnalysisId,
                        by = "covariateId"
      ) |>
      dplyr::arrange(
        startDay,
        endDay,
        dplyr::desc(averageValue)
      ) |>
      dplyr::select(
        covariateId,
        covariateName,
        conceptId,
        analysisId,
        analysisName,
        domainId,
        periodName,
        sumValue,
        averageValue
      ) |>
      dplyr::filter(averageValue > minAverageValue) |>
      dplyr::collect() |>
      dplyr::mutate(continuous = 0)
    
    # Continuous covariates if available
    if (!is.null(covariateData$covariatesContinuous)) {
      # Get statistics for continuous covariates
      reportTimeVarying2a <-
        covariateData$covariatesContinuous |>
        dplyr::filter(cohortDefinitionId == cohortId) |>
        dplyr::inner_join(
          covariateData$timeRef |>
            dplyr::filter(
              startDay %in% startDays,
              endDay %in% endDays
            ) |>
            dplyr::mutate(
              periodName = paste0(
                "d",
                startDay |> as.integer(),
                "d",
                endDay |> as.integer()
              )
            ),
          by = "timeId"
        ) |>
        dplyr::inner_join(covariateAnalysisId,
                          by = "covariateId"
        ) |>
        dplyr::arrange(
          startDay,
          endDay,
          dplyr::desc(averageValue)
        ) |>
        dplyr::select(
          "covariateId",
          "covariateName",
          "conceptId",
          "analysisId",
          "analysisName",
          "domainId",
          "periodName",
          dplyr::all_of(distributionStatistic)
        ) |>
        dplyr::filter(averageValue > minAverageValue) |>
        dplyr::collect() |>
        tidyr::pivot_longer(
          cols = dplyr::all_of(distributionStatistic),
          names_to = "statistic",
          values_to = "averageValue"
        ) |>
        dplyr::mutate(statistic = stringr::str_replace(
          string = statistic,
          pattern = "Value",
          replacement = ""
        )) |>
        dplyr::mutate(covariateName = paste0(covariateName, " (", statistic, ")")) |>
        dplyr::select(-statistic)
      
      # Get count values for continuous covariates
      reportTimeVarying2b <-
        covariateData$covariatesContinuous |>
        dplyr::filter(cohortDefinitionId == cohortId) |>
        dplyr::inner_join(
          covariateData$timeRef |>
            dplyr::filter(
              startDay %in% startDays,
              endDay %in% endDays
            ) |>
            dplyr::mutate(
              periodName = paste0(
                "d",
                startDay |> as.integer(),
                "d",
                endDay |> as.integer()
              )
            ),
          by = "timeId"
        ) |>
        dplyr::inner_join(covariateAnalysisId,
                          by = "covariateId"
        ) |>
        dplyr::select(
          covariateId,
          periodName,
          countValue
        ) |>
        dplyr::rename(sumValue = countValue) |>
        dplyr::collect()
      
      # Join statistics with counts for continuous covariates
      reportTimeVarying2 <- reportTimeVarying2a |>
        dplyr::inner_join(reportTimeVarying2b,
                          by = c(
                            "covariateId",
                            "periodName"
                          )
        ) |>
        dplyr::mutate(continuous = 1)
    } else {
      reportTimeVarying2 <- dplyr::tibble()
    }
    
    # Combine binary and continuous time-varying covariates
    reportTimeVarying <- dplyr::tibble()
    if (nrow(reportTimeVarying1) > 0) {
      reportTimeVarying <- dplyr::bind_rows(
        reportTimeVarying,
        reportTimeVarying1
      )
    }
    if (nrow(reportTimeVarying2) > 0) {
      reportTimeVarying <- dplyr::bind_rows(
        reportTimeVarying,
        reportTimeVarying2
      )
    }
    
    # Format the report if needed
    if (all(
      nrow(reportTimeVarying) > 0,
      length(colnames(reportTimeVarying) > 0),
      format
    )) {
      reportTimeVarying <-
        dplyr::bind_rows(
          reportTimeVarying |>
            dplyr::filter(continuous == 0) |>
            dplyr::mutate(
              report = formatCountPercent(count = sumValue, percent = averageValue)
            ),
          reportTimeVarying |>
            dplyr::filter(continuous == 1) |>
            dplyr::mutate(
              report = formatDecimalWithComma(
                number = averageValue,
                decimalPlaces = 1,
                round = 1
              )
            )
        ) |>
        dplyr::select(-continuous)
    } else {
      reportTimeVarying <- dplyr::tibble()
    }
  }
  
  # Process non-time-varying covariates if requested
  if (includeNonTimeVarying) {
    # Check if timeId column exists and filter accordingly
    if ("timeId" %in% colnames(covariateData$covariates)) {
      covariateDataTemp <- covariateData$covariates |>
        dplyr::filter(cohortDefinitionId == cohortId) |>
        dplyr::filter(is.na(timeId))
    } else {
      covariateDataTemp <- covariateData$covariates |>
        dplyr::filter(cohortDefinitionId == cohortId)
    }
    
    # Binary non-time-varying covariates
    reportNonTimeVarying1 <- covariateDataTemp |>
      dplyr::inner_join(covariateAnalysisId,
                        by = "covariateId"
      ) |>
      dplyr::arrange(dplyr::desc(averageValue)) |>
      dplyr::mutate(periodName = "nonTimeVarying") |>
      dplyr::select(
        covariateId,
        covariateName,
        conceptId,
        analysisId,
        analysisName,
        domainId,
        periodName,
        sumValue,
        averageValue
      ) |>
      dplyr::filter(averageValue > minAverageValue) |>
      dplyr::collect() |>
      dplyr::mutate(continuous = 0)
    
    # Continuous non-time-varying covariates if available
    if (!is.null(covariateData$covariatesContinuous)) {
      # Check if timeId column exists and filter accordingly
      if ("timeId" %in% colnames(covariateData$covariatesContinuous)) {
        covariatesContinuousTemp <- covariateData$covariatesContinuous |>
          dplyr::filter(cohortDefinitionId == cohortId) |>
          dplyr::filter(is.na(timeId))
      } else {
        covariatesContinuousTemp <- covariateData$covariatesContinuous |>
          dplyr::filter(cohortDefinitionId == cohortId)
      }
      
      # Get statistics for continuous non-time-varying covariates
      reportNonTimeVarying2a <-
        covariatesContinuousTemp |>
        dplyr::inner_join(covariateAnalysisId,
                          by = "covariateId"
        ) |>
        dplyr::arrange(dplyr::desc(averageValue)) |>
        dplyr::mutate(periodName = "nonTimeVarying") |>
        dplyr::select(
          "covariateId",
          "covariateName",
          "conceptId",
          "analysisId",
          "analysisName",
          "domainId",
          "periodName",
          dplyr::all_of(distributionStatistic)
        ) |>
        dplyr::filter(averageValue > minAverageValue) |>
        dplyr::collect() |>
        tidyr::pivot_longer(
          cols = dplyr::all_of(distributionStatistic),
          names_to = "statistic",
          values_to = "averageValue"
        ) |>
        dplyr::mutate(statistic = stringr::str_replace(
          string = statistic,
          pattern = "Value",
          replacement = ""
        )) |>
        dplyr::mutate(covariateName = paste0(covariateName, " (", statistic, ")")) |>
        dplyr::select(-statistic)
      
      # Get count values for continuous non-time-varying covariates
      reportNonTimeVarying2b <-
        covariatesContinuousTemp |>
        dplyr::inner_join(covariateAnalysisId,
                          by = "covariateId"
        ) |>
        dplyr::arrange(dplyr::desc(averageValue)) |>
        dplyr::mutate(periodName = "nonTimeVarying") |>
        dplyr::select(
          covariateId,
          periodName,
          countValue
        ) |>
        dplyr::rename(sumValue = countValue) |>
        dplyr::collect()
      
      # Join statistics with counts for continuous non-time-varying covariates
      reportNonTimeVarying2 <- reportNonTimeVarying2a |>
        dplyr::inner_join(reportNonTimeVarying2b,
                          by = c(
                            "covariateId",
                            "periodName"
                          )
        ) |>
        dplyr::mutate(continuous = 1)
    } else {
      reportNonTimeVarying2 <- dplyr::tibble()
    }
    
    # Combine binary and continuous non-time-varying covariates
    reportNonTimeVarying <- dplyr::tibble()
    if (nrow(reportNonTimeVarying1) > 0) {
      reportNonTimeVarying <- dplyr::bind_rows(
        reportNonTimeVarying,
        reportNonTimeVarying1
      )
    }
    if (nrow(reportNonTimeVarying2) > 0) {
      reportNonTimeVarying <- dplyr::bind_rows(
        reportNonTimeVarying,
        reportNonTimeVarying2
      )
    }
    
    # Format the non-time-varying report if needed
    if (all(
      nrow(reportNonTimeVarying) > 0,
      length(colnames(reportNonTimeVarying) > 0),
      format
    )) {
      reportNonTimeVarying <-
        dplyr::bind_rows(
          reportNonTimeVarying |>
            dplyr::filter(continuous == 0) |>
            dplyr::mutate(
              report = formatCountPercent(count = sumValue, percent = averageValue)
            ),
          reportNonTimeVarying |>
            dplyr::filter(continuous == 1) |>
            dplyr::mutate(
              report = formatDecimalWithComma(
                number = averageValue,
                decimalPlaces = 1,
                round = 1
              )
            )
        ) |>
        dplyr::select(-continuous)
    } else {
      reportNonTimeVarying <- dplyr::tibble()
    }
  }
  
  # Combine time-varying and non-time-varying reports
  report <- dplyr::bind_rows(
    reportNonTimeVarying,
    reportTimeVarying
  )
  
  # Process conceptId for custom covariates
  if (all(
    nrow(report) > 0,
    "conceptId" %in% colnames(report)
  )) {
    report <- report |>
      dplyr::mutate(conceptId = dplyr::if_else(
        condition = (conceptId == 0),
        true = (covariateId - analysisId) / 1000,
        false = conceptId
      ))
  }
  
  # Clean up
  rm("covariateAnalysisId")
  
  # Check if we have results
  if (nrow(report) == 0) {
    writeLines("No results")
    return()
  }
  
  # Store raw report before any table1 formatting
  rawReport <- report
  
  # Process table1 specifications if provided
  if (!is.null(table1Specifications)) {
    table1Specifications <- table1Specifications |>
      dplyr::mutate(labelId = dplyr::row_number()) |>
      dplyr::relocate(labelId)
    reportTable1 <- c()
    for (i in (1:nrow(table1Specifications))) {
      reportTable1[[i]] <- table1Specifications[i, ] |>
        dplyr::select(
          labelId,
          label
        ) |>
        tidyr::crossing(report |>
                          dplyr::filter(
                            covariateId %in% commaSeparaedStringToIntArray(table1Specifications[i, ]$covariateIds)
                          ))
      
      if (nrow(reportTable1[[i]]) > 0) {
        reportTable1[[i]] <- dplyr::bind_rows(
          reportTable1[[i]] |>
            dplyr::mutate(source = 2),
          table1Specifications[i, ] |>
            dplyr::mutate(
              covariateId = 0,
              periodName = "",
              covariateName = label
            ) |>
            dplyr::select(
              labelId,
              label,
              covariateId,
              periodName,
              covariateName
            ) |>
            dplyr::mutate(source = 1)
        ) |>
          dplyr::arrange(
            labelId,
            label,
            source
          ) |>
          dplyr::select(-source)
      }
    }
    report <- dplyr::bind_rows(reportTable1)
    
    idCols <- c(
      "labelId",
      "label",
      "covariateId",
      "covariateName",
      "conceptId",
      "analysisId",
      "analysisName",
      "domainId"
    )
  } else {
    idCols <- c(
      "covariateId",
      "covariateName",
      "conceptId",
      "analysisId",
      "analysisName",
      "domainId"
    )
  }
  
  # Pivot the report if requested
  if (pivot) {
    report <- report |>
      tidyr::pivot_wider(
        id_cols = idCols,
        names_from = periodName,
        values_from = report
      )
  }
  
  # Add cohort and database information if provided
  if (!is.null(cohortName)) {
    report <-
      dplyr::bind_rows(
        report |>
          dplyr::slice(0),
        dplyr::tibble(covariateName = cohortName),
        report
      )
  }
  
  if (!is.null(databaseId)) {
    report <- dplyr::bind_rows(
      report |>
        dplyr::slice(0),
      dplyr::tibble(covariateName = databaseId),
      report
    )
  }
  
  if (!is.null(reportName)) {
    report <-
      dplyr::bind_rows(
        report |>
          dplyr::slice(0),
        dplyr::tibble(covariateName = reportName),
        report
      )
  }
  
  # Prepare and return output
  output <- list()
  output$raw <- rawReport
  output$formatted <- report
  return(output)
}



getFeatureExtractionReportCommonSequentialTimePeriods <-  function() {


    priorMonthlyPeriods <- dplyr::tibble(
      timeId = c(15, 21, 23, 25, 27, 29, 31, 33, 36, 38, 41, 44, 47),
      startDay = c(
        -391, -361, -331, -301, -271, -241, -211, -181, -151, -121, -91, -61, -31
      ),
      endDay = c(-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1)
    )

    postMonthlyPeriods <- dplyr::tibble(
      timeId = c(58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70),
      startDay = c(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1),
      endDay = c(1, 31, 61, 91, 121, 151, 181, 211, 241, 271, 301, 331, 361)
    )

    onDayOf <- dplyr::tibble(
      timeId = 53,
      startDay = 0,
      endDay = 0
    )

    timePeriods <- dplyr::bind_rows(
      priorMonthlyPeriods,
      postMonthlyPeriods,
      onDayOf
    ) |>
      dplyr::arrange(timeId)

    return(timePeriods)
  }


getFeatureExtractionReportNonTimeVarying <- function(cdmSources,
           covariateDataPath,
           cohortId,
           cohortDefinitionSet,
           remove = "Visit Count|Chads 2 Vasc|Demographics Index Month|Demographics Post Observation Time|Visit Concept Count|Chads 2|Demographics Prior Observation Time|Dcsi|Demographics Time In Cohort|Demographics Index Year Month") {
    output <-
      getFeatureExtractionReportInParallel(
        cdmSources = cdmSources,
        covariateDataPath = covariateDataPath,
        includeNonTimeVarying = TRUE,
        minAverageValue = 0.01,
        includedCovariateIds = NULL,
        excludedCovariateIds = NULL,
        table1Specifications = NULL,
        simple = TRUE,
        cohortId = cohortId,
        covariateDataFileNamePattern = paste0(cohortId, "$"),
        cohortDefinitionSet = cohortDefinitionSet,
        databaseId = NULL,
        cohortName = NULL,
        reportName = NULL,
        format = TRUE
      )

    if (is.null(output)) {
      return(NULL)
    }

    if (!is.null(remove)) {
      writeLines(paste0(
        "removing from formatted report",
        remove
      ))
      output$formattedFull <- output$formatted
      output$formatted <- output$formatted |>
        dplyr::filter(stringr::str_detect(
          string = label,
          pattern = remove,
          negate = TRUE
        ))
    }

    return(output)
  }

getFeatureExtractionStandardizedDifference <-
  function(covariateData1Path = NULL,
           covariateData2Path = NULL,
           cohortId1,
           cohortId2,
           includeNonTimeVarying = TRUE,
           timeRef = NULL) {
    if (all(is.null(timeRef), !includeNonTimeVarying)) {
      message("includeNonTimeVarying is FASLE and timeRef is NULL. no results.")
      return(NULL)
    }

    if (all(
      is.null(covariateData1Path),
      is.null(covariateData2Path)
    )) {
      stop("covariateData1/2 and path are all NULL")
    }

    covariateData1 <-
      FeatureExtraction::loadCovariateData(file = covariateData1Path)

    covariateData2 <-
      FeatureExtraction::loadCovariateData(file = covariateData2Path)

    timeRef1 <- covariateData1$timeRef |> dplyr::collect()
    timeRef2 <- covariateData2$timeRef |> dplyr::collect()

    compared <-
      OhdsiHelpers::compareTibbles(tibble1 = timeRef1, tibble2 = timeRef2)

    if (!compared$identical) {
      message("covariate data is not identical")
      timeRefFromCovariateData <- timeRef1 |>
        dplyr::inner_join(timeRef2,
          by = c(
            "timeId",
            "startDay",
            "endDay"
          )
        )
    } else {
      timeRefFromCovariateData <- timeRef1
    }

    standardizedDifference <- c()

    if (!is.null(timeRef)) {
      checkmate::assertDataFrame(timeRef)
      if (!"startDay" %in% colnames(timeRef)) {
        stop("please check timeRef")
      }
      if (!"endDay" %in% colnames(timeRef)) {
        stop("please check timeRef")
      }
      timeRef <- timeRefFromCovariateData |>
        dplyr::inner_join(
          timeRef |>
            dplyr::select(
              startDay,
              endDay
            ) |>
            dplyr::distinct(),
          by = c("startDay", "endDay")
        )
    } else {
      timeRef <- timeRefFromCovariateData
    }

    if (nrow(timeRef) == 0) {
      message("no valid time windows")
    }

    for (i in (1:nrow(timeRef))) {
      rowData <- timeRef[i, ]

      message(paste0("working on ", rowData$startDay, " to ", rowData$endDay))
      covariateData1 <-
        FeatureExtraction::loadCovariateData(file = covariateData1Path)
      covariateData1$covariates <- covariateData1$covariates |>
        dplyr::filter(
          timeId == rowData$timeId,
          cohortDefinitionId == cohortId1
        )

      covariateData2 <-
        FeatureExtraction::loadCovariateData(file = covariateData2Path)
      covariateData2$covariates <- covariateData2$covariates |>
        dplyr::filter(
          timeId == rowData$timeId,
          cohortDefinitionId == cohortId2
        )

      standardizedDifference[[i]] <-
        FeatureExtraction::computeStandardizedDifference(
          covariateData1 = covariateData1,
          covariateData2 = covariateData2,
          cohortId1 = cohortId1,
          cohortId2 = cohortId2
        ) |>
        tidyr::crossing(rowData |>
          dplyr::select(
            startDay,
            endDay
          )) |>
        dplyr::relocate(
          startDay,
          endDay,
          covariateId,
          covariateName
        )
    }

    standardizedDifference <-
      dplyr::bind_rows(standardizedDifference)

    if (includeNonTimeVarying) {
      # non time varying
      message("working on non time varying")
      covariateData1 <-
        FeatureExtraction::loadCovariateData(file = covariateData1Path)
      covariateData1$covariates <- covariateData1$covariates |>
        dplyr::filter(
          is.na(timeId),
          cohortDefinitionId == cohortId1
        )

      covariateData2 <-
        FeatureExtraction::loadCovariateData(file = covariateData2Path)
      covariateData2$covariates <- covariateData2$covariates |>
        dplyr::filter(
          is.na(timeId),
          cohortDefinitionId == cohortId2
        )
      standardizedDifferenceNonTimeVarying <-
        FeatureExtraction::computeStandardizedDifference(
          covariateData1 = covariateData1,
          covariateData2 = covariateData2,
          cohortId1 = cohortId1,
          cohortId2 = cohortId2
        )

      standardizedDifference <-
        dplyr::bind_rows(
          standardizedDifference,
          standardizedDifferenceNonTimeVarying
        )
    }
    return(standardizedDifference)
  }


commaSeparaedStringToIntArray <- function(inputString) {
  # Split the string into elements based on commas
  stringElements <- strsplit(inputString, ",")[[1]]
  # Remove empty elements
  stringElements <- stringElements[stringElements != ""]
  # Convert elements to integer
  integerArray <- as.double(stringElements)
  return(integerArray)
}

formatCountPercent <- function (count, percent, percentDigits = 1) 
{
  return(paste0(formatIntegerWithComma(count), " (", formatPercent(percent, 
                                                                   digits = percentDigits), ")"))
}

formatIntegerWithComma <- function (number) 
{
  return(formatC(number, format = "d", big.mark = ","))
}

formatDecimalWithComma <- function (number, decimalPlaces = 1, round = TRUE) 
{
  integerPart <- floor(number)
  decimalPart <- number - integerPart
  if (round) {
    decimalPart <- round(decimalPart, decimalPlaces)
  }
  else {
    decimalPart <- trunc(decimalPart * 10^decimalPlaces)/10^decimalPlaces
  }
  formattedIntegerPart <- formatC(integerPart, format = "d", 
                                  big.mark = ",")
  decimalPartAsString <- formatC(decimalPart, format = "f", 
                                 digits = decimalPlaces)
  formattedDecimalPart <- substr(decimalPartAsString, 3, nchar(decimalPartAsString))
  return(paste(formattedIntegerPart, formattedDecimalPart, 
               sep = "."))
}

formatPercent <- function (x, digits = 2, format = "f", ...) 
{
  paste0(formatC(100 * x, format = format, digits = digits, 
                 ...), "%")
}


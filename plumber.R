Sys.setenv(PINS_CACHE_DIR = "/tmp")

library(pins)
library(plumber)
library(rapidoc)
library(vetiver)
library(jsonlite)
library(xgboost)
library(bundle)  # Required for unbundling

b <- board_folder(path = "/opt/ml/my-pins")
v <- vetiver_pin_read(b, "hotel_boost_model")

# Unbundle the model if it's bundled
if (inherits(v$model, "bundle")) {
  xgb_model <- unbundle(v$model)
  cat("Model unbundled successfully\n")
} else {
  xgb_model <- v$model
  cat("Model was not bundled\n")
}

#' @plumber
function(pr) {
  pr %>%
    # Add logging filter
    pr_filter(
      "logger",
      function(req) {
        # Construct the log message
        log_message <- paste0(
          as.character(Sys.time()),
          " - ",
          req$REQUEST_METHOD,
          " ",
          req$PATH_INFO,
          " - ",
          ifelse(is.null(req$HTTP_USER_AGENT), "Unknown", req$HTTP_USER_AGENT),
          " @ ",
          ifelse(is.null(req$REMOTE_ADDR), "Unknown", req$REMOTE_ADDR),
          "\n"
        )
        
        # 1. Print the log to the console
        cat(log_message)
        
        # 2. Append the log to a file in the /tmp/ directory
        tryCatch({
          cat(log_message, file = "/tmp/hotel_booking_logs.txt", append = TRUE)
        }, error = function(e) {
          cat("Warning: Could not write to log file:", e$message, "\n")
        })
        
        plumber::forward()
      }
    ) %>%
    
    # Root endpoint
    pr_get("/", function() {
      list(msg = "Welcome to the Hotel Booking API!")
    }) %>%
    
    # NEW: Add an endpoint to view the log file
    pr_get("/logs", function(res){
      log_file_path <- "/tmp/hotel_booking_logs.txt"
      if (file.exists(log_file_path)) {
        # Set the content type to plain text
        res$headers$`Content-Type` <- "text/plain"
        # Return the contents of the file
        readLines(log_file_path)
      } else {
        res$status <- 404
        list(error = "Log file not found. Make a prediction first to generate logs.")
      }
    }) %>%

    pr_get("/prediction-logs", function(res){
  log_file_path <- "/tmp/hotel_booking_logs.txt"
  if (file.exists(log_file_path)) {
    # Set the content type to plain text
    res$headers$`Content-Type` <- "text/plain"
    # Return the contents of the file
    readLines(log_file_path)
  } else {
    res$status <- 404
    list(error = "Log file not found. Make a prediction first to generate logs.")
  }
}) %>%

    # Enhanced prediction endpoint with detailed logging
    pr_post("/predict", function(req, res) {
      prediction_start_time <- Sys.time()
      
      tryCatch({
        # Log prediction request details
        cat("📊 PREDICTION REQUEST DETAILS:\n")
        cat("Timestamp:", as.character(prediction_start_time), "\n")
        cat("Content-Type:", ifelse(is.null(req$CONTENT_TYPE), "Not specified", req$CONTENT_TYPE), "\n")
        cat("Request Body Length:", nchar(req$postBody), "characters\n")
        
        # Parse JSON input
        raw_input <- jsonlite::fromJSON(req$postBody)
        cat("Raw input received:", jsonlite::toJSON(raw_input, auto_unbox = TRUE), "\n")
        
        # Log detailed input to file
        input_log <- paste0(
          "PREDICTION_INPUT - ",
          as.character(prediction_start_time),
          " - Input: ",
          jsonlite::toJSON(raw_input, auto_unbox = TRUE),
          "\n"
        )
        tryCatch({
          cat(input_log, file = "/tmp/hotel_booking_logs.txt", append = TRUE)
        }, error = function(e) {
          cat("Warning: Could not log input details\n")
        })
        
        # Convert to proper format
        if (is.list(raw_input) && length(raw_input) > 0) {
          if (is.list(raw_input[[1]])) {
            # Array of objects: [{"col1": val1, "col2": val2}]
            input_df <- do.call(rbind, lapply(raw_input, function(x) {
              as.data.frame(x, stringsAsFactors = FALSE)
            }))
          } else {
            # Single object: {"col1": val1, "col2": val2}
            input_df <- as.data.frame(raw_input, stringsAsFactors = FALSE)
          }
        } else {
          stop("Invalid input format")
        }
        
        # Define expected columns in correct order
        expected_cols <- c("lead_time", "hotel", "deposit_type", "customer_type", 
                           "market_segment", "adults", "children", 
                           "previous_cancellations", "total_of_special_requests")
        
        # Convert all columns to numeric and ensure correct order
        input_df <- input_df[, expected_cols, drop = FALSE]
        for (col in expected_cols) {
          input_df[[col]] <- as.numeric(as.character(input_df[[col]]))
        }
        
        cat("Processed input:\n")
        print(input_df)
        
        # Convert to matrix for XGBoost
        input_matrix <- as.matrix(input_df)
        
        # Create xgb.DMatrix
        dmatrix <- xgb.DMatrix(data = input_matrix)
        
        # Make prediction with unbundled model
        prediction_result <- predict(xgb_model, dmatrix)
        
        prediction_end_time <- Sys.time()
        processing_time <- as.numeric(difftime(prediction_end_time, prediction_start_time, units = "secs"))
        
        cat("✅ PREDICTION SUCCESS:\n")
        cat("Prediction result:", prediction_result, "\n")
        cat("Processing time:", round(processing_time * 1000, 2), "ms\n")
        
        # Log successful prediction to file
        success_log <- paste0(
          "PREDICTION_SUCCESS - ",
          as.character(prediction_end_time),
          " - Result: ",
          prediction_result[1],
          " - Processing time: ",
          round(processing_time * 1000, 2),
          "ms\n"
        )
        tryCatch({
          cat(success_log, file = "/tmp/hotel_booking_logs.txt", append = TRUE)
        }, error = function(e) {
          cat("Warning: Could not log prediction success\n")
        })
        
        # Return in list format
        output <- list(list(.pred = as.numeric(prediction_result[1])))
        
        return(output)
        
      }, error = function(e) {
        prediction_error_time <- Sys.time()
        
        cat("❌ ERROR in prediction:", e$message, "\n")
        print(traceback())
        
        # Log error to file
        error_log <- paste0(
          "PREDICTION_ERROR - ",
          as.character(prediction_error_time),
          " - Error: ",
          e$message,
          "\n"
        )
        tryCatch({
          cat(error_log, file = "/tmp/hotel_booking_logs.txt", append = TRUE)
        }, error = function(err) {
          cat("Warning: Could not log error details\n")
        })
        
        res$status <- 400
        list(error = paste("Prediction error:", e$message))
      })
    }) %>%
    
    # Health check endpoint with logging
    pr_get("/health", function() {
      cat("🏥 HEALTH CHECK - ", as.character(Sys.time()), "\n")
      list(
        status = "healthy",
        timestamp = Sys.time(),
        model_loaded = !is.null(xgb_model),
        api_version = "1.0"
      )
    }) %>%
    
    # Vetiver endpoints except /predict (to avoid conflicts)
    vetiver_api(v, endpoints = c("/ping", "/pin-info"))
}
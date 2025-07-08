# Load libraries
library(tidyverse)
library(xgboost)
library(caret)
library(vetiver)
library(pins)

# Load data
hotel_data <- read.csv("C:/Users/sm2125/Downloads/hotel_bookings.csv")

# clean data
hotel_data_clean <- hotel_data %>%
  select(is_canceled, lead_time, hotel, deposit_type, customer_type, market_segment,
         adults, children, previous_cancellations, total_of_special_requests) %>%
  drop_na()

# Convert categorical columns to factors
hotel_data_clean <- hotel_data_clean %>%
  mutate(across(c(hotel, deposit_type, customer_type, market_segment, is_canceled), as.factor))

# Encode factors to integers
hotel_data_clean <- hotel_data_clean %>%
  mutate(across(where(is.factor), as.integer))

# Adjust is_canceled to be 0/1
hotel_data_clean <- hotel_data_clean %>%
  mutate(is_canceled = is_canceled - 1)

# Split data
set.seed(123)
train_index <- createDataPartition(hotel_data_clean$is_canceled, p = 0.8, list = FALSE)
train_data <- hotel_data_clean[train_index, ]
test_data <- hotel_data_clean[-train_index, ]

# Prepare matrices for xgboost
train_matrix <- xgb.DMatrix(data = as.matrix(select(train_data, -is_canceled)),
                            label = train_data$is_canceled)

test_matrix <- xgb.DMatrix(data = as.matrix(select(test_data, -is_canceled)),
                           label = test_data$is_canceled)

# Train xgboost model
params <- list(
  objective = "binary:logistic",
  eval_metric = "error",
  eta = 0.05,
  max_depth = 6
)

boost_fit <- xgb.train(
  params = params,
  data = train_matrix,
  nrounds = 500,
  watchlist = list(train = train_matrix, eval = test_matrix),
  verbose = 1
)

# Predict on test data
test_preds <- predict(boost_fit, test_matrix)
test_class <- ifelse(test_preds > 0.5, 1, 0)

# Confusion matrix and accuracy
conf_matrix <- confusionMatrix(factor(test_class), factor(test_data$is_canceled))
print(conf_matrix$overall['Accuracy'])

# Vetiver model object creation
v <- vetiver_model(boost_fit, "hotel_boost_model")

# Pin the model
b <- board_folder("my-pins")
b %>% vetiver_pin_write(v)

# Generate plumber API script
vetiver_write_plumber(b, "hotel_boost_model", rsconnect = FALSE)

# Generate Dockerfile for deployment
vetiver_write_docker(v)

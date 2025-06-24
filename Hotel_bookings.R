---
title: "Untitled"
author: "Sai Goutham Manukonda"
date: "2025-06-17"
output: html_document
---

```{r setup, include=FALSE}
knitr::opts_chunk$set(echo = TRUE)

install.packages(c("tidyverse", "randomForest", "caret", "pROC"))

library(tidyverse)
library(randomForest)
library(caret)
library(pROC)

```

## R Markdown

```{r}
# Load your data
hotel_data <- read.csv("C:/Users/sm2125/Downloads/hotel_bookings.csv")

# use a subset of features and remove NAs
hotel_data_clean <- hotel_data %>%
  select(is_canceled, lead_time, hotel, deposit_type, customer_type, market_segment,
         adults, children, previous_cancellations, total_of_special_requests) %>%
  drop_na()

# categorical variables are factors
hotel_data_clean$hotel <- as.factor(hotel_data_clean$hotel)
hotel_data_clean$deposit_type <- as.factor(hotel_data_clean$deposit_type)
hotel_data_clean$customer_type <- as.factor(hotel_data_clean$customer_type)
hotel_data_clean$market_segment <- as.factor(hotel_data_clean$market_segment)
hotel_data_clean$is_canceled <- as.factor(hotel_data_clean$is_canceled)

set.seed(123)
train_index <- createDataPartition(hotel_data_clean$is_canceled, p = 0.8, list = FALSE)
train_data <- hotel_data_clean[train_index, ]
test_data  <- hotel_data_clean[-train_index, ]

rf_model <- randomForest(is_canceled ~ ., data = train_data, ntree = 100, importance = TRUE)
print(rf_model)

# Predict on test set
pred_probs <- predict(rf_model, test_data, type = "prob")[, 2]
pred_classes <- predict(rf_model, test_data)

# Accuracy
conf_matrix <- confusionMatrix(pred_classes, test_data$is_canceled)
print(conf_matrix)

# ROC-AUC
roc_obj <- roc(as.numeric(as.character(test_data$is_canceled)), pred_probs)
auc(roc_obj)



```


```{r}

```

Note that the `echo = FALSE` parameter was added to the code chunk to prevent printing of the R code that generated the plot.

#' Validation and Backtesting Framework
#'
#' Multi-layer validation framework for model accuracy, distribution calibration,
#' and benchmarking against Vegas lines.

#' Validate Simulation Output
#'
#' Layer 1: Basic validation that simulation produces sensible outputs.
#'
#' @param sim_results Simulation results from simulate_game()
#' @return List with validation results and any warnings
#' @export
#' @examples
#' \dontrun{
#' validation <- validate_simulation_output(sim_results)
#' if (validation$passed) {
#'   message("Simulation passed validation")
#' }
#' }
validate_simulation_output <- function(sim_results) {
  checks <- list()
  warnings <- character()

  # Check 1: Reasonable point totals
  team_a_mean <- sim_results$summary$team_a_points$mean
  team_b_mean <- sim_results$summary$team_b_points$mean

  checks$reasonable_points <- team_a_mean >= 80 && team_a_mean <= 150 &&
                             team_b_mean >= 80 && team_b_mean <= 150

  if (!checks$reasonable_points) {
    warnings <- c(warnings, sprintf("Unrealistic point projections: A=%.1f, B=%.1f",
                                   team_a_mean, team_b_mean))
  }

  # Check 2: Reasonable total
  total_mean <- sim_results$summary$total$mean
  checks$reasonable_total <- total_mean >= 160 && total_mean <= 300

  if (!checks$reasonable_total) {
    warnings <- c(warnings, sprintf("Unrealistic total: %.1f", total_mean))
  }

  # Check 3: Reasonable spread
  spread_mean <- sim_results$summary$spread$mean
  checks$reasonable_spread <- abs(spread_mean) <= 50

  if (!checks$reasonable_spread) {
    warnings <- c(warnings, sprintf("Unrealistic spread: %.1f", spread_mean))
  }

  # Check 4: Standard deviations are positive
  checks$positive_sds <- all(c(
    sim_results$summary$team_a_points$sd,
    sim_results$summary$team_b_points$sd,
    sim_results$summary$total$sd,
    sim_results$summary$spread$sd
  ) > 0)

  if (!checks$positive_sds) {
    warnings <- c(warnings, "Zero or negative standard deviations detected")
  }

  # Overall pass/fail
  passed <- all(unlist(checks))

  return(list(
    passed = passed,
    checks = checks,
    warnings = warnings,
    summary = sim_results$summary
  ))
}

#' Validate Distribution Calibration
#'
#' Layer 2: Tests if predicted distributions match observed outcomes using
#' probability integral transform (PIT) and Kolmogorov-Smirnov test.
#'
#' @param historical_sims Historical simulation results
#' @param historical_actuals Actual game outcomes
#' @return List with calibration metrics
#' @export
validate_distribution_calibration <- function(historical_sims, historical_actuals) {
  # Calculate percentiles where actuals fell in predicted distributions
  pit_values <- purrr::map2_dbl(historical_sims, historical_actuals, function(sim, actual) {
    # For spread
    ecdf_spread <- ecdf(sim$simulations$spread)
    pit <- ecdf_spread(actual$spread)
    return(pit)
  })

  # Test if PIT values are uniform (well-calibrated model)
  ks_test <- ks.test(pit_values, "punif")

  # Visual calibration check: bin observed frequencies
  bins <- seq(0, 1, by = 0.1)
  observed_freq <- hist(pit_values, breaks = bins, plot = FALSE)$counts
  expected_freq <- length(pit_values) / 10  # Uniform expectation

  chi_sq_test <- chisq.test(observed_freq, p = rep(1/10, 10))

  # Calculate calibration metrics
  mean_pit <- mean(pit_values)
  spread_too_wide <- mean_pit > 0.55  # Actuals consistently in tails
  spread_too_narrow <- mean_pit < 0.45

  return(list(
    pit_values = pit_values,
    ks_test = ks_test,
    chi_sq_test = chi_sq_test,
    mean_pit = mean_pit,
    calibration_status = dplyr::case_when(
      ks_test$p.value < 0.05 ~ "poorly_calibrated",
      spread_too_wide ~ "spread_too_wide",
      spread_too_narrow ~ "spread_too_narrow",
      TRUE ~ "well_calibrated"
    ),
    recommendation = dplyr::case_when(
      spread_too_wide ~ "Consider reducing variance estimates",
      spread_too_narrow ~ "Consider increasing variance estimates",
      TRUE ~ "Model is well-calibrated"
    )
  ))
}

#' Run Historical Backtest
#'
#' Layer 3: Walk-forward backtesting on historical data.
#'
#' @param historical_data Complete historical dataset
#' @param config Model configuration
#' @param start_date Start date for backtest
#' @param end_date End date for backtest
#' @return Comprehensive backtest results
#' @export
#' @examples
#' \dontrun{
#' backtest <- run_historical_backtest(
#'   historical_data,
#'   model_config,
#'   start_date = as.Date("2024-10-15"),
#'   end_date = as.Date("2025-04-15")
#' )
#'
#' print(backtest$accuracy_metrics)
#' plot_backtest_results(backtest)
#' }
run_historical_backtest <- function(historical_data, config, start_date, end_date) {
  games <- historical_data$games %>%
    dplyr::filter(date >= start_date, date <= end_date) %>%
    dplyr::arrange(date)

  message(sprintf("Running backtest on %d games from %s to %s",
                 nrow(games), start_date, end_date))

  predictions <- list()
  actuals <- list()

  for (i in seq_len(nrow(games))) {
    game <- games[i, ]

    # Get data available before this game (walk-forward)
    team_states <- get_team_states_before(game$date, historical_data)

    # Run pre-game analysis
    analysis <- tryCatch({
      pregame_workflow(
        game_info = list(
          game_id = game$game_id,
          team_a_id = game$team_a_id,
          team_b_id = game$team_b_id,
          date = game$date,
          venue_a = game$venue_a,
          venue_b = game$venue_b
        ),
        team_states = team_states,
        config = config,
        market_lines = NULL
      )
    }, error = function(e) {
      return(NULL)
    })

    if (!is.null(analysis)) {
      predictions[[i]] <- list(
        game_id = game$game_id,
        date = game$date,
        predicted_total = analysis$simulation$summary$total$mean,
        predicted_spread = analysis$simulation$summary$spread$mean,
        predicted_team_a = analysis$simulation$summary$team_a_points$mean,
        predicted_team_b = analysis$simulation$summary$team_b_points$mean
      )

      actuals[[i]] <- list(
        game_id = game$game_id,
        date = game$date,
        actual_total = game$team_a_points + game$team_b_points,
        actual_spread = game$team_a_points - game$team_b_points,
        actual_team_a = game$team_a_points,
        actual_team_b = game$team_b_points
      )
    }

    if (i %% 100 == 0) {
      message(sprintf("Progress: %d / %d games", i, nrow(games)))
    }
  }

  # Convert to data frames
  predictions_df <- dplyr::bind_rows(predictions)
  actuals_df <- dplyr::bind_rows(actuals)

  # Calculate accuracy metrics
  accuracy <- calculate_accuracy_metrics(predictions_df, actuals_df)

  return(list(
    predictions = predictions_df,
    actuals = actuals_df,
    accuracy_metrics = accuracy,
    start_date = start_date,
    end_date = end_date,
    n_games = nrow(predictions_df)
  ))
}

#' Calculate Accuracy Metrics
#'
#' Calculates MAE, RMSE, bias, and correlation for predictions.
#'
#' @param predictions Data frame with predicted values
#' @param actuals Data frame with actual values
#' @return List with accuracy metrics
#' @export
calculate_accuracy_metrics <- function(predictions, actuals) {
  # Join predictions and actuals
  combined <- predictions %>%
    dplyr::left_join(actuals, by = c("game_id", "date"))

  # Calculate errors
  errors <- combined %>%
    dplyr::mutate(
      total_error = predicted_total - actual_total,
      spread_error = predicted_spread - actual_spread,
      team_a_error = predicted_team_a - actual_team_a,
      team_b_error = predicted_team_b - actual_team_b
    )

  # Summary metrics
  metrics <- list(
    total = list(
      mae = mean(abs(errors$total_error), na.rm = TRUE),
      rmse = sqrt(mean(errors$total_error^2, na.rm = TRUE)),
      bias = mean(errors$total_error, na.rm = TRUE),
      correlation = cor(errors$predicted_total, errors$actual_total, use = "complete.obs")
    ),
    spread = list(
      mae = mean(abs(errors$spread_error), na.rm = TRUE),
      rmse = sqrt(mean(errors$spread_error^2, na.rm = TRUE)),
      bias = mean(errors$spread_error, na.rm = TRUE),
      correlation = cor(errors$predicted_spread, errors$actual_spread, use = "complete.obs")
    ),
    team_points = list(
      mae = mean(c(abs(errors$team_a_error), abs(errors$team_b_error)), na.rm = TRUE),
      rmse = sqrt(mean(c(errors$team_a_error^2, errors$team_b_error^2), na.rm = TRUE)),
      bias = mean(c(errors$team_a_error, errors$team_b_error), na.rm = TRUE)
    )
  )

  # Create summary data frame
  summary_df <- data.frame(
    metric = c("Total", "Spread", "Team Points"),
    mae = c(metrics$total$mae, metrics$spread$mae, metrics$team_points$mae),
    rmse = c(metrics$total$rmse, metrics$spread$rmse, metrics$team_points$rmse),
    bias = c(metrics$total$bias, metrics$spread$bias, metrics$team_points$bias),
    correlation = c(metrics$total$correlation, metrics$spread$correlation, NA)
  )

  return(list(
    detailed = metrics,
    summary = summary_df,
    errors = errors
  ))
}

#' Benchmark Against Vegas
#'
#' Layer 4: Compares model accuracy to Vegas closing lines.
#'
#' @param backtest_results Results from run_historical_backtest()
#' @param vegas_lines Vegas closing lines for comparison
#' @return Comparison metrics
#' @export
benchmark_against_vegas <- function(backtest_results, vegas_lines) {
  # Join model predictions with Vegas lines
  comparison <- backtest_results$predictions %>%
    dplyr::left_join(vegas_lines, by = "game_id", suffix = c("_model", "_vegas")) %>%
    dplyr::left_join(backtest_results$actuals, by = "game_id")

  # Calculate errors for both model and Vegas
  comparison <- comparison %>%
    dplyr::mutate(
      model_total_error = abs(predicted_total_model - actual_total),
      vegas_total_error = abs(predicted_total_vegas - actual_total),
      model_spread_error = abs(predicted_spread_model - actual_spread),
      vegas_spread_error = abs(predicted_spread_vegas - actual_spread),
      model_better_total = model_total_error < vegas_total_error,
      model_better_spread = model_spread_error < vegas_spread_error
    )

  # Summary statistics
  summary <- list(
    model_total_mae = mean(comparison$model_total_error, na.rm = TRUE),
    vegas_total_mae = mean(comparison$vegas_total_error, na.rm = TRUE),
    model_spread_mae = mean(comparison$model_spread_error, na.rm = TRUE),
    vegas_spread_mae = mean(comparison$vegas_spread_error, na.rm = TRUE),
    model_wins_total = sum(comparison$model_better_total, na.rm = TRUE),
    model_wins_spread = sum(comparison$model_better_spread, na.rm = TRUE),
    n_games = nrow(comparison)
  )

  summary$model_win_pct_total <- summary$model_wins_total / summary$n_games
  summary$model_win_pct_spread <- summary$model_wins_spread / summary$n_games

  # Statistical test: paired t-test
  t_test_total <- t.test(comparison$model_total_error, comparison$vegas_total_error,
                         paired = TRUE)
  t_test_spread <- t.test(comparison$model_spread_error, comparison$vegas_spread_error,
                          paired = TRUE)

  return(list(
    summary = summary,
    comparison_data = comparison,
    t_test_total = t_test_total,
    t_test_spread = t_test_spread,
    interpretation = list(
      total = ifelse(t_test_total$p.value < 0.05 && summary$model_total_mae < summary$vegas_total_mae,
                    "Model significantly more accurate than Vegas on totals",
                    "Model comparable to Vegas on totals"),
      spread = ifelse(t_test_spread$p.value < 0.05 && summary$model_spread_mae < summary$vegas_spread_mae,
                     "Model significantly more accurate than Vegas on spreads",
                     "Model comparable to Vegas on spreads")
    )
  ))
}

#' Calculate ROI from Historical Bets
#'
#' Simulates betting strategy on historical data and calculates ROI.
#'
#' @param backtest_results Backtest results
#' @param market_odds Historical market odds
#' @param min_ev Minimum EV threshold for betting
#' @param min_edge Minimum probability edge
#' @param bet_size Bet size per game
#' @return ROI analysis
#' @export
calculate_historical_roi <- function(backtest_results, market_odds, min_ev = 0.02,
                                    min_edge = 0.03, bet_size = 100) {
  # Identify bets that would have been placed
  bets <- backtest_results$predictions %>%
    dplyr::left_join(market_odds, by = "game_id") %>%
    dplyr::left_join(backtest_results$actuals, by = "game_id")

  # Calculate implied probabilities and edges
  bets <- bets %>%
    dplyr::mutate(
      spread_cover = actual_spread > spread_line,
      total_over = actual_total > total_line,
      # Additional bet evaluation logic here
    )

  # Calculate profit/loss for each bet
  # (Simplified - implement full betting logic)

  roi_summary <- list(
    total_bets = nrow(bets),
    wins = sum(bets$won, na.rm = TRUE),
    losses = sum(!bets$won, na.rm = TRUE),
    win_rate = mean(bets$won, na.rm = TRUE),
    total_profit = sum(bets$profit, na.rm = TRUE),
    roi = sum(bets$profit, na.rm = TRUE) / (nrow(bets) * bet_size)
  )

  return(roi_summary)
}

#' Plot Backtest Results
#'
#' Creates visualization of backtest performance.
#'
#' @param backtest_results Results from run_historical_backtest()
#' @return List of ggplot objects
#' @export
plot_backtest_results <- function(backtest_results) {
  errors <- backtest_results$accuracy_metrics$errors

  # Prediction vs actual scatter
  p1 <- ggplot2::ggplot(errors, ggplot2::aes(x = predicted_total, y = actual_total)) +
    ggplot2::geom_point(alpha = 0.3) +
    ggplot2::geom_abline(intercept = 0, slope = 1, color = "red", linetype = "dashed") +
    ggplot2::labs(
      title = "Total Points: Predicted vs Actual",
      x = "Predicted Total",
      y = "Actual Total"
    ) +
    ggplot2::theme_minimal()

  # Error distribution
  p2 <- ggplot2::ggplot(errors, ggplot2::aes(x = total_error)) +
    ggplot2::geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7) +
    ggplot2::geom_vline(xintercept = 0, color = "red", linetype = "dashed") +
    ggplot2::labs(
      title = "Total Points Error Distribution",
      x = "Error (Predicted - Actual)",
      y = "Frequency"
    ) +
    ggplot2::theme_minimal()

  # Spread predictions
  p3 <- ggplot2::ggplot(errors, ggplot2::aes(x = predicted_spread, y = actual_spread)) +
    ggplot2::geom_point(alpha = 0.3) +
    ggplot2::geom_abline(intercept = 0, slope = 1, color = "red", linetype = "dashed") +
    ggplot2::labs(
      title = "Spread: Predicted vs Actual",
      x = "Predicted Spread",
      y = "Actual Spread"
    ) +
    ggplot2::theme_minimal()

  return(list(
    total_scatter = p1,
    error_dist = p2,
    spread_scatter = p3
  ))
}

# Helper function
get_team_states_before <- function(date, historical_data) {
  # Template - implement walk-forward state reconstruction
  stop("Implement get_team_states_before for walk-forward validation")
}

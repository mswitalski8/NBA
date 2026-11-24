# Example 1: Running Backfitting Analysis
#
# This example demonstrates how to run the complete backfitting suite
# to empirically determine optimal interaction models.

library(nbabetting)
library(dplyr)
library(ggplot2)

# Load historical data for backfitting
# In a real implementation, this would load from your database or files
historical_data <- list(
  games = data.frame(
    game_id = paste0("game_", 1:500),
    date = seq.Date(as.Date("2024-10-15"), by = "day", length.out = 500),
    team_a_id = sample(c("BOS", "MIL", "PHI", "DAL", "DEN"), 500, replace = TRUE),
    team_b_id = sample(c("LAL", "GSW", "PHX", "MIA", "NYK"), 500, replace = TRUE),
    team_a_points = rnorm(500, 115, 12),
    team_b_points = rnorm(500, 112, 12),
    team_a_fga = rnorm(500, 88, 8),
    team_a_fta = rnorm(500, 24, 6),
    team_a_oreb = rnorm(500, 10, 3),
    team_a_to = rnorm(500, 14, 4),
    team_b_fga = rnorm(500, 86, 8),
    team_b_fta = rnorm(500, 22, 6),
    team_b_oreb = rnorm(500, 9, 3),
    team_b_to = rnorm(500, 13, 4),
    minutes = 48
  ),
  team_metrics = expand.grid(
    team_id = c("BOS", "MIL", "PHI", "DAL", "DEN", "LAL", "GSW", "PHX", "MIA", "NYK"),
    date = seq.Date(as.Date("2024-10-15"), by = "day", length.out = 100)
  ) %>%
    mutate(
      adj_off = rnorm(n(), 115, 5),
      adj_def = rnorm(n(), 113, 5),
      adj_tempo = rnorm(n(), 99, 3)
    )
)

# Calculate actual tempo for games
historical_data$games <- historical_data$games %>%
  mutate(
    team_a_poss = calculate_possessions(team_a_fga, team_a_fta, team_a_oreb, team_a_to),
    team_b_poss = calculate_possessions(team_b_fga, team_b_fta, team_b_oreb, team_b_to),
    actual_tempo = ((team_a_poss + team_b_poss) / 2) * (48 / minutes)
  )

# Run complete backfitting analysis
cat("Running backfitting analysis...\n")
cat("This will test multiple interaction models on historical data.\n\n")

backfit_results <- run_complete_backfitting(
  historical_data = historical_data,
  seasons = c("2024-25")
)

# View offense-defense interaction results
cat("=== Offense-Defense Interaction Models ===\n")
print(backfit_results$offense_defense$summary)
cat("\nSelected Model:", backfit_results$selected_models$offense_defense, "\n\n")

# View tempo interaction results
cat("=== Tempo Interaction Models ===\n")
print(backfit_results$tempo$summary)
cat("\nSelected Model:", backfit_results$selected_models$tempo, "\n\n")

# View rest adjustment results
cat("=== Rest Adjustments ===\n")
print(backfit_results$rest$adjustments)

# Visualize offense-defense model comparison
if (!is.null(backfit_results$offense_defense$simple_average$predictions)) {

  simple_preds <- backfit_results$offense_defense$simple_average$predictions
  mult_preds <- backfit_results$offense_defense$multiplicative$predictions

  # Scatter plot: predicted vs actual totals
  plot_data <- data.frame(
    actual = simple_preds$actual_total,
    simple = simple_preds$predicted_total,
    mult = mult_preds$predicted_total
  )

  p <- ggplot(plot_data, aes(x = actual)) +
    geom_point(aes(y = simple, color = "Simple Average"), alpha = 0.4) +
    geom_point(aes(y = mult, color = "Multiplicative"), alpha = 0.4) +
    geom_abline(intercept = 0, slope = 1, linetype = "dashed", color = "red") +
    labs(
      title = "Offense-Defense Interaction Models: Predicted vs Actual",
      x = "Actual Total Points",
      y = "Predicted Total Points",
      color = "Model"
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")

  print(p)
}

cat("\n=== Backfitting Complete ===\n")
cat("Save these results to use in your model configuration:\n")
cat("- Interaction models determined empirically\n")
cat("- Venue effects calculated (recalculate weekly during season)\n")
cat("- Universal rest/timezone adjustments established\n")

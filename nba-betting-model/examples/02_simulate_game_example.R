# Example 2: Simulating a Single Game
#
# This example shows how to run a Monte Carlo simulation for a single game
# and analyze the probability distributions.

library(nbabetting)
library(ggplot2)
library(dplyr)

# Define team metrics for Dallas Mavericks (home)
mavericks <- list(
  adj_off = 118.5,  # Elite offense
  adj_def = 112.3,  # Average defense
  adj_tempo = 100.2,  # Fast pace
  sd_off = 5.2,  # Based on rolling 30-game window
  sd_def = 4.8,
  sd_tempo = 3.1
)

# Define team metrics for Boston Celtics (away)
celtics <- list(
  adj_off = 120.1,  # Elite offense
  adj_def = 109.5,  # Elite defense
  adj_tempo = 98.5,  # Moderate pace
  sd_off = 4.9,
  sd_def = 5.1,
  sd_tempo = 2.8
)

cat("=== Game Setup ===\n")
cat("Dallas Mavericks (Home) vs Boston Celtics (Away)\n\n")
cat("Dallas Metrics:\n")
cat("  Adj Off: 118.5 pts/100 poss (SD: 5.2)\n")
cat("  Adj Def: 112.3 pts/100 poss (SD: 4.8)\n")
cat("  Adj Tempo: 100.2 poss/48 min (SD: 3.1)\n\n")
cat("Boston Metrics:\n")
cat("  Adj Off: 120.1 pts/100 poss (SD: 4.9)\n")
cat("  Adj Def: 109.5 pts/100 poss (SD: 5.1)\n")
cat("  Adj Tempo: 98.5 poss/48 min (SD: 2.8)\n\n")

# Run Monte Carlo simulation
cat("Running 10,000 Monte Carlo simulations...\n\n")
sim_results <- simulate_game(
  team_a_metrics = mavericks,
  team_b_metrics = celtics,
  interaction_model = "multiplicative",
  n_sims = 10000,
  seed = 123
)

# Validate simulation output
validation <- validate_simulation_output(sim_results)
if (!validation$passed) {
  cat("WARNING: Simulation validation failed!\n")
  print(validation$warnings)
} else {
  cat("✓ Simulation passed validation checks\n\n")
}

# Display summary statistics
cat("=== Simulation Results ===\n\n")

cat("Dallas Mavericks (Team A):\n")
cat(sprintf("  Mean: %.1f points (SD: %.1f)\n",
           sim_results$summary$team_a_points$mean,
           sim_results$summary$team_a_points$sd))
cat(sprintf("  Median: %.1f points\n", sim_results$summary$team_a_points$median))
cat(sprintf("  90%% Range: [%.1f, %.1f]\n",
           sim_results$summary$team_a_points$q05,
           sim_results$summary$team_a_points$q95))
cat("\n")

cat("Boston Celtics (Team B):\n")
cat(sprintf("  Mean: %.1f points (SD: %.1f)\n",
           sim_results$summary$team_b_points$mean,
           sim_results$summary$team_b_points$sd))
cat(sprintf("  Median: %.1f points\n", sim_results$summary$team_b_points$median))
cat(sprintf("  90%% Range: [%.1f, %.1f]\n",
           sim_results$summary$team_b_points$q05,
           sim_results$summary$team_b_points$q95))
cat("\n")

cat("Total Points:\n")
cat(sprintf("  Mean: %.1f points (SD: %.1f)\n",
           sim_results$summary$total$mean,
           sim_results$summary$total$sd))
cat(sprintf("  90%% Range: [%.1f, %.1f]\n",
           sim_results$summary$total$q05,
           sim_results$summary$total$q95))
cat("\n")

cat("Spread (Dallas - Boston):\n")
cat(sprintf("  Mean: %.1f points (SD: %.1f)\n",
           sim_results$summary$spread$mean,
           sim_results$summary$spread$sd))
cat(sprintf("  90%% Range: [%.1f, %.1f]\n",
           sim_results$summary$spread$q05,
           sim_results$summary$spread$q95))
cat("\n")

# Calculate market probabilities for specific lines
market_lines <- list(
  spread = -2.5,  # Boston favored by 2.5
  total = 230.5,
  team_a_total = 115.5,  # Dallas team total
  team_b_total = 115.5   # Boston team total
)

market_probs <- calculate_market_probabilities(sim_results, market_lines)

cat("=== Market Probabilities ===\n\n")
print(market_probs)

# Calculate implied probabilities from typical odds
typical_odds <- data.frame(
  market = c("spread", "total", "team_a_total", "team_b_total"),
  odds = c(-110, -110, -110, -110)  # Standard -110 juice
)

opportunities <- find_betting_opportunities(
  market_probs = market_probs,
  market_odds = typical_odds,
  min_ev = 0.01,  # 1% EV threshold
  min_edge = 0.02  # 2% edge threshold
)

cat("\n=== +EV Betting Opportunities ===\n")
if (nrow(opportunities) > 0) {
  print(opportunities %>% select(market, probability, implied_prob, edge, ev_pct))
} else {
  cat("No +EV opportunities found with current thresholds.\n")
}

# Visualizations
cat("\n=== Creating Visualizations ===\n")

# 1. Spread distribution
p1 <- ggplot(sim_results$simulations, aes(x = spread)) +
  geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7) +
  geom_vline(xintercept = market_lines$spread, color = "red",
             linetype = "dashed", size = 1.2) +
  geom_vline(xintercept = 0, color = "black", linetype = "dotted") +
  annotate("text", x = market_lines$spread, y = Inf, vjust = 2,
           label = sprintf("Line: %.1f", market_lines$spread), color = "red") +
  labs(
    title = "Spread Distribution: Dallas - Boston",
    subtitle = sprintf("Model Mean: %.1f | Market Line: %.1f",
                      sim_results$summary$spread$mean, market_lines$spread),
    x = "Point Differential (Dallas - Boston)",
    y = "Frequency"
  ) +
  theme_minimal()

print(p1)

# 2. Total distribution
p2 <- ggplot(sim_results$simulations, aes(x = total)) +
  geom_histogram(bins = 50, fill = "darkgreen", alpha = 0.7) +
  geom_vline(xintercept = market_lines$total, color = "red",
             linetype = "dashed", size = 1.2) +
  annotate("text", x = market_lines$total, y = Inf, vjust = 2,
           label = sprintf("O/U: %.1f", market_lines$total), color = "red") +
  labs(
    title = "Total Points Distribution",
    subtitle = sprintf("Model Mean: %.1f | Market Total: %.1f",
                      sim_results$summary$total$mean, market_lines$total),
    x = "Total Points",
    y = "Frequency"
  ) +
  theme_minimal()

print(p2)

# 3. Scatter plot: Dallas vs Boston points
p3 <- ggplot(sim_results$simulations, aes(x = team_a_points, y = team_b_points)) +
  geom_bin2d(bins = 40) +
  geom_abline(intercept = 0, slope = 1, color = "red", linetype = "dashed") +
  scale_fill_gradient(low = "lightblue", high = "darkblue") +
  labs(
    title = "Joint Distribution: Team Scores",
    x = "Dallas Points",
    y = "Boston Points",
    fill = "Frequency"
  ) +
  theme_minimal()

print(p3)

cat("\nSimulation complete!\n")

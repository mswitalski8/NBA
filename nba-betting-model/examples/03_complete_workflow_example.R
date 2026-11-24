# Example 3: Complete Daily Workflow
#
# This example demonstrates the complete workflow for a typical day:
# 1. Daily update (process yesterday's games)
# 2. Pre-game analysis for today's slate
# 3. Identify +EV opportunities

library(nbabetting)
library(dplyr)
library(lubridate)

cat("=== NBA Betting Model: Complete Daily Workflow ===\n")
cat("Date:", format(Sys.Date(), "%B %d, %Y"), "\n\n")

# ===========================
# STEP 1: INITIALIZATION
# ===========================
cat("STEP 1: Loading Configuration and Team States\n")
cat("----------------------------------------------\n")

# In a real implementation, you would load these from your database
# This is simulated data for demonstration

# Load model configuration (from backfitting results)
model_config <- list(
  selected_models = list(
    offense_defense = "multiplicative",
    tempo = "simple_avg"
  ),
  rest_adjustments = data.frame(
    rest_category = c("back_to_back", "one_day_rest", "two_day_rest", "extended_rest"),
    off_adjustment = c(-3.0, 0.0, 1.0, 1.5),
    def_adjustment = c(2.0, 0.0, -0.5, -1.0),
    tempo_adjustment = c(-1.5, 0.0, 0.5, 1.0)
  ),
  timezone_adjustments = data.frame(
    timezone_category = c("no_change", "west_to_east", "east_to_west", "minor_change"),
    off_adjustment = c(0.0, -1.5, 0.5, 0.0),
    def_adjustment = c(0.0, 1.0, -0.3, 0.0),
    tempo_adjustment = c(0.0, -0.5, 0.3, 0.0)
  ),
  min_ev = 0.02,
  min_edge = 0.03
)

# Simulated team states (in reality, load from database)
team_states <- list()
teams <- c("BOS", "MIL", "PHI", "DAL", "DEN", "LAL", "GSW", "PHX", "MIA", "NYK")

for (team in teams) {
  team_states[[team]] <- list(
    team_id = team,
    adj_off = rnorm(1, 115, 5),
    adj_def = rnorm(1, 113, 5),
    adj_tempo = rnorm(1, 99, 3),
    sd_off = runif(1, 4, 6),
    sd_def = runif(1, 4, 6),
    sd_tempo = runif(1, 2, 4),
    venue_off_home = rnorm(1, 2, 1),
    venue_def_home = rnorm(1, -1.5, 0.8),
    venue_tempo_home = rnorm(1, 1, 0.5),
    rotation = data.frame(
      player_id = paste0("P", 1:10),
      normalized_minutes = c(35, 32, 28, 25, 22, 20, 18, 15, 12, 33)
    ),
    game_history = data.frame(),
    games_played = 20
  )
}

cat("✓ Configuration loaded\n")
cat("✓ Team states loaded for", length(team_states), "teams\n\n")

# ===========================
# STEP 2: DAILY UPDATE
# ===========================
cat("STEP 2: Daily Update Workflow\n")
cat("----------------------------------------------\n")
cat("Processing yesterday's completed games...\n")

# This would normally fetch from your data sources
# Here we simulate it
update_result <- list(
  status = list(status = "success", steps_completed = c("fetch_dnt", "fetch_games", "update_states")),
  updated_states = team_states
)

if (update_result$status$status == "success") {
  cat("✓ DunksAndThrees data fetched\n")
  cat("✓ Box scores processed\n")
  cat("✓ Team states updated\n")
  team_states <- update_result$updated_states
} else {
  cat("✗ Update failed:", update_result$status$error_message, "\n")
  stop("Cannot proceed without successful update")
}

cat("\n")

# ===========================
# STEP 3: PRE-GAME ANALYSIS
# ===========================
cat("STEP 3: Pre-Game Analysis for Today's Slate\n")
cat("----------------------------------------------\n")

# Today's games (simulated)
games_today <- list(
  list(
    game_id = "2025-12-15-DAL-BOS",
    team_a_id = "DAL",
    team_b_id = "BOS",
    date = Sys.Date(),
    venue_a = "away",
    venue_b = "home",
    tipoff = "19:30"
  ),
  list(
    game_id = "2025-12-15-LAL-GSW",
    team_a_id = "LAL",
    team_b_id = "GSW",
    date = Sys.Date(),
    venue_a = "away",
    venue_b = "home",
    tipoff = "22:00"
  ),
  list(
    game_id = "2025-12-15-MIA-PHI",
    team_a_id = "MIA",
    team_b_id = "PHI",
    date = Sys.Date(),
    venue_a = "home",
    venue_b = "away",
    tipoff = "19:00"
  )
)

cat("Games to analyze:", length(games_today), "\n\n")

# Market lines (simulated - would fetch from odds API)
market_data <- list(
  "2025-12-15-DAL-BOS" = list(spread = -5.5, total = 225.5),
  "2025-12-15-LAL-GSW" = list(spread = 3.5, total = 232.5),
  "2025-12-15-MIA-PHI" = list(spread = -2.5, total = 218.5)
)

# Analyze each game
all_opportunities <- list()

for (i in seq_along(games_today)) {
  game <- games_today[[i]]
  cat(sprintf("Analyzing: %s @ %s\n", game$team_a_id, game$team_b_id))

  # Get team metrics with adjustments
  team_a_state <- team_states[[game$team_a_id]]
  team_b_state <- team_states[[game$team_b_id]]

  # Apply venue adjustments
  if (game$venue_a == "home") {
    team_a_off_adj <- team_a_state$venue_off_home
    team_a_def_adj <- team_a_state$venue_def_home
    team_a_tempo_adj <- team_a_state$venue_tempo_home
  } else {
    team_a_off_adj <- -team_a_state$venue_off_home
    team_a_def_adj <- -team_a_state$venue_def_home
    team_a_tempo_adj <- -team_a_state$venue_tempo_home
  }

  if (game$venue_b == "home") {
    team_b_off_adj <- team_b_state$venue_off_home
    team_b_def_adj <- team_b_state$venue_def_home
    team_b_tempo_adj <- team_b_state$venue_tempo_home
  } else {
    team_b_off_adj <- -team_b_state$venue_off_home
    team_b_def_adj <- -team_b_state$venue_def_home
    team_b_tempo_adj <- -team_b_state$venue_tempo_home
  }

  # Apply rest adjustments (simulated - would calculate from game history)
  rest_adj <- model_config$rest_adjustments %>% filter(rest_category == "one_day_rest")

  # Create adjusted metrics
  team_a_metrics <- list(
    adj_off = team_a_state$adj_off + team_a_off_adj + rest_adj$off_adjustment[1],
    adj_def = team_a_state$adj_def + team_a_def_adj + rest_adj$def_adjustment[1],
    adj_tempo = team_a_state$adj_tempo + team_a_tempo_adj + rest_adj$tempo_adjustment[1],
    sd_off = team_a_state$sd_off,
    sd_def = team_a_state$sd_def,
    sd_tempo = team_a_state$sd_tempo
  )

  team_b_metrics <- list(
    adj_off = team_b_state$adj_off + team_b_off_adj + rest_adj$off_adjustment[1],
    adj_def = team_b_state$adj_def + team_b_def_adj + rest_adj$def_adjustment[1],
    adj_tempo = team_b_state$adj_tempo + team_b_tempo_adj + rest_adj$tempo_adjustment[1],
    sd_off = team_b_state$sd_off,
    sd_def = team_b_state$sd_def,
    sd_tempo = team_b_state$sd_tempo
  )

  # Run simulation
  sim_results <- simulate_game(
    team_a_metrics = team_a_metrics,
    team_b_metrics = team_b_metrics,
    interaction_model = model_config$selected_models$offense_defense,
    n_sims = 10000,
    seed = i * 100
  )

  # Calculate market probabilities
  game_lines <- market_data[[game$game_id]]
  market_probs <- calculate_market_probabilities(sim_results, game_lines)

  # Find opportunities
  market_odds <- data.frame(
    market = c("spread", "total"),
    odds = c(-110, -110)
  )

  opportunities <- find_betting_opportunities(
    market_probs = market_probs,
    market_odds = market_odds,
    min_ev = model_config$min_ev,
    min_edge = model_config$min_edge
  )

  if (nrow(opportunities) > 0) {
    opportunities$game_id <- game$game_id
    opportunities$game_desc <- sprintf("%s @ %s", game$team_a_id, game$team_b_id)
    all_opportunities[[i]] <- opportunities
    cat(sprintf("  → Found %d +EV opportunity(ies)\n", nrow(opportunities)))
  } else {
    cat("  → No +EV opportunities\n")
  }

  cat(sprintf("  Model Total: %.1f | Market: %.1f\n",
             sim_results$summary$total$mean, game_lines$total))
  cat(sprintf("  Model Spread: %.1f | Market: %.1f\n\n",
             sim_results$summary$spread$mean, game_lines$spread))
}

# ===========================
# STEP 4: OPPORTUNITY SUMMARY
# ===========================
cat("STEP 4: +EV Opportunity Summary\n")
cat("----------------------------------------------\n")

if (length(all_opportunities) > 0) {
  all_opps_df <- bind_rows(all_opportunities)

  cat(sprintf("Total +EV opportunities found: %d\n\n", nrow(all_opps_df)))

  # Display sorted by EV
  all_opps_df %>%
    arrange(desc(ev_pct)) %>%
    select(game_desc, market, probability, implied_prob, edge, ev_pct) %>%
    print()

  cat("\n=== Recommended Bets ===\n")
  top_bets <- all_opps_df %>%
    arrange(desc(ev_pct)) %>%
    head(3)

  for (i in seq_len(nrow(top_bets))) {
    bet <- top_bets[i, ]
    cat(sprintf("%d. %s - %s\n", i, bet$game_desc, toupper(bet$market)))
    cat(sprintf("   Model Prob: %.1f%% | Implied Prob: %.1f%%\n",
               bet$probability * 100, bet$implied_prob * 100))
    cat(sprintf("   Edge: %.1f%% | EV: %.2f%%\n\n",
               bet$edge * 100, bet$ev_pct * 100))
  }
} else {
  cat("No +EV opportunities found today.\n")
  cat("Consider:\n")
  cat("  - Lowering EV/edge thresholds\n")
  cat("  - Waiting for line movement\n")
  cat("  - Checking alternative markets\n")
}

cat("\n=== Workflow Complete ===\n")
cat("Next steps:\n")
cat("1. Monitor line movement throughout the day\n")
cat("2. Update projections if injury news breaks\n")
cat("3. Place bets closer to tipoff for best value\n")
cat("4. Run post-game workflow after games complete\n")

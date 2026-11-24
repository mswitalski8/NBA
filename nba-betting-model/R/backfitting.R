#' Backfitting Framework for Interaction Model Testing
#'
#' Implements walk-forward validation for offense-defense and tempo interaction models
#' using historical data to empirically determine optimal model specifications.

#' Test Offense-Defense Interaction Models
#'
#' Compares simple average vs multiplicative interaction models using walk-forward
#' validation on historical data.
#'
#' @param games_data Historical games data frame with columns:
#'        date, team_a_id, team_b_id, team_a_points, team_b_points, possessions
#' @param team_metrics Team metrics by date (team_id, date, adj_off, adj_def, adj_tempo)
#' @param league_avg League average efficiency (default = 115)
#' @return List with MAE results and model comparison
#' @export
#' @examples
#' \dontrun{
#' results <- test_offense_defense_models(games_data, team_metrics)
#' print(results$summary)
#' plot_model_comparison(results)
#' }
test_offense_defense_models <- function(games_data, team_metrics, league_avg = 115) {
  # Initialize result storage
  simple_predictions <- list()
  mult_predictions <- list()

  for (i in seq_len(nrow(games_data))) {
    game <- games_data[i, ]

    # Get team metrics available BEFORE this game
    team_a_prior <- team_metrics %>%
      dplyr::filter(team_id == game$team_a_id, date < game$date) %>%
      dplyr::arrange(dplyr::desc(date)) %>%
      dplyr::slice(1)

    team_b_prior <- team_metrics %>%
      dplyr::filter(team_id == game$team_b_id, date < game$date) %>%
      dplyr::arrange(dplyr::desc(date)) %>%
      dplyr::slice(1)

    if (nrow(team_a_prior) == 0 || nrow(team_b_prior) == 0) {
      next  # Skip if no prior data
    }

    # Calculate expected possessions
    expected_poss <- (team_a_prior$adj_tempo + team_b_prior$adj_tempo) / 2

    # MODEL A: Simple Average
    team_a_eff_simple <- (team_a_prior$adj_off + team_b_prior$adj_def) / 2
    team_a_pts_simple <- team_a_eff_simple * expected_poss / 100

    team_b_eff_simple <- (team_b_prior$adj_off + team_a_prior$adj_def) / 2
    team_b_pts_simple <- team_b_eff_simple * expected_poss / 100

    # MODEL B: Multiplicative
    team_a_pts_mult <- (team_a_prior$adj_off * (team_b_prior$adj_def / league_avg) *
                       expected_poss / 100)
    team_b_pts_mult <- (team_b_prior$adj_off * (team_a_prior$adj_def / league_avg) *
                       expected_poss / 100)

    # Store predictions
    simple_predictions[[i]] <- list(
      predicted_total = team_a_pts_simple + team_b_pts_simple,
      predicted_spread = team_a_pts_simple - team_b_pts_simple,
      actual_total = game$team_a_points + game$team_b_points,
      actual_spread = game$team_a_points - game$team_b_points,
      game_id = game$game_id
    )

    mult_predictions[[i]] <- list(
      predicted_total = team_a_pts_mult + team_b_pts_mult,
      predicted_spread = team_a_pts_mult - team_b_pts_mult,
      actual_total = game$team_a_points + game$team_b_points,
      actual_spread = game$team_a_points - game$team_b_points,
      game_id = game$game_id
    )
  }

  # Convert to data frames
  simple_df <- dplyr::bind_rows(simple_predictions)
  mult_df <- dplyr::bind_rows(mult_predictions)

  # Calculate MAE
  simple_mae_total <- mean(abs(simple_df$predicted_total - simple_df$actual_total), na.rm = TRUE)
  mult_mae_total <- mean(abs(mult_df$predicted_total - mult_df$actual_total), na.rm = TRUE)

  simple_mae_spread <- mean(abs(simple_df$predicted_spread - simple_df$actual_spread), na.rm = TRUE)
  mult_mae_spread <- mean(abs(mult_df$predicted_spread - mult_df$actual_spread), na.rm = TRUE)

  # Determine winner
  improvement_total <- simple_mae_total - mult_mae_total
  improvement_spread <- simple_mae_spread - mult_mae_spread

  winner <- if (improvement_total >= 1.0 || improvement_spread >= 1.0) {
    "multiplicative"
  } else if (improvement_total <= -1.0 || improvement_spread <= -1.0) {
    "simple_average"
  } else {
    "multiplicative"  # Default to multiplicative for theoretical reasons
  }

  return(list(
    simple_average = list(
      mae_total = simple_mae_total,
      mae_spread = simple_mae_spread,
      predictions = simple_df
    ),
    multiplicative = list(
      mae_total = mult_mae_total,
      mae_spread = mult_mae_spread,
      predictions = mult_df
    ),
    improvement = list(
      total = improvement_total,
      spread = improvement_spread
    ),
    winner = winner,
    summary = data.frame(
      model = c("Simple Average", "Multiplicative"),
      mae_total = c(simple_mae_total, mult_mae_total),
      mae_spread = c(simple_mae_spread, mult_mae_spread)
    )
  ))
}

#' Stratified Interaction Model Test
#'
#' Tests interaction models on different matchup types to identify where
#' each model performs best.
#'
#' @param games_data Historical games data
#' @param team_metrics Team metrics by date
#' @return List with stratified results by matchup type
#' @export
test_stratified_interaction <- function(games_data, team_metrics) {
  # Categorize games
  categorized_games <- games_data %>%
    dplyr::mutate(
      matchup_type = purrr::map_chr(seq_len(dplyr::n()), function(i) {
        game <- games_data[i, ]

        team_a_metrics <- team_metrics %>%
          dplyr::filter(team_id == game$team_a_id, date < game$date) %>%
          dplyr::arrange(dplyr::desc(date)) %>%
          dplyr::slice(1)

        team_b_metrics <- team_metrics %>%
          dplyr::filter(team_id == game$team_b_id, date < game$date) %>%
          dplyr::arrange(dplyr::desc(date)) %>%
          dplyr::slice(1)

        if (nrow(team_a_metrics) == 0 || nrow(team_b_metrics) == 0) {
          return(NA_character_)
        }

        diff_a <- abs(team_a_metrics$adj_off - team_b_metrics$adj_def)
        diff_b <- abs(team_b_metrics$adj_off - team_a_metrics$adj_def)
        max_diff <- max(diff_a, diff_b)

        if (max_diff > 15) {
          return("extreme_mismatch")
        } else if (team_a_metrics$adj_off > 120 && team_b_metrics$adj_def < 110) {
          return("elite_matchup")
        } else if (team_a_metrics$adj_off < 110 && team_b_metrics$adj_def > 120) {
          return("terrible_matchup")
        } else {
          return("balanced")
        }
      })
    )

  # Test each category
  categories <- c("extreme_mismatch", "elite_matchup", "terrible_matchup", "balanced")
  results <- list()

  for (cat in categories) {
    cat_games <- categorized_games %>%
      dplyr::filter(matchup_type == cat)

    if (nrow(cat_games) > 0) {
      results[[cat]] <- test_offense_defense_models(cat_games, team_metrics)
      results[[cat]]$sample_size <- nrow(cat_games)
    }
  }

  return(results)
}

#' Test Tempo Interaction Models
#'
#' Compares different tempo interaction models:
#' - Simple average
#' - Weighted by team strength
#' - Faster team dictates
#' - Defensive focus adjustment
#'
#' @param games_data Historical games with actual tempo observations
#' @param team_metrics Team metrics including tempo
#' @param league_avg_def League average defensive efficiency
#' @return List with MAE results for each model
#' @export
test_tempo_models <- function(games_data, team_metrics, league_avg_def = 115) {
  errors <- list(
    simple_avg = numeric(),
    weighted_strength = numeric(),
    faster_dictates = numeric(),
    defensive_focus = numeric()
  )

  for (i in seq_len(nrow(games_data))) {
    game <- games_data[i, ]

    # Get prior team data
    team_a_prior <- team_metrics %>%
      dplyr::filter(team_id == game$team_a_id, date < game$date) %>%
      dplyr::arrange(dplyr::desc(date)) %>%
      dplyr::slice(1)

    team_b_prior <- team_metrics %>%
      dplyr::filter(team_id == game$team_b_id, date < game$date) %>%
      dplyr::arrange(dplyr::desc(date)) %>%
      dplyr::slice(1)

    if (nrow(team_a_prior) == 0 || nrow(team_b_prior) == 0 || is.na(game$actual_tempo)) {
      next
    }

    # Model A: Simple average
    pred_simple <- (team_a_prior$adj_tempo + team_b_prior$adj_tempo) / 2
    errors$simple_avg <- c(errors$simple_avg, abs(pred_simple - game$actual_tempo))

    # Model B: Weighted by strength
    team_a_strength <- team_a_prior$adj_off - team_a_prior$adj_def
    team_b_strength <- team_b_prior$adj_off - team_b_prior$adj_def
    strength_sum <- abs(team_a_strength) + abs(team_b_strength)

    if (strength_sum > 0) {
      pred_weighted <- (abs(team_a_strength) / strength_sum) * team_a_prior$adj_tempo +
                      (abs(team_b_strength) / strength_sum) * team_b_prior$adj_tempo
    } else {
      pred_weighted <- pred_simple
    }
    errors$weighted_strength <- c(errors$weighted_strength, abs(pred_weighted - game$actual_tempo))

    # Model C: Faster dictates
    faster <- max(team_a_prior$adj_tempo, team_b_prior$adj_tempo)
    slower <- min(team_a_prior$adj_tempo, team_b_prior$adj_tempo)
    pred_faster <- 0.6 * faster + 0.4 * slower
    errors$faster_dictates <- c(errors$faster_dictates, abs(pred_faster - game$actual_tempo))

    # Model D: Defensive focus
    avg_tempo <- pred_simple
    def_factor <- (team_a_prior$adj_def + team_b_prior$adj_def) / (2 * league_avg_def)
    pred_def <- avg_tempo * def_factor
    errors$defensive_focus <- c(errors$defensive_focus, abs(pred_def - game$actual_tempo))
  }

  # Calculate MAE for each model
  results <- list()
  for (model_name in names(errors)) {
    results[[model_name]] <- list(
      mae = mean(errors[[model_name]], na.rm = TRUE),
      sample_size = length(errors[[model_name]])
    )
  }

  # Determine winner
  maes <- sapply(results, function(x) x$mae)
  best_model <- names(which.min(maes))
  simple_mae <- results$simple_avg$mae

  winner <- if (abs(simple_mae - min(maes)) <= 0.5) {
    "simple_avg"  # Keep simple if within 0.5 possessions
  } else {
    best_model
  }

  results$winner <- winner
  results$summary <- data.frame(
    model = names(maes),
    mae = maes,
    stringsAsFactors = FALSE
  )

  return(results)
}

#' Calculate Rest Adjustments
#'
#' Analyzes performance by rest category (back-to-back, 1 day, 2 days, 3+ days)
#' and calculates universal rest adjustments.
#'
#' @param games_data Historical games data
#' @param team_metrics Team metrics
#' @return List with rest adjustments for offense, defense, tempo
#' @export
calculate_rest_adjustments <- function(games_data, team_metrics) {
  # Add rest days to each team-game observation
  team_game_data <- games_data %>%
    tidyr::pivot_longer(
      cols = c(team_a_id, team_b_id),
      names_to = "home_away",
      values_to = "team_id"
    ) %>%
    dplyr::arrange(team_id, date)

  # Calculate rest days
  team_game_data <- team_game_data %>%
    dplyr::group_by(team_id) %>%
    dplyr::mutate(
      rest_days = as.numeric(date - dplyr::lag(date)) - 1
    ) %>%
    dplyr::ungroup()

  # Categorize rest
  team_game_data <- team_game_data %>%
    dplyr::mutate(
      rest_category = dplyr::case_when(
        rest_days == 0 ~ "back_to_back",
        rest_days == 1 ~ "one_day_rest",
        rest_days == 2 ~ "two_day_rest",
        rest_days >= 3 ~ "extended_rest",
        TRUE ~ NA_character_
      )
    )

  # Calculate performance by rest category
  rest_performance <- team_game_data %>%
    dplyr::filter(!is.na(rest_category)) %>%
    dplyr::group_by(rest_category) %>%
    dplyr::summarise(
      mean_points = mean(points, na.rm = TRUE),
      mean_points_allowed = mean(points_allowed, na.rm = TRUE),
      sample_size = dplyr::n(),
      .groups = 'drop'
    )

  # Calculate adjustments relative to 1-day baseline
  baseline <- rest_performance %>%
    dplyr::filter(rest_category == "one_day_rest")

  adjustments <- rest_performance %>%
    dplyr::mutate(
      off_adjustment = mean_points - baseline$mean_points,
      def_adjustment = mean_points_allowed - baseline$mean_points_allowed
    )

  return(list(
    performance = rest_performance,
    adjustments = adjustments,
    baseline = baseline
  ))
}

#' Calculate Venue Effects
#'
#' Calculates team-specific home/away adjustments as residuals from
#' expected performance based on interaction models.
#'
#' @param team_id Team to calculate venue effects for
#' @param games_data Historical games data
#' @param team_metrics Team metrics
#' @param interaction_model Selected interaction model ("simple" or "multiplicative")
#' @return List with venue_off_impact, venue_def_impact, venue_tempo_impact
#' @export
calculate_venue_effects <- function(team_id, games_data, team_metrics,
                                   interaction_model = "multiplicative") {
  # Get team's games
  team_games <- games_data %>%
    dplyr::filter(team_a_id == team_id | team_b_id == team_id) %>%
    dplyr::mutate(
      is_home = team_a_id == team_id,
      team_points = ifelse(is_home, team_a_points, team_b_points),
      opp_points = ifelse(is_home, team_b_points, team_a_points)
    )

  # Calculate residuals
  team_games <- team_games %>%
    dplyr::mutate(
      residual_off = purrr::map_dbl(seq_len(dplyr::n()), function(i) {
        # Calculate expected performance and subtract from actual
        # (Simplified - implement full expected calculation)
        NA_real_
      })
    )

  # Separate home and away
  home_games <- team_games %>% dplyr::filter(is_home)
  away_games <- team_games %>% dplyr::filter(!is_home)

  # Calculate weighted residuals
  home_weights <- calculate_decay_weights(nrow(home_games))
  away_weights <- calculate_decay_weights(nrow(away_games))

  home_off_adj <- calculate_weighted_mean(home_games$residual_off, home_weights)
  away_off_adj <- calculate_weighted_mean(away_games$residual_off, away_weights)

  venue_off_impact <- home_off_adj - away_off_adj

  return(list(
    venue_off_impact = venue_off_impact,
    venue_def_impact = NA,  # Implement similarly
    venue_tempo_impact = NA,  # Implement similarly
    home_games = nrow(home_games),
    away_games = nrow(away_games)
  ))
}

#' Run Complete Backfitting Suite
#'
#' Executes all backfitting analyses and returns configuration for model.
#'
#' @param historical_data Complete historical data with games and team metrics
#' @param seasons Seasons to include (e.g., c("2024-25", "2025-26"))
#' @return List with all backfitting results and selected models
#' @export
run_complete_backfitting <- function(historical_data, seasons) {
  message("Starting complete backfitting analysis...")

  # Test offense-defense interaction models
  message("Testing offense-defense interaction models...")
  off_def_results <- test_offense_defense_models(
    historical_data$games,
    historical_data$team_metrics
  )

  # Test tempo models
  message("Testing tempo interaction models...")
  tempo_results <- test_tempo_models(
    historical_data$games,
    historical_data$team_metrics
  )

  # Calculate rest adjustments
  message("Calculating rest adjustments...")
  rest_results <- calculate_rest_adjustments(
    historical_data$games,
    historical_data$team_metrics
  )

  message("Backfitting complete!")

  return(list(
    offense_defense = off_def_results,
    tempo = tempo_results,
    rest = rest_results,
    selected_models = list(
      offense_defense = off_def_results$winner,
      tempo = tempo_results$winner
    )
  ))
}

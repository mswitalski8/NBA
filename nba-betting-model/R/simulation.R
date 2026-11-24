#' Monte Carlo Simulation Engine
#'
#' Implements 10,000-iteration Monte Carlo simulation for NBA game outcomes
#' using normal distributions with rolling 30-game standard deviations.

#' Run Monte Carlo Simulation
#'
#' Simulates game outcomes using team efficiency and tempo distributions.
#' Generates 10,000 iterations to create probability distributions for
#' spreads, totals, team totals, and moneylines.
#'
#' @param team_a_metrics List with team A expected metrics:
#'        adj_off, adj_def, adj_tempo, sd_off, sd_def, sd_tempo
#' @param team_b_metrics List with team B expected metrics (same structure)
#' @param interaction_model Interaction model to use ("simple" or "multiplicative")
#' @param n_sims Number of simulations (default = 10000)
#' @param league_avg League average efficiency for multiplicative model
#' @param seed Random seed for reproducibility
#' @return List with simulation results and market probabilities
#' @export
#' @examples
#' \dontrun{
#' team_a <- list(
#'   adj_off = 118.5, adj_def = 112.3, adj_tempo = 100.2,
#'   sd_off = 5.2, sd_def = 4.8, sd_tempo = 3.1
#' )
#' team_b <- list(
#'   adj_off = 115.2, adj_def = 114.5, adj_tempo = 98.5,
#'   sd_off = 4.9, sd_def = 5.1, sd_tempo = 2.8
#' )
#'
#' results <- simulate_game(team_a, team_b, interaction_model = "multiplicative")
#' print(results$summary)
#' plot_simulation_results(results)
#' }
simulate_game <- function(team_a_metrics, team_b_metrics,
                         interaction_model = "multiplicative",
                         n_sims = 10000,
                         league_avg = 115,
                         seed = NULL) {
  if (!is.null(seed)) {
    set.seed(seed)
  }

  # Sample from distributions
  team_a_off_samples <- rnorm(n_sims, team_a_metrics$adj_off, team_a_metrics$sd_off)
  team_a_def_samples <- rnorm(n_sims, team_a_metrics$adj_def, team_a_metrics$sd_def)
  team_a_tempo_samples <- rnorm(n_sims, team_a_metrics$adj_tempo, team_a_metrics$sd_tempo)

  team_b_off_samples <- rnorm(n_sims, team_b_metrics$adj_off, team_b_metrics$sd_off)
  team_b_def_samples <- rnorm(n_sims, team_b_metrics$adj_def, team_b_metrics$sd_def)
  team_b_tempo_samples <- rnorm(n_sims, team_b_metrics$adj_tempo, team_b_metrics$sd_tempo)

  # Calculate game tempo (simple average)
  game_tempo_samples <- (team_a_tempo_samples + team_b_tempo_samples) / 2

  # Calculate team efficiencies based on interaction model
  if (interaction_model == "multiplicative") {
    team_a_eff_samples <- team_a_off_samples * (team_b_def_samples / league_avg)
    team_b_eff_samples <- team_b_off_samples * (team_a_def_samples / league_avg)
  } else {  # simple average
    team_a_eff_samples <- (team_a_off_samples + team_b_def_samples) / 2
    team_b_eff_samples <- (team_b_off_samples + team_a_def_samples) / 2
  }

  # Calculate points
  team_a_points_samples <- team_a_eff_samples * game_tempo_samples / 100
  team_b_points_samples <- team_b_eff_samples * game_tempo_samples / 100

  # Calculate market outcomes
  total_samples <- team_a_points_samples + team_b_points_samples
  spread_samples <- team_a_points_samples - team_b_points_samples

  # Create results structure
  results <- list(
    simulations = data.frame(
      team_a_points = team_a_points_samples,
      team_b_points = team_b_points_samples,
      total = total_samples,
      spread = spread_samples,
      team_a_off = team_a_eff_samples,
      team_a_def = team_a_def_samples,
      team_b_off = team_b_eff_samples,
      team_b_def = team_b_def_samples,
      tempo = game_tempo_samples
    ),
    summary = list(
      team_a_points = summarize_distribution(team_a_points_samples),
      team_b_points = summarize_distribution(team_b_points_samples),
      total = summarize_distribution(total_samples),
      spread = summarize_distribution(spread_samples)
    ),
    n_sims = n_sims,
    interaction_model = interaction_model,
    inputs = list(team_a = team_a_metrics, team_b = team_b_metrics)
  )

  return(results)
}

#' Summarize Distribution
#'
#' Calculates summary statistics for a simulated distribution.
#'
#' @param samples Numeric vector of simulation outcomes
#' @return List with mean, median, sd, and quantiles
#' @export
summarize_distribution <- function(samples) {
  list(
    mean = mean(samples),
    median = median(samples),
    sd = sd(samples),
    q05 = quantile(samples, 0.05),
    q25 = quantile(samples, 0.25),
    q75 = quantile(samples, 0.75),
    q95 = quantile(samples, 0.95),
    min = min(samples),
    max = max(samples)
  )
}

#' Calculate Market Probabilities
#'
#' Calculates probabilities for specific market lines from simulation results.
#'
#' @param sim_results Results from simulate_game()
#' @param lines List with market lines: spread, total, team_a_total, team_b_total, moneyline
#' @return Data frame with probabilities for each market
#' @export
#' @examples
#' \dontrun{
#' lines <- list(
#'   spread = -5.5,
#'   total = 225.5,
#'   team_a_total = 115.5,
#'   team_b_total = 110.5
#' )
#' probs <- calculate_market_probabilities(sim_results, lines)
#' }
calculate_market_probabilities <- function(sim_results, lines) {
  sims <- sim_results$simulations

  probabilities <- list()

  # Spread probability (team A covers)
  if (!is.null(lines$spread)) {
    probabilities$spread_cover <- mean(sims$spread > lines$spread)
    probabilities$spread_line <- lines$spread
  }

  # Total probability (over)
  if (!is.null(lines$total)) {
    probabilities$total_over <- mean(sims$total > lines$total)
    probabilities$total_line <- lines$total
  }

  # Team A total (over)
  if (!is.null(lines$team_a_total)) {
    probabilities$team_a_over <- mean(sims$team_a_points > lines$team_a_total)
    probabilities$team_a_total_line <- lines$team_a_total
  }

  # Team B total (over)
  if (!is.null(lines$team_b_total)) {
    probabilities$team_b_over <- mean(sims$team_b_points > lines$team_b_total)
    probabilities$team_b_total_line <- lines$team_b_total
  }

  # Moneyline (team A wins)
  probabilities$team_a_ml <- mean(sims$spread > 0)
  probabilities$team_b_ml <- 1 - probabilities$team_a_ml

  # Create data frame
  prob_df <- data.frame(
    market = c("spread", "total", "team_a_total", "team_b_total", "moneyline_a", "moneyline_b"),
    probability = c(
      probabilities$spread_cover %||% NA,
      probabilities$total_over %||% NA,
      probabilities$team_a_over %||% NA,
      probabilities$team_b_over %||% NA,
      probabilities$team_a_ml,
      probabilities$team_b_ml
    ),
    line = c(
      probabilities$spread_line %||% NA,
      probabilities$total_line %||% NA,
      probabilities$team_a_total_line %||% NA,
      probabilities$team_b_total_line %||% NA,
      NA,
      NA
    ),
    stringsAsFactors = FALSE
  )

  return(prob_df)
}

#' Calculate Expected Value
#'
#' Calculates expected value (EV) for a bet given model probability and odds.
#'
#' @param model_prob Model's probability of event occurring (0 to 1)
#' @param odds American odds (e.g., -110, +150)
#' @param bet_size Bet amount (default = 100)
#' @return Expected value of the bet
#' @export
#' @examples
#' # Model says 55% probability, line is -110
#' ev <- calculate_expected_value(0.55, -110)
#'
#' # Model says 30% probability, line is +250
#' ev_underdog <- calculate_expected_value(0.30, 250)
calculate_expected_value <- function(model_prob, odds, bet_size = 100) {
  # Convert American odds to decimal
  if (odds < 0) {
    win_amount <- bet_size * (100 / abs(odds))
  } else {
    win_amount <- bet_size * (odds / 100)
  }

  # Calculate EV
  ev <- (model_prob * win_amount) - ((1 - model_prob) * bet_size)

  return(ev)
}

#' Convert Probability to American Odds
#'
#' Converts probability to American odds format.
#'
#' @param prob Probability (0 to 1)
#' @param vig Vig/juice to add (default = 0.05 for 5%)
#' @return American odds
#' @export
#' @examples
#' # 60% probability
#' odds <- prob_to_american_odds(0.60)
prob_to_american_odds <- function(prob, vig = 0.05) {
  # Adjust for vig
  fair_prob <- prob + vig

  if (fair_prob >= 0.5) {
    # Favorite
    odds <- -100 * (fair_prob / (1 - fair_prob))
  } else {
    # Underdog
    odds <- 100 * ((1 - fair_prob) / fair_prob)
  }

  return(round(odds))
}

#' Find Betting Opportunities
#'
#' Identifies +EV betting opportunities by comparing model probabilities to market odds.
#'
#' @param market_probs Data frame from calculate_market_probabilities()
#' @param market_odds Data frame with columns: market, odds
#' @param min_ev Minimum EV threshold (default = 0.02 for 2%)
#' @param min_edge Minimum probability edge (default = 0.03 for 3%)
#' @return Data frame with +EV opportunities
#' @export
find_betting_opportunities <- function(market_probs, market_odds, min_ev = 0.02, min_edge = 0.03) {
  # Join probabilities with odds
  opportunities <- market_probs %>%
    dplyr::left_join(market_odds, by = "market") %>%
    dplyr::filter(!is.na(odds))

  # Calculate implied probability from odds
  opportunities <- opportunities %>%
    dplyr::mutate(
      implied_prob = dplyr::case_when(
        odds < 0 ~ abs(odds) / (abs(odds) + 100),
        odds > 0 ~ 100 / (odds + 100),
        TRUE ~ NA_real_
      )
    )

  # Calculate edge and EV
  opportunities <- opportunities %>%
    dplyr::mutate(
      edge = probability - implied_prob,
      ev = calculate_expected_value(probability, odds, bet_size = 100),
      ev_pct = ev / 100
    )

  # Filter for +EV opportunities
  plus_ev <- opportunities %>%
    dplyr::filter(ev_pct >= min_ev, edge >= min_edge) %>%
    dplyr::arrange(dplyr::desc(ev_pct))

  return(plus_ev)
}

#' Plot Simulation Distribution
#'
#' Creates visualization of simulation results.
#'
#' @param sim_results Results from simulate_game()
#' @param market_lines Optional market lines to overlay
#' @return ggplot object
#' @export
plot_simulation_distribution <- function(sim_results, market_lines = NULL) {
  sims <- sim_results$simulations

  # Create plots for key markets
  p1 <- ggplot2::ggplot(sims, ggplot2::aes(x = spread)) +
    ggplot2::geom_histogram(bins = 50, fill = "steelblue", alpha = 0.7) +
    ggplot2::labs(
      title = "Spread Distribution",
      x = "Team A - Team B",
      y = "Frequency"
    ) +
    ggplot2::theme_minimal()

  if (!is.null(market_lines$spread)) {
    p1 <- p1 + ggplot2::geom_vline(xintercept = market_lines$spread,
                                    color = "red", linetype = "dashed", size = 1)
  }

  p2 <- ggplot2::ggplot(sims, ggplot2::aes(x = total)) +
    ggplot2::geom_histogram(bins = 50, fill = "darkgreen", alpha = 0.7) +
    ggplot2::labs(
      title = "Total Points Distribution",
      x = "Total Points",
      y = "Frequency"
    ) +
    ggplot2::theme_minimal()

  if (!is.null(market_lines$total)) {
    p2 <- p2 + ggplot2::geom_vline(xintercept = market_lines$total,
                                    color = "red", linetype = "dashed", size = 1)
  }

  return(list(spread_plot = p1, total_plot = p2))
}

#' Simulate Season
#'
#' Runs simulations for multiple games efficiently.
#'
#' @param games_schedule Data frame with game info and team metrics
#' @param interaction_model Interaction model to use
#' @param n_sims Number of simulations per game
#' @return List of simulation results for each game
#' @export
simulate_season <- function(games_schedule, interaction_model = "multiplicative", n_sims = 10000) {
  results <- purrr::map(seq_len(nrow(games_schedule)), function(i) {
    game <- games_schedule[i, ]

    team_a_metrics <- list(
      adj_off = game$team_a_adj_off,
      adj_def = game$team_a_adj_def,
      adj_tempo = game$team_a_adj_tempo,
      sd_off = game$team_a_sd_off,
      sd_def = game$team_a_sd_def,
      sd_tempo = game$team_a_sd_tempo
    )

    team_b_metrics <- list(
      adj_off = game$team_b_adj_off,
      adj_def = game$team_b_adj_def,
      adj_tempo = game$team_b_adj_tempo,
      sd_off = game$team_b_sd_off,
      sd_def = game$team_b_sd_def,
      sd_tempo = game$team_b_sd_tempo
    )

    sim_result <- simulate_game(team_a_metrics, team_b_metrics,
                                interaction_model, n_sims)

    sim_result$game_id <- game$game_id
    sim_result$date <- game$date

    return(sim_result)
  })

  names(results) <- games_schedule$game_id

  return(results)
}

# Helper function for NULL coalescing
`%||%` <- function(x, y) if (is.null(x)) y else x

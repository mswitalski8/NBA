#' Core Mathematical Functions for NBA Betting Model
#'
#' Implements exponential decay weighting, Bayesian updates, and variance calculations
#' as specified in the model design document.

#' Calculate Exponential Decay Weights
#'
#' Calculates weights for historical data using 15-game exponential half-life.
#' Properties:
#' - Most recent game: weight = 1.0
#' - 15 games ago: weight = 0.5
#' - 30 games ago: weight = 0.25
#'
#' @param n Number of games
#' @param half_life Half-life for exponential decay (default = 15 games)
#' @return Vector of weights from most recent (index 1) to oldest (index n)
#' @export
#' @examples
#' # Weights for last 30 games
#' weights <- calculate_decay_weights(30)
#' plot(weights, type = "l", main = "15-Game Exponential Decay")
calculate_decay_weights <- function(n, half_life = 15) {
  # i = 0 (most recent) to i = n-1 (oldest)
  indices <- 0:(n - 1)
  weights <- (0.5)^(indices / half_life)
  return(weights)
}

#' Calculate Weighted Mean
#'
#' Computes weighted average of observations using exponential decay weights.
#'
#' @param values Numeric vector of observations (most recent first)
#' @param weights Optional custom weights. If NULL, uses 15-game half-life
#' @return Weighted mean value
#' @export
#' @examples
#' # Weighted average of last 20 games
#' points <- c(115, 112, 118, 110, 114, 116, 113, 111, 117, 115,
#'             114, 112, 113, 115, 116, 114, 113, 112, 115, 114)
#' weighted_mean <- calculate_weighted_mean(points)
calculate_weighted_mean <- function(values, weights = NULL) {
  if (is.null(weights)) {
    weights <- calculate_decay_weights(length(values))
  }

  weighted_sum <- sum(weights * values)
  sum_weights <- sum(weights)

  return(weighted_sum / sum_weights)
}

#' Calculate Weighted Variance
#'
#' Computes weighted variance where recent volatility is weighted more heavily.
#'
#' @param values Numeric vector of observations (most recent first)
#' @param weighted_mean Pre-calculated weighted mean (optional)
#' @param weights Optional custom weights
#' @return Weighted variance
#' @export
#' @examples
#' values <- c(115, 112, 118, 110, 114, 116, 113, 111, 117, 115)
#' wvar <- calculate_weighted_variance(values)
calculate_weighted_variance <- function(values, weighted_mean = NULL, weights = NULL) {
  if (is.null(weights)) {
    weights <- calculate_decay_weights(length(values))
  }

  if (is.null(weighted_mean)) {
    weighted_mean <- calculate_weighted_mean(values, weights)
  }

  squared_deviations <- (values - weighted_mean)^2
  weighted_var <- sum(weights * squared_deviations) / sum(weights)

  return(weighted_var)
}

#' Bayesian Conjugate Prior Update
#'
#' Updates posterior distribution using conjugate prior for normal distribution.
#' Used specifically for tempo tracking with internal Bayesian updates.
#'
#' @param prior_mean Current baseline (μ₀)
#' @param prior_variance Prior variance (σ₀²)
#' @param observation New observed value (x)
#' @param observation_variance Observation noise parameter (σ²_obs)
#' @return List with posterior_mean and posterior_variance
#' @export
#' @examples
#' # Update tempo estimate after observing new game
#' result <- bayesian_conjugate_update(
#'   prior_mean = 98.5,
#'   prior_variance = 4.2,
#'   observation = 102.3,
#'   observation_variance = 2.0
#' )
bayesian_conjugate_update <- function(prior_mean, prior_variance,
                                      observation, observation_variance) {
  # Posterior variance (always decreases)
  posterior_var <- (prior_variance * observation_variance) /
                   (prior_variance + observation_variance)

  # Posterior mean (weighted combination)
  posterior_mean <- (observation_variance * prior_mean +
                    prior_variance * observation) /
                    (prior_variance + observation_variance)

  return(list(
    posterior_mean = posterior_mean,
    posterior_variance = posterior_var
  ))
}

#' Calculate Hybrid Variance
#'
#' Conservative approach using maximum of weighted and Bayesian variance.
#' - σ²_weighted captures regime changes (can increase)
#' - σ²_bayesian rewards data accumulation (only decreases)
#'
#' @param weighted_variance Variance from weighted historical data
#' @param bayesian_variance Variance from Bayesian posterior
#' @return Maximum of the two variances (conservative estimate)
#' @export
#' @examples
#' hybrid_var <- calculate_hybrid_variance(
#'   weighted_variance = 5.2,
#'   bayesian_variance = 3.8
#' )
calculate_hybrid_variance <- function(weighted_variance, bayesian_variance) {
  return(max(weighted_variance, bayesian_variance))
}

#' Calculate Rolling Standard Deviation
#'
#' Simple rolling window standard deviation for Monte Carlo sampling.
#' Uses last N games (typically 30) with equal weighting.
#'
#' @param values Numeric vector of last N observations
#' @param window_size Number of games in rolling window (default = 30)
#' @return Standard deviation for simulation sampling
#' @export
#' @examples
#' # Last 30 games of adjusted offensive efficiency
#' recent_games <- rnorm(30, mean = 115, sd = 5)
#' rolling_sd <- calculate_rolling_sd(recent_games)
calculate_rolling_sd <- function(values, window_size = 30) {
  n <- length(values)

  if (n < window_size) {
    warning(sprintf("Only %d games available, less than window size %d", n, window_size))
    use_values <- values
  } else {
    # Use most recent window_size games
    use_values <- values[1:window_size]
  }

  return(sd(use_values))
}

#' Normalize Values to Target Sum
#'
#' Normalizes a vector to sum to a target value. Used for rotation normalization
#' to ensure exactly 240 total minutes.
#'
#' @param values Numeric vector to normalize
#' @param target_sum Target sum (default = 240 for NBA game minutes)
#' @return Normalized vector summing to target_sum
#' @export
#' @examples
#' # Normalize rotation minutes to 240
#' raw_minutes <- c(35, 32, 28, 25, 22, 20, 18, 15, 12, 10, 3)
#' normalized <- normalize_to_target(raw_minutes, 240)
#' sum(normalized)  # Should equal 240
normalize_to_target <- function(values, target_sum = 240) {
  current_sum <- sum(values)

  if (current_sum == 0) {
    stop("Cannot normalize: sum of values is zero")
  }

  normalized <- (values / current_sum) * target_sum
  return(normalized)
}

#' League Normalize Value
#'
#' Normalizes a raw metric relative to league average.
#' Used for tempo and other per-possession metrics.
#'
#' @param raw_value Raw observed value
#' @param league_average Current league average for the metric
#' @return League-normalized value
#' @export
#' @examples
#' # Normalize raw tempo to league average
#' adjusted_tempo <- league_normalize(102.5, league_average = 99.8)
league_normalize <- function(raw_value, league_average) {
  return(raw_value - league_average + 100)
}

#' Calculate Possession Count
#'
#' Estimates possessions from box score statistics using standard formula.
#' Formula: Poss = 0.5 × (FGA + 0.475×FTA - OReb + TO)
#'
#' @param fga Field goals attempted
#' @param fta Free throws attempted
#' @param oreb Offensive rebounds
#' @param to Turnovers
#' @return Estimated possessions
#' @export
#' @examples
#' # Calculate possessions from box score
#' possessions <- calculate_possessions(
#'   fga = 88,
#'   fta = 24,
#'   oreb = 10,
#'   to = 14
#' )
calculate_possessions <- function(fga, fta, oreb, to) {
  poss <- 0.5 * (fga + 0.475 * fta - oreb + to)
  return(poss)
}

#' Calculate Efficiency Rating
#'
#' Converts points and possessions to per-100-possession efficiency.
#'
#' @param points Points scored
#' @param possessions Possessions used
#' @return Efficiency rating (points per 100 possessions)
#' @export
#' @examples
#' off_eff <- calculate_efficiency(118, 102.5)
calculate_efficiency <- function(points, possessions) {
  return((points / possessions) * 100)
}

#' Calculate Tempo (Pace)
#'
#' Converts possessions to per-48-minute tempo.
#'
#' @param possessions Total possessions in game
#' @param minutes Game length in minutes (48 for regulation)
#' @return Tempo (possessions per 48 minutes)
#' @export
#' @examples
#' # Calculate tempo from overtime game
#' game_tempo <- calculate_tempo(108, minutes = 53)
calculate_tempo <- function(possessions, minutes = 48) {
  return(possessions * (48 / minutes))
}

#' Adjust Offensive Efficiency (Multiplicative Model)
#'
#' Applies opponent defensive adjustment using multiplicative interaction model.
#'
#' @param team_adj_off Team's adjusted offensive efficiency
#' @param opponent_adj_def Opponent's adjusted defensive efficiency
#' @param league_avg_eff League average efficiency (default = 115)
#' @return Adjusted offensive efficiency
#' @export
#' @examples
#' # Elite offense vs terrible defense
#' adjusted_off <- adjust_offensive_efficiency(
#'   team_adj_off = 120,
#'   opponent_adj_def = 118,
#'   league_avg_eff = 115
#' )
adjust_offensive_efficiency <- function(team_adj_off, opponent_adj_def,
                                       league_avg_eff = 115) {
  def_factor <- opponent_adj_def / league_avg_eff
  adjusted_off <- team_adj_off * def_factor
  return(adjusted_off)
}

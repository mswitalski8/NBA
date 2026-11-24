#' Lineup and Rotation Analysis Functions
#'
#' Implements weighted rotation tracking and lineup impact calculations
#' using player EPM (Estimated Plus-Minus) values from DunksAndThrees.

#' Calculate Weighted Rotation
#'
#' Tracks minutes played with exponential decay and normalizes to 240 minutes.
#' Uses 15-game half-life weighting for recent performance emphasis.
#'
#' @param player_minutes Data frame with columns: player_id, game_index, minutes
#'        where game_index = 0 is most recent game
#' @param half_life Half-life for exponential decay (default = 15)
#' @return Data frame with player_id, weighted_minutes, normalized_minutes
#' @export
#' @examples
#' # Example rotation data
#' rotation_data <- data.frame(
#'   player_id = rep(c("P1", "P2", "P3"), each = 20),
#'   game_index = rep(0:19, 3),
#'   minutes = c(rnorm(20, 35, 3), rnorm(20, 32, 4), rnorm(20, 28, 5))
#' )
#' rotation <- calculate_weighted_rotation(rotation_data)
calculate_weighted_rotation <- function(player_minutes, half_life = 15) {
  # Calculate weights for each game
  player_minutes$weight <- (0.5)^(player_minutes$game_index / half_life)

  # Calculate weighted average minutes per player
  weighted_rotation <- player_minutes %>%
    dplyr::group_by(player_id) %>%
    dplyr::summarise(
      games_played = dplyr::n(),
      raw_weighted_minutes = sum(weight * minutes) / sum(weight),
      .groups = 'drop'
    )

  # Normalize to 240 minutes
  total_raw <- sum(weighted_rotation$raw_weighted_minutes)

  if (total_raw > 0) {
    weighted_rotation$normalized_minutes <-
      (weighted_rotation$raw_weighted_minutes / total_raw) * 240
  } else {
    weighted_rotation$normalized_minutes <- 0
  }

  return(weighted_rotation)
}

#' Calculate Lineup Impact
#'
#' Computes aggregate EPM impact for a rotation, scaled by minutes played.
#' Formula: Σ[(minutes_i / 48) × EPM_i] for each player
#'
#' @param rotation Data frame with columns: player_id, minutes
#' @param player_epm Data frame with columns: player_id, off_epm, def_epm
#' @return List with off_impact and def_impact
#' @export
#' @examples
#' rotation <- data.frame(
#'   player_id = c("Luka", "Kyrie", "PJW"),
#'   minutes = c(34.2, 33.1, 25.0)
#' )
#'
#' epm_data <- data.frame(
#'   player_id = c("Luka", "Kyrie", "PJW"),
#'   off_epm = c(8.0, 5.0, 1.2),
#'   def_epm = c(-3.5, -1.8, -2.1)
#' )
#'
#' impact <- calculate_lineup_impact(rotation, epm_data)
calculate_lineup_impact <- function(rotation, player_epm) {
  # Join rotation with EPM data
  lineup_data <- rotation %>%
    dplyr::left_join(player_epm, by = "player_id")

  # Handle missing EPM data
  lineup_data$off_epm[is.na(lineup_data$off_epm)] <- 0
  lineup_data$def_epm[is.na(lineup_data$def_epm)] <- 0

  # Calculate impact (minutes / 48 * EPM)
  lineup_data$off_contribution <- (lineup_data$minutes / 48) * lineup_data$off_epm
  lineup_data$def_contribution <- (lineup_data$minutes / 48) * lineup_data$def_epm

  # Aggregate impact
  off_impact <- sum(lineup_data$off_contribution)
  def_impact <- sum(lineup_data$def_contribution)

  return(list(
    off_impact = off_impact,
    def_impact = def_impact,
    details = lineup_data
  ))
}

#' Calculate Lineup Adjustment
#'
#' Compares today's expected rotation to baseline rotation to calculate adjustment.
#' Accounts for injuries, rest, and lineup changes.
#'
#' @param baseline_rotation Baseline weighted rotation (player_id, minutes)
#' @param today_rotation Today's projected rotation (player_id, minutes)
#' @param player_epm Player EPM data (player_id, off_epm, def_epm)
#' @param normalize_today Should today's rotation be normalized to 240? (default = TRUE)
#' @return List with off_adjustment, def_adjustment, baseline_impact, today_impact
#' @export
#' @examples
#' baseline <- data.frame(
#'   player_id = c("Luka", "Kyrie", "Others"),
#'   minutes = c(34.2, 33.1, 172.7)
#' )
#'
#' # Luka injured
#' today <- data.frame(
#'   player_id = c("Kyrie", "Dinwiddie", "Others"),
#'   minutes = c(38.0, 30.0, 172.0)
#' )
#'
#' epm <- data.frame(
#'   player_id = c("Luka", "Kyrie", "Dinwiddie", "Others"),
#'   off_epm = c(8.0, 5.0, 0.8, 0.6),
#'   def_epm = c(-3.5, -1.8, 0.2, 0.0)
#' )
#'
#' adjustment <- calculate_lineup_adjustment(baseline, today, epm)
calculate_lineup_adjustment <- function(baseline_rotation, today_rotation,
                                       player_epm, normalize_today = TRUE) {
  # Normalize today's rotation if needed
  if (normalize_today) {
    total_today <- sum(today_rotation$minutes)
    if (total_today != 240 && total_today > 0) {
      today_rotation$minutes <- (today_rotation$minutes / total_today) * 240
    }
  }

  # Calculate baseline impact
  baseline_impact <- calculate_lineup_impact(baseline_rotation, player_epm)

  # Calculate today's impact
  today_impact <- calculate_lineup_impact(today_rotation, player_epm)

  # Calculate adjustments
  off_adjustment <- today_impact$off_impact - baseline_impact$off_impact
  def_adjustment <- today_impact$def_impact - baseline_impact$def_impact

  return(list(
    off_adjustment = off_adjustment,
    def_adjustment = def_adjustment,
    baseline_impact = baseline_impact$off_impact,
    today_impact = today_impact$off_impact,
    baseline_def_impact = baseline_impact$def_impact,
    today_def_impact = today_impact$def_impact,
    baseline_details = baseline_impact$details,
    today_details = today_impact$details
  ))
}

#' Load Player EPM Data
#'
#' Retrieves current player EPM values from database or API.
#' This is a template function - implement based on your data source.
#'
#' @param date Date for EPM values (YYYY-MM-DD)
#' @param source Data source ("database" or "api")
#' @return Data frame with player_id, off_epm, def_epm
#' @export
load_player_epm <- function(date, source = "database") {
  # Template function - implement based on your data infrastructure
  stop("load_player_epm must be implemented for your data source")

  # Example structure:
  # if (source == "database") {
  #   query <- "SELECT player_id, off_epm, def_epm FROM player_epm WHERE date = ?"
  #   epm_data <- dbGetQuery(conn, query, params = list(date))
  # } else if (source == "api") {
  #   # Call DunksAndThrees API
  # }
  #
  # return(epm_data)
}

#' Load Injury Report
#'
#' Retrieves current injury status for all players.
#' This is a template function - implement based on your data source.
#'
#' @param date Date for injury report
#' @return Data frame with player_id, team_id, status (out/questionable/probable/active)
#' @export
load_injury_report <- function(date) {
  # Template function
  stop("load_injury_report must be implemented for your data source")
}

#' Project Today's Rotation
#'
#' Projects today's rotation based on injury report and historical patterns.
#' This is a simplified template - implement more sophisticated projection logic.
#'
#' @param baseline_rotation Baseline weighted rotation
#' @param injury_report Current injury report
#' @param minutes_projections Optional external minutes projections
#' @return Projected rotation (player_id, minutes)
#' @export
project_todays_rotation <- function(baseline_rotation, injury_report,
                                   minutes_projections = NULL) {
  # Remove injured players
  available_players <- baseline_rotation %>%
    dplyr::left_join(injury_report, by = "player_id") %>%
    dplyr::filter(is.na(status) | status %in% c("active", "probable"))

  # If external projections provided, use those
  if (!is.null(minutes_projections)) {
    projected <- available_players %>%
      dplyr::left_join(minutes_projections, by = "player_id") %>%
      dplyr::mutate(minutes = dplyr::coalesce(projected_minutes, minutes)) %>%
      dplyr::select(player_id, minutes)
  } else {
    # Simple redistribution: scale up remaining players
    total_available <- sum(available_players$minutes)
    if (total_available > 0) {
      available_players$minutes <- (available_players$minutes / total_available) * 240
    }
    projected <- available_players %>%
      dplyr::select(player_id, minutes)
  }

  return(projected)
}

#' Aggregate Bench Players
#'
#' Groups low-minute players into aggregate "bench" category for cleaner analysis.
#'
#' @param rotation Rotation data frame
#' @param threshold Minimum minutes to be treated individually (default = 10)
#' @return Rotation with bench players aggregated
#' @export
aggregate_bench_players <- function(rotation, threshold = 10) {
  starters <- rotation %>%
    dplyr::filter(minutes >= threshold)

  bench <- rotation %>%
    dplyr::filter(minutes < threshold)

  if (nrow(bench) > 0) {
    bench_aggregate <- data.frame(
      player_id = "BENCH",
      minutes = sum(bench$minutes)
    )
    result <- dplyr::bind_rows(starters, bench_aggregate)
  } else {
    result <- starters
  }

  return(result)
}

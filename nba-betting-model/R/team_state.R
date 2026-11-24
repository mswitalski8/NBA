#' Team State Management
#'
#' Functions for tracking and updating team state including efficiency metrics,
#' tempo, rotation, and variance calculations.

#' Initialize Team State
#'
#' Creates initial team state structure from backfitting results and historical data.
#'
#' @param team_id Team identifier
#' @param initial_metrics Initial metrics from DunksAndThrees (adj_off, adj_def)
#' @param initial_tempo Initial tempo estimate
#' @param historical_games Last 60 games for initialization
#' @param backfit_results Backfitting results for venue effects
#' @return List containing complete team state
#' @export
#' @examples
#' \dontrun{
#' team_state <- initialize_team_state(
#'   team_id = "DAL",
#'   initial_metrics = list(adj_off = 118.5, adj_def = 112.3),
#'   initial_tempo = 100.2,
#'   historical_games = dal_history,
#'   backfit_results = backfit
#' )
#' }
initialize_team_state <- function(team_id, initial_metrics, initial_tempo,
                                  historical_games, backfit_results) {
  # Calculate weighted rotation from recent games
  rotation_data <- historical_games %>%
    dplyr::select(game_index, player_id, minutes) %>%
    dplyr::arrange(game_index)

  weighted_rotation <- calculate_weighted_rotation(rotation_data)

  # Calculate rolling standard deviations (last 30 games)
  recent_30 <- historical_games %>%
    dplyr::arrange(dplyr::desc(date)) %>%
    dplyr::slice(1:min(30, dplyr::n()))

  sd_off <- sd(recent_30$adj_off)
  sd_def <- sd(recent_30$adj_def)
  sd_tempo <- sd(recent_30$adj_tempo)

  # Initialize Bayesian tempo tracking
  tempo_variance_weighted <- calculate_weighted_variance(recent_30$adj_tempo)
  tempo_variance_bayesian <- tempo_variance_weighted  # Initial state

  # Get venue effects from backfitting
  venue_effects <- backfit_results$venue_effects[[team_id]]

  # Create state structure
  state <- list(
    team_id = team_id,
    last_update = Sys.Date(),

    # Current metrics (from DnT)
    adj_off = initial_metrics$adj_off,
    adj_def = initial_metrics$adj_def,
    adj_tempo = initial_tempo,

    # Standard deviations for simulation
    sd_off = sd_off,
    sd_def = sd_def,
    sd_tempo = sd_tempo,

    # Tempo variance tracking
    tempo_variance_weighted = tempo_variance_weighted,
    tempo_variance_bayesian = tempo_variance_bayesian,
    tempo_variance_hybrid = max(tempo_variance_weighted, tempo_variance_bayesian),

    # Weighted rotation (normalized to 240 minutes)
    rotation = weighted_rotation,

    # Venue effects
    venue_off_home = venue_effects$venue_off_impact %||% 0,
    venue_def_home = venue_effects$venue_def_impact %||% 0,
    venue_tempo_home = venue_effects$venue_tempo_impact %||% 0,

    # Game history (maintain 60 game rolling window)
    game_history = historical_games,

    # Metadata
    games_played = nrow(historical_games),
    season = extract_season(Sys.Date())
  )

  class(state) <- c("nba_team_state", "list")

  return(state)
}

#' Update Team State After Game
#'
#' Updates all team state components after a game is completed.
#' Implements Bayesian tempo updates, weighted rotation updates,
#' and rolling variance recalculation.
#'
#' @param team_state Current team state
#' @param game_data Completed game data including box score
#' @param new_dnt_metrics Updated metrics from DunksAndThrees
#' @param observation_variance Observation variance for Bayesian update (default = 2.0)
#' @return Updated team state
#' @export
update_team_state <- function(team_state, game_data, new_dnt_metrics,
                              observation_variance = 2.0) {
  # Update efficiency metrics from DnT (authoritative source)
  team_state$adj_off <- new_dnt_metrics$adj_off
  team_state$adj_def <- new_dnt_metrics$adj_def

  # Calculate observed tempo from box score
  observed_tempo <- game_data$tempo

  # Bayesian tempo update
  bayesian_result <- bayesian_conjugate_update(
    prior_mean = team_state$adj_tempo,
    prior_variance = team_state$tempo_variance_bayesian,
    observation = observed_tempo,
    observation_variance = observation_variance
  )

  team_state$adj_tempo <- bayesian_result$posterior_mean
  team_state$tempo_variance_bayesian <- bayesian_result$posterior_variance

  # Update weighted tempo variance
  recent_tempo <- c(observed_tempo, team_state$game_history$adj_tempo)
  team_state$tempo_variance_weighted <- calculate_weighted_variance(recent_tempo)

  # Calculate hybrid variance
  team_state$tempo_variance_hybrid <- calculate_hybrid_variance(
    team_state$tempo_variance_weighted,
    team_state$tempo_variance_bayesian
  )

  # Update game history
  new_game_record <- data.frame(
    date = game_data$date,
    opponent = game_data$opponent_id,
    venue = game_data$venue,
    adj_off = new_dnt_metrics$adj_off,
    adj_def = new_dnt_metrics$adj_def,
    adj_tempo = observed_tempo,
    points = game_data$points,
    points_allowed = game_data$points_allowed,
    possessions = game_data$possessions
  )

  team_state$game_history <- dplyr::bind_rows(
    new_game_record,
    team_state$game_history
  ) %>%
    dplyr::slice(1:60)  # Keep only last 60 games

  # Update rolling standard deviations (last 30 games)
  recent_30 <- team_state$game_history %>%
    dplyr::slice(1:min(30, dplyr::n()))

  team_state$sd_off <- calculate_rolling_sd(recent_30$adj_off, window_size = 30)
  team_state$sd_def <- calculate_rolling_sd(recent_30$adj_def, window_size = 30)
  team_state$sd_tempo <- calculate_rolling_sd(recent_30$adj_tempo, window_size = 30)

  # Update weighted rotation (if player minutes provided)
  if (!is.null(game_data$player_minutes)) {
    rotation_data <- team_state$game_history %>%
      dplyr::mutate(game_index = dplyr::row_number() - 1) %>%
      tidyr::unnest(cols = player_minutes) %>%
      dplyr::select(game_index, player_id, minutes)

    team_state$rotation <- calculate_weighted_rotation(rotation_data)
  }

  # Update metadata
  team_state$last_update <- Sys.Date()
  team_state$games_played <- team_state$games_played + 1

  return(team_state)
}

#' Calculate Game Adjustments
#'
#' Calculates all adjustments for a specific game: lineup, venue, rest, timezone.
#'
#' @param team_state Current team state
#' @param game_context Game context (opponent, venue, rest_days, timezone_diff)
#' @param player_epm Current player EPM data
#' @param injury_report Current injury report
#' @param rest_adjustments Universal rest adjustments from backfitting
#' @param timezone_adjustments Universal timezone adjustments from backfitting
#' @return List with all adjustments
#' @export
calculate_game_adjustments <- function(team_state, game_context, player_epm,
                                      injury_report, rest_adjustments,
                                      timezone_adjustments) {
  adjustments <- list()

  # 1. Lineup adjustment
  today_rotation <- project_todays_rotation(
    team_state$rotation,
    injury_report %>% dplyr::filter(team_id == team_state$team_id)
  )

  lineup_adj <- calculate_lineup_adjustment(
    team_state$rotation,
    today_rotation,
    player_epm
  )

  adjustments$lineup_off <- lineup_adj$off_adjustment
  adjustments$lineup_def <- lineup_adj$def_adjustment

  # 2. Venue adjustment
  if (game_context$venue == "home") {
    adjustments$venue_off <- team_state$venue_off_home
    adjustments$venue_def <- team_state$venue_def_home
    adjustments$venue_tempo <- team_state$venue_tempo_home
  } else {
    adjustments$venue_off <- -team_state$venue_off_home
    adjustments$venue_def <- -team_state$venue_def_home
    adjustments$venue_tempo <- -team_state$venue_tempo_home
  }

  # 3. Rest adjustment
  rest_category <- categorize_rest(game_context$rest_days)
  rest_adj <- rest_adjustments %>%
    dplyr::filter(rest_category == !!rest_category)

  adjustments$rest_off <- rest_adj$off_adjustment %||% 0
  adjustments$rest_def <- rest_adj$def_adjustment %||% 0
  adjustments$rest_tempo <- rest_adj$tempo_adjustment %||% 0

  # 4. Timezone adjustment
  tz_category <- categorize_timezone(game_context$timezone_diff)
  tz_adj <- timezone_adjustments %>%
    dplyr::filter(timezone_category == !!tz_category)

  adjustments$timezone_off <- tz_adj$off_adjustment %||% 0
  adjustments$timezone_def <- tz_adj$def_adjustment %||% 0
  adjustments$timezone_tempo <- tz_adj$tempo_adjustment %||% 0

  # Total adjustments
  adjustments$total_off <- adjustments$lineup_off + adjustments$venue_off +
                          adjustments$rest_off + adjustments$timezone_off
  adjustments$total_def <- adjustments$lineup_def + adjustments$venue_def +
                          adjustments$rest_def + adjustments$timezone_def
  adjustments$total_tempo <- adjustments$venue_tempo + adjustments$rest_tempo +
                            adjustments$timezone_tempo

  return(adjustments)
}

#' Apply Adjustments to Metrics
#'
#' Applies calculated adjustments to baseline metrics.
#'
#' @param baseline_metrics Baseline metrics (adj_off, adj_def, adj_tempo)
#' @param adjustments Adjustments from calculate_game_adjustments()
#' @return Adjusted metrics ready for simulation
#' @export
apply_adjustments <- function(baseline_metrics, adjustments) {
  adjusted <- list(
    adj_off = baseline_metrics$adj_off + adjustments$total_off,
    adj_def = baseline_metrics$adj_def + adjustments$total_def,
    adj_tempo = baseline_metrics$adj_tempo + adjustments$total_tempo,
    sd_off = baseline_metrics$sd_off,
    sd_def = baseline_metrics$sd_def,
    sd_tempo = baseline_metrics$sd_tempo
  )

  return(adjusted)
}

#' Categorize Rest Days
#'
#' Converts rest days to category for adjustment lookup.
#'
#' @param rest_days Number of days since last game
#' @return Rest category string
#' @export
categorize_rest <- function(rest_days) {
  dplyr::case_when(
    rest_days == 0 ~ "back_to_back",
    rest_days == 1 ~ "one_day_rest",
    rest_days == 2 ~ "two_day_rest",
    rest_days >= 3 ~ "extended_rest",
    TRUE ~ "one_day_rest"  # Default
  )
}

#' Categorize Timezone Difference
#'
#' Converts timezone difference to category.
#'
#' @param tz_diff Timezone difference in hours (positive = traveling east)
#' @return Timezone category string
#' @export
categorize_timezone <- function(tz_diff) {
  dplyr::case_when(
    tz_diff == 0 ~ "no_change",
    tz_diff <= -2 ~ "west_to_east",  # Traveling east (harder)
    tz_diff >= 2 ~ "east_to_west",   # Traveling west (easier)
    TRUE ~ "minor_change"
  )
}

#' Extract Season from Date
#'
#' Determines NBA season from date (e.g., "2024-25").
#'
#' @param date Date object
#' @return Season string
#' @export
extract_season <- function(date) {
  year <- lubridate::year(date)
  month <- lubridate::month(date)

  # NBA season runs Oct-Jun
  if (month >= 10) {
    season <- paste0(year, "-", substr(year + 1, 3, 4))
  } else {
    season <- paste0(year - 1, "-", substr(year, 3, 4))
  }

  return(season)
}

#' Save Team State
#'
#' Serializes team state to database or file.
#'
#' @param team_state Team state object
#' @param connection Database connection or file path
#' @export
save_team_state <- function(team_state, connection) {
  # Template function - implement based on storage backend
  stop("save_team_state must be implemented for your storage backend")
}

#' Load Team State
#'
#' Loads team state from database or file.
#'
#' @param team_id Team identifier
#' @param connection Database connection or file path
#' @return Team state object
#' @export
load_team_state <- function(team_id, connection) {
  # Template function - implement based on storage backend
  stop("load_team_state must be implemented for your storage backend")
}

#' Update All Teams
#'
#' Batch update all teams after daily data refresh.
#'
#' @param team_states List of all team states
#' @param completed_games Games completed since last update
#' @param new_dnt_data New DunksAndThrees data
#' @return Updated list of team states
#' @export
update_all_teams <- function(team_states, completed_games, new_dnt_data) {
  # Get unique teams that played
  teams_that_played <- unique(c(completed_games$team_a_id, completed_games$team_b_id))

  # Update each team
  updated_states <- purrr::map(teams_that_played, function(team_id) {
    team_state <- team_states[[team_id]]

    # Get team's games
    team_games <- completed_games %>%
      dplyr::filter(team_a_id == team_id | team_b_id == team_id)

    # Get new metrics
    new_metrics <- new_dnt_data %>%
      dplyr::filter(team_id == !!team_id)

    # Update state for each game
    for (i in seq_len(nrow(team_games))) {
      game <- team_games[i, ]
      team_state <- update_team_state(team_state, game, new_metrics)
    }

    return(team_state)
  })

  names(updated_states) <- teams_that_played

  # Merge with unchanged teams
  all_states <- team_states
  all_states[teams_that_played] <- updated_states

  return(all_states)
}

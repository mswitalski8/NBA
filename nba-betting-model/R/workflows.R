#' Operational Workflows
#'
#' Complete workflows for daily updates, pre-game analysis, and post-game processing.

#' Daily Update Workflow
#'
#' Executes complete daily update: scrape DnT data, update team states,
#' recalculate venue effects (weekly), and prepare for today's games.
#'
#' @param team_states List of current team states
#' @param config Model configuration including backfitting results
#' @param date Date to update (default = today)
#' @param update_venue_effects Update venue effects? (default = weekly check)
#' @return List with updated_states and status
#' @export
#' @examples
#' \dontrun{
#' result <- daily_update_workflow(
#'   team_states = all_team_states,
#'   config = model_config,
#'   date = Sys.Date()
#' )
#'
#' if (result$status == "success") {
#'   all_team_states <- result$updated_states
#' }
#' }
daily_update_workflow <- function(team_states, config, date = Sys.Date(),
                                  update_venue_effects = NULL) {
  message(sprintf("Starting daily update for %s...", date))

  workflow_status <- list(
    date = date,
    start_time = Sys.time(),
    steps_completed = character(),
    errors = list()
  )

  tryCatch({
    # Step 1: Scrape DunksAndThrees data
    message("Step 1: Fetching DunksAndThrees data...")
    dnt_data <- fetch_dunksandthrees_data(date)
    workflow_status$steps_completed <- c(workflow_status$steps_completed, "fetch_dnt")

    # Step 2: Get completed games from yesterday
    message("Step 2: Loading completed games...")
    yesterday <- date - 1
    completed_games <- fetch_completed_games(yesterday)
    workflow_status$steps_completed <- c(workflow_status$steps_completed, "fetch_games")

    # Step 3: Get box scores for completed games
    message("Step 3: Fetching box scores...")
    box_scores <- fetch_box_scores(completed_games$game_id)
    workflow_status$steps_completed <- c(workflow_status$steps_completed, "fetch_boxscores")

    # Step 4: Update team states for teams that played
    message("Step 4: Updating team states...")
    updated_states <- update_all_teams(
      team_states = team_states,
      completed_games = completed_games,
      new_dnt_data = dnt_data
    )
    workflow_status$steps_completed <- c(workflow_status$steps_completed, "update_states")

    # Step 5: Check if venue effects need updating (weekly)
    if (is.null(update_venue_effects)) {
      update_venue_effects <- lubridate::wday(date) == 2  # Monday
    }

    if (update_venue_effects) {
      message("Step 5: Recalculating venue effects...")
      updated_states <- update_all_venue_effects(updated_states, config)
      workflow_status$steps_completed <- c(workflow_status$steps_completed, "update_venue")
    }

    workflow_status$status <- "success"
    workflow_status$end_time <- Sys.time()
    workflow_status$duration <- difftime(workflow_status$end_time,
                                        workflow_status$start_time,
                                        units = "mins")

    message(sprintf("Daily update completed successfully in %.2f minutes",
                   as.numeric(workflow_status$duration)))

    return(list(
      updated_states = updated_states,
      status = workflow_status,
      dnt_data = dnt_data,
      completed_games = completed_games
    ))

  }, error = function(e) {
    workflow_status$status <- "error"
    workflow_status$error_message <- as.character(e)
    workflow_status$end_time <- Sys.time()

    warning(sprintf("Daily update failed: %s", e$message))

    return(list(
      updated_states = team_states,  # Return unchanged
      status = workflow_status
    ))
  })
}

#' Pre-Game Workflow
#'
#' Complete pre-game analysis workflow: load team states, calculate adjustments,
#' run simulation, calculate market probabilities, identify +EV opportunities.
#'
#' @param game_info Game information (team_a_id, team_b_id, date, time)
#' @param team_states Current team states
#' @param config Model configuration
#' @param market_lines Current market lines (spread, total, etc.)
#' @return List with simulation results, probabilities, and opportunities
#' @export
#' @examples
#' \dontrun{
#' game <- list(
#'   game_id = "2025-12-15-DAL-BOS",
#'   team_a_id = "DAL",
#'   team_b_id = "BOS",
#'   date = as.Date("2025-12-15"),
#'   venue_a = "away",
#'   venue_b = "home"
#' )
#'
#' lines <- list(spread = -5.5, total = 225.5)
#'
#' analysis <- pregame_workflow(game, team_states, model_config, lines)
#' print(analysis$opportunities)
#' }
pregame_workflow <- function(game_info, team_states, config, market_lines = NULL) {
  message(sprintf("Pre-game analysis: %s @ %s", game_info$team_a_id, game_info$team_b_id))

  # Step 1: Load team states
  team_a_state <- team_states[[game_info$team_a_id]]
  team_b_state <- team_states[[game_info$team_b_id]]

  # Step 2: Get external inputs
  player_epm <- load_player_epm(game_info$date)
  injury_report <- load_injury_report(game_info$date)

  # Step 3: Calculate game context
  team_a_context <- list(
    venue = game_info$venue_a,
    rest_days = calculate_rest_days_from_state(team_a_state, game_info$date),
    timezone_diff = calculate_timezone_diff(team_a_state, game_info)
  )

  team_b_context <- list(
    venue = game_info$venue_b,
    rest_days = calculate_rest_days_from_state(team_b_state, game_info$date),
    timezone_diff = calculate_timezone_diff(team_b_state, game_info)
  )

  # Step 4: Calculate adjustments for both teams
  team_a_adjustments <- calculate_game_adjustments(
    team_a_state, team_a_context, player_epm,
    injury_report, config$rest_adjustments, config$timezone_adjustments
  )

  team_b_adjustments <- calculate_game_adjustments(
    team_b_state, team_b_context, player_epm,
    injury_report, config$rest_adjustments, config$timezone_adjustments
  )

  # Step 5: Apply adjustments to baseline metrics
  team_a_metrics <- list(
    adj_off = team_a_state$adj_off + team_a_adjustments$total_off,
    adj_def = team_a_state$adj_def + team_a_adjustments$total_def,
    adj_tempo = team_a_state$adj_tempo + team_a_adjustments$total_tempo,
    sd_off = team_a_state$sd_off,
    sd_def = team_a_state$sd_def,
    sd_tempo = team_a_state$sd_tempo
  )

  team_b_metrics <- list(
    adj_off = team_b_state$adj_off + team_b_adjustments$total_off,
    adj_def = team_b_state$adj_def + team_b_adjustments$total_def,
    adj_tempo = team_b_state$adj_tempo + team_b_adjustments$total_tempo,
    sd_off = team_b_state$sd_off,
    sd_def = team_b_state$sd_def,
    sd_tempo = team_b_state$sd_tempo
  )

  # Step 6: Run simulation
  sim_results <- simulate_game(
    team_a_metrics = team_a_metrics,
    team_b_metrics = team_b_metrics,
    interaction_model = config$selected_models$offense_defense,
    n_sims = 10000
  )

  # Step 7: Calculate market probabilities
  market_probs <- NULL
  opportunities <- NULL

  if (!is.null(market_lines)) {
    market_probs <- calculate_market_probabilities(sim_results, market_lines)

    # Step 8: Identify +EV opportunities
    if (!is.null(config$market_odds)) {
      opportunities <- find_betting_opportunities(
        market_probs,
        config$market_odds,
        min_ev = config$min_ev %||% 0.02,
        min_edge = config$min_edge %||% 0.03
      )
    }
  }

  # Return comprehensive analysis
  return(list(
    game_info = game_info,
    team_a = list(
      state = team_a_state,
      adjustments = team_a_adjustments,
      final_metrics = team_a_metrics
    ),
    team_b = list(
      state = team_b_state,
      adjustments = team_b_adjustments,
      final_metrics = team_b_metrics
    ),
    simulation = sim_results,
    market_probabilities = market_probs,
    opportunities = opportunities,
    timestamp = Sys.time()
  ))
}

#' Post-Game Workflow
#'
#' Processes completed game: retrieve box score, calculate observed metrics,
#' compute residuals, update team states.
#'
#' @param game_id Game identifier
#' @param team_states Current team states
#' @param config Model configuration
#' @return Updated team states and game analysis
#' @export
postgame_workflow <- function(game_id, team_states, config) {
  message(sprintf("Processing post-game: %s", game_id))

  # Step 1: Retrieve box score
  box_score <- fetch_box_score(game_id)

  # Step 2: Calculate observed metrics
  observed_metrics <- calculate_observed_metrics(box_score)

  # Step 3: Get pre-game expectations (if stored)
  pregame_expectations <- load_pregame_expectations(game_id)

  # Step 4: Calculate residuals
  if (!is.null(pregame_expectations)) {
    residuals <- calculate_residuals(observed_metrics, pregame_expectations)
  } else {
    residuals <- NULL
  }

  # Step 5: Update team states
  team_a_id <- box_score$team_a_id
  team_b_id <- box_score$team_b_id

  # Prepare game data for team A
  team_a_game_data <- list(
    date = box_score$date,
    opponent_id = team_b_id,
    venue = box_score$team_a_venue,
    points = box_score$team_a_points,
    points_allowed = box_score$team_b_points,
    possessions = observed_metrics$team_a_possessions,
    tempo = observed_metrics$tempo,
    player_minutes = box_score$team_a_player_minutes
  )

  # Prepare game data for team B
  team_b_game_data <- list(
    date = box_score$date,
    opponent_id = team_a_id,
    venue = box_score$team_b_venue,
    points = box_score$team_b_points,
    points_allowed = box_score$team_a_points,
    possessions = observed_metrics$team_b_possessions,
    tempo = observed_metrics$tempo,
    player_minutes = box_score$team_b_player_minutes
  )

  # Update states
  team_states[[team_a_id]] <- update_team_state(
    team_states[[team_a_id]],
    team_a_game_data,
    observed_metrics$team_a_metrics
  )

  team_states[[team_b_id]] <- update_team_state(
    team_states[[team_b_id]],
    team_b_game_data,
    observed_metrics$team_b_metrics
  )

  return(list(
    updated_states = team_states,
    observed_metrics = observed_metrics,
    residuals = residuals,
    box_score = box_score
  ))
}

#' Calculate Rest Days from State
#'
#' Helper to calculate rest days from team state.
#'
#' @param team_state Team state object
#' @param game_date Date of upcoming game
#' @return Number of rest days
#' @export
calculate_rest_days_from_state <- function(team_state, game_date) {
  if (nrow(team_state$game_history) == 0) {
    return(1)  # Default
  }

  last_game_date <- team_state$game_history$date[1]
  rest_days <- as.numeric(game_date - last_game_date) - 1

  return(max(0, rest_days))
}

#' Calculate Timezone Difference
#'
#' Calculates timezone difference for traveling team.
#'
#' @param team_state Team state
#' @param game_info Game information
#' @return Timezone difference in hours
#' @export
calculate_timezone_diff <- function(team_state, game_info) {
  # Template - implement based on team location data
  return(0)
}

#' Calculate Observed Metrics from Box Score
#'
#' Extracts and calculates all relevant metrics from box score.
#'
#' @param box_score Box score data
#' @return List with observed efficiency and tempo metrics
#' @export
calculate_observed_metrics <- function(box_score) {
  # Calculate possessions for both teams
  team_a_poss <- calculate_possessions(
    box_score$team_a_fga,
    box_score$team_a_fta,
    box_score$team_a_oreb,
    box_score$team_a_to
  )

  team_b_poss <- calculate_possessions(
    box_score$team_b_fga,
    box_score$team_b_fta,
    box_score$team_b_oreb,
    box_score$team_b_to
  )

  avg_poss <- (team_a_poss + team_b_poss) / 2

  # Calculate efficiencies
  team_a_off_eff <- calculate_efficiency(box_score$team_a_points, team_a_poss)
  team_b_off_eff <- calculate_efficiency(box_score$team_b_points, team_b_poss)

  # Calculate tempo
  game_tempo <- calculate_tempo(avg_poss, box_score$minutes)

  return(list(
    team_a_possessions = team_a_poss,
    team_b_possessions = team_b_poss,
    tempo = game_tempo,
    team_a_metrics = list(
      adj_off = team_a_off_eff,
      adj_def = team_b_off_eff
    ),
    team_b_metrics = list(
      adj_off = team_b_off_eff,
      adj_def = team_a_off_eff
    )
  ))
}

#' Calculate Residuals
#'
#' Calculates residuals between observed and expected performance.
#'
#' @param observed Observed metrics
#' @param expected Pre-game expectations
#' @return List with residuals
#' @export
calculate_residuals <- function(observed, expected) {
  list(
    team_a_off_residual = observed$team_a_metrics$adj_off - expected$team_a_expected_off,
    team_a_def_residual = observed$team_a_metrics$adj_def - expected$team_a_expected_def,
    team_b_off_residual = observed$team_b_metrics$adj_off - expected$team_b_expected_off,
    team_b_def_residual = observed$team_b_metrics$adj_def - expected$team_b_expected_def,
    tempo_residual = observed$tempo - expected$expected_tempo
  )
}

#' Batch Pre-Game Analysis
#'
#' Runs pre-game analysis for multiple games efficiently.
#'
#' @param games_today List of games to analyze
#' @param team_states Current team states
#' @param config Model configuration
#' @param market_data Market lines for all games
#' @return List of pre-game analyses
#' @export
batch_pregame_analysis <- function(games_today, team_states, config, market_data = NULL) {
  message(sprintf("Running batch analysis for %d games...", length(games_today)))

  analyses <- purrr::map(games_today, function(game) {
    # Get market lines for this game
    game_lines <- if (!is.null(market_data)) {
      market_data[[game$game_id]]
    } else {
      NULL
    }

    # Run pre-game workflow
    analysis <- pregame_workflow(game, team_states, config, game_lines)

    return(analysis)
  })

  names(analyses) <- sapply(games_today, function(g) g$game_id)

  # Summarize opportunities
  all_opportunities <- purrr::map_dfr(analyses, function(a) {
    if (!is.null(a$opportunities)) {
      a$opportunities %>%
        dplyr::mutate(game_id = a$game_info$game_id)
    }
  })

  return(list(
    analyses = analyses,
    opportunities = all_opportunities,
    timestamp = Sys.time()
  ))
}

# Template data loading functions (implement based on your data sources)

fetch_dunksandthrees_data <- function(date) {
  stop("Implement fetch_dunksandthrees_data for your data source")
}

fetch_completed_games <- function(date) {
  stop("Implement fetch_completed_games for your data source")
}

fetch_box_scores <- function(game_ids) {
  stop("Implement fetch_box_scores for your data source")
}

fetch_box_score <- function(game_id) {
  stop("Implement fetch_box_score for your data source")
}

load_pregame_expectations <- function(game_id) {
  # Return NULL if not stored
  return(NULL)
}

update_all_venue_effects <- function(team_states, config) {
  # Recalculate venue effects for all teams
  message("Recalculating venue effects (weekly update)...")
  return(team_states)
}

#' nbabetting: Bayesian NBA Betting Model with Monte Carlo Simulation
#'
#' A comprehensive Bayesian betting model for NBA games that generates
#' probability distributions for spreads, totals, team totals, and moneylines.
#'
#' @description
#' This package implements a sophisticated statistical framework that combines:
#' \itemize{
#'   \item DunksAndThrees integration for adjusted efficiency metrics
#'   \item Internal tempo tracking with Bayesian conjugate prior updates
#'   \item Lineup impact analysis using player EPM values
#'   \item Monte Carlo simulation (10,000 iterations per game)
#'   \item Walk-forward validation and backfitting framework
#' }
#'
#' @section Key Features:
#' \itemize{
#'   \item \strong{75/25 Philosophy}: 15-game exponential half-life balances
#'         recent performance (75\%) with stable team identity (25\%)
#'   \item \strong{Multiplicative Interactions}: Empirically tested offense-defense
#'         interaction models
#'   \item \strong{Venue-Specific Effects}: Team-specific home/away adjustments
#'         recalculated weekly
#'   \item \strong{Universal Adjustments}: Back-to-back, rest, and timezone effects
#'         from historical data
#'   \item \strong{Multi-Layer Validation}: Distribution calibration and Vegas
#'         benchmarking
#' }
#'
#' @section Main Functions:
#' \describe{
#'   \item{\code{\link{simulate_game}}}{Run Monte Carlo simulation for a game}
#'   \item{\code{\link{pregame_workflow}}}{Complete pre-game analysis workflow}
#'   \item{\code{\link{daily_update_workflow}}}{Process daily updates}
#'   \item{\code{\link{run_complete_backfitting}}}{Empirical model selection}
#'   \item{\code{\link{calculate_lineup_adjustment}}}{Lineup impact from injuries}
#'   \item{\code{\link{find_betting_opportunities}}}{Identify +EV bets}
#' }
#'
#' @section Mathematical Foundations:
#' The model uses several key mathematical techniques:
#' \describe{
#'   \item{Exponential Decay Weighting}{weight_i = (0.5)^(games_ago_i / 15)}
#'   \item{Bayesian Updates}{Conjugate prior for tempo tracking}
#'   \item{Rolling Variance}{30-game window for simulation sampling}
#'   \item{Lineup Impact}{EPM-based adjustments: Σ[(minutes_i / 48) × EPM_i]}
#' }
#'
#' @section Getting Started:
#' See the package vignettes for detailed tutorials:
#' \itemize{
#'   \item \code{vignette("quickstart", package = "nbabetting")}
#'   \item \code{vignette("backfitting", package = "nbabetting")}
#'   \item \code{vignette("simulation", package = "nbabetting")}
#' }
#'
#' @docType package
#' @name nbabetting-package
#' @aliases nbabetting
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
## usethis namespace: end
NULL

# NBA Betting Model: Bayesian Monte Carlo Simulation

[![R](https://img.shields.io/badge/R-%3E%3D4.0.0-blue)](https://www.r-project.org/)

A comprehensive Bayesian betting model for NBA games that generates probability distributions for spreads, totals, team totals, and moneylines using Monte Carlo simulation.

## Overview

This model implements a sophisticated statistical framework that combines:
- **DunksAndThrees Integration**: Leverages industry-leading adjusted efficiency metrics
- **Internal Tempo Tracking**: Bayesian conjugate prior updates with 15-game exponential half-life
- **Lineup Impact Analysis**: Player-level EPM adjustments for injuries and rotation changes
- **Monte Carlo Simulation**: 10,000 iterations per game with normal distributions
- **Walk-Forward Validation**: Empirical backfitting to determine optimal interaction models

### Key Features

- **75/25 Philosophy**: 15-game exponential half-life balances recent performance (75%) with stable team identity (25%)
- **Multiplicative Interactions**: Empirically tested offense-defense interaction models
- **Venue-Specific Effects**: Team-specific home/away adjustments recalculated weekly
- **Universal Adjustments**: Back-to-back, rest, and timezone effects from historical data
- **Multi-Layer Validation**: Comprehensive testing including distribution calibration and Vegas benchmarking

## Model Architecture

### Mathematical Foundations

#### Exponential Decay Weighting
```r
weight_i = (0.5)^(games_ago_i / 15)

# Properties:
# - Most recent game: weight = 1.0
# - 15 games ago: weight = 0.5
# - 30 games ago: weight = 0.25
```

#### Bayesian Tempo Updates
```r
# Posterior variance (always decreases)
σ²_post = (σ₀² × σ²_obs) / (σ₀² + σ²_obs)

# Posterior mean (weighted combination)
μ_post = (σ²_obs × μ₀ + σ₀² × x) / (σ₀² + σ²_obs)
```

#### Lineup Impact Calculation
```r
# Aggregate EPM impact
off_impact = Σ[(minutes_i / 48) × OFF_EPM_i]

# Adjustment for today's game
lineup_adj = today_impact - baseline_impact
```

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                   Data Sources                          │
│  - DunksAndThrees (adj efficiency, player EPM)          │
│  - NBA Box Scores (possessions, tempo)                  │
│  - Injury Reports (player availability)                 │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│              Backfitting Framework                      │
│  - Test interaction models (offense-defense, tempo)     │
│  - Calculate venue effects (team-specific)              │
│  - Determine rest/timezone adjustments (universal)      │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│               Team State Tracking                       │
│  - Weighted rotation (15-game half-life)                │
│  - Bayesian tempo updates                               │
│  - Rolling variance (30-game window)                    │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│              Pre-Game Workflow                          │
│  - Calculate lineup adjustments (injuries)              │
│  - Apply venue effects (home/away)                      │
│  - Add rest and timezone adjustments                    │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│          Monte Carlo Simulation Engine                  │
│  - 10,000 iterations per game                           │
│  - Normal distributions (efficiency, tempo)             │
│  - Interaction models (backfit-determined)              │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│           Market Analysis & Betting                     │
│  - Calculate market probabilities                       │
│  - Compute expected value (EV)                          │
│  - Identify +EV opportunities                           │
└─────────────────────────────────────────────────────────┘
```

## Installation

```r
# Install from GitHub
devtools::install_github("yourusername/nba-betting-model")

# Or install locally
devtools::install("path/to/nba-betting-model")

# Load package
library(nbabetting)
```

### Dependencies

```r
# Required packages
install.packages(c(
  "dplyr", "tidyr", "purrr", "tibble", "ggplot2",
  "lubridate", "httr", "jsonlite", "DBI", "RSQLite",
  "glue", "scales"
))
```

## Quick Start

### 1. Run Backfitting Analysis

```r
# Load historical data
historical_data <- load_historical_data(
  seasons = c("2024-25", "2025-26"),
  source = "database"
)

# Run complete backfitting suite
backfit_results <- run_complete_backfitting(
  historical_data = historical_data,
  seasons = c("2024-25", "2025-26")
)

# View results
print(backfit_results$selected_models)
# $offense_defense: "multiplicative"
# $tempo: "simple_avg"
```

### 2. Initialize Team States

```r
# Initialize all team states from historical data
team_states <- initialize_all_teams(
  historical_data = historical_data,
  backfit_results = backfit_results,
  date = Sys.Date()
)

# View a team's state
team_states[["DAL"]]
```

### 3. Simulate a Game

```r
# Define game
game_info <- list(
  game_id = "2025-12-15-DAL-BOS",
  team_a_id = "DAL",
  team_b_id = "BOS",
  date = as.Date("2025-12-15"),
  venue_a = "away",
  venue_b = "home"
)

# Market lines
market_lines <- list(
  spread = -5.5,  # BOS favored by 5.5
  total = 225.5
)

# Run pre-game analysis
analysis <- pregame_workflow(
  game_info = game_info,
  team_states = team_states,
  config = model_config,
  market_lines = market_lines
)

# View results
print(analysis$simulation$summary)
print(analysis$market_probabilities)
print(analysis$opportunities)
```

### 4. Find +EV Opportunities

```r
# Analyze today's games
games_today <- get_todays_games()

# Batch analysis
results <- batch_pregame_analysis(
  games_today = games_today,
  team_states = team_states,
  config = model_config,
  market_data = current_market_lines
)

# View all +EV opportunities
results$opportunities %>%
  dplyr::arrange(desc(ev_pct)) %>%
  dplyr::select(game_id, market, probability, implied_prob, edge, ev_pct)
```

### 5. Daily Update Workflow

```r
# Run daily update (after games complete)
update_result <- daily_update_workflow(
  team_states = team_states,
  config = model_config,
  date = Sys.Date()
)

# Update your team states
if (update_result$status$status == "success") {
  team_states <- update_result$updated_states
}
```

## Validation & Backtesting

### Historical Backtest

```r
# Run walk-forward backtest
backtest <- run_historical_backtest(
  historical_data = historical_data,
  config = model_config,
  start_date = as.Date("2024-10-15"),
  end_date = as.Date("2025-04-15")
)

# View accuracy metrics
print(backtest$accuracy_metrics$summary)
#   metric        mae  rmse   bias correlation
#   Total        10.2  12.8   0.4      0.72
#   Spread        9.8  12.1  -0.2      0.68
#   Team Points   7.1   9.2   0.1      NA

# Plot results
plots <- plot_backtest_results(backtest)
plots$total_scatter
plots$error_dist
```

### Benchmark Against Vegas

```r
# Compare to Vegas closing lines
vegas_comparison <- benchmark_against_vegas(
  backtest_results = backtest,
  vegas_lines = vegas_closing_lines
)

print(vegas_comparison$summary)
# Model Total MAE: 10.2
# Vegas Total MAE: 10.5
# Model Win %: 51.2%

print(vegas_comparison$interpretation)
```

### Distribution Calibration

```r
# Test distribution calibration
calibration <- validate_distribution_calibration(
  historical_sims = backtest$simulations,
  historical_actuals = backtest$actuals
)

print(calibration$calibration_status)
# "well_calibrated"

print(calibration$recommendation)
# "Model is well-calibrated"
```

## Advanced Usage

### Custom Backfitting

```r
# Test specific interaction model
results <- test_offense_defense_models(
  games_data = historical_data$games,
  team_metrics = historical_data$team_metrics,
  league_avg = 115
)

# View model comparison
results$summary
#   model              mae_total  mae_spread
#   Simple Average          10.8        10.2
#   Multiplicative          10.1         9.6

# Stratified analysis
stratified <- test_stratified_interaction(
  games_data = historical_data$games,
  team_metrics = historical_data$team_metrics
)
```

### Lineup Analysis

```r
# Calculate lineup impact
lineup_adj <- calculate_lineup_adjustment(
  baseline_rotation = team_states[["DAL"]]$rotation,
  today_rotation = projected_rotation,
  player_epm = current_epm_data
)

print(lineup_adj$off_adjustment)  # -5.4 pts/100 (Luka out)
print(lineup_adj$def_adjustment)  # +2.1 pts/100 (worse defense)
```

### Venue Effect Tracking

```r
# View team venue effects
team_states[["DEN"]]$venue_off_home  # +4.5 (altitude advantage)
team_states[["LAL"]]$venue_off_home  # +2.2 (typical home advantage)

# Recalculate weekly
updated_states <- update_all_venue_effects(
  team_states = team_states,
  config = model_config
)
```

## Project Structure

```
nba-betting-model/
├── R/
│   ├── math_core.R          # Mathematical functions (weighting, Bayesian, variance)
│   ├── lineup_analysis.R    # Rotation tracking and lineup impact
│   ├── backfitting.R        # Interaction model testing framework
│   ├── simulation.R         # Monte Carlo simulation engine
│   ├── team_state.R         # Team state management
│   ├── workflows.R          # Daily, pre-game, post-game workflows
│   └── validation.R         # Validation and backtesting framework
├── data/                    # Example datasets
├── man/                     # Documentation
├── tests/                   # Unit tests
├── examples/                # Usage examples
├── vignettes/               # Detailed tutorials
├── DESCRIPTION             # Package metadata
└── README.md               # This file
```

## Technical Highlights for Employers

### Statistical Rigor
- **Bayesian Methodology**: Proper conjugate prior updates with variance tracking
- **Exponential Decay Weighting**: Theoretically sound 15-game half-life (75/25 philosophy)
- **Walk-Forward Validation**: No look-ahead bias in historical testing
- **Distribution Calibration**: PIT analysis and KS tests for model validation

### Software Engineering
- **Modular Architecture**: Clean separation of concerns across 7 core modules
- **Functional Programming**: Extensive use of purrr, dplyr pipelines
- **Error Handling**: Comprehensive try-catch blocks and validation
- **Documentation**: Roxygen2 documentation for all exported functions
- **Testing**: Unit tests with testthat framework

### Data Engineering
- **Efficient Computation**: Vectorized operations, batch processing
- **State Management**: Rolling windows, incremental updates
- **Database Integration**: Templates for SQLite, SQL Server, APIs
- **Workflow Orchestration**: Daily updates, batch simulations

### Sports Analytics Domain Knowledge
- **NBA-Specific**: Possessions formula, EPM metrics, back-to-backs, altitude
- **Market Analysis**: EV calculation, implied probability, +EV identification
- **Realistic Constraints**: 240-minute rotation normalization, injury handling

## Model Performance (Hypothetical)

*Note: These are target metrics based on the model specification. Actual performance requires real data.*

| Metric | Target | Interpretation |
|--------|--------|----------------|
| Total MAE | ≤ 10.5 pts | Within 1.5 possessions |
| Spread MAE | ≤ 10.0 pts | Competitive with Vegas |
| Calibration | p > 0.05 | Well-calibrated distributions |
| Vegas Win % | ≥ 50% | Comparable accuracy |
| +EV ROI | ≥ 3% | Positive long-term returns |

## Limitations & Future Work

### Current Limitations
1. **Data Requirements**: Assumes access to DunksAndThrees API (paid subscription)
2. **Phase 1 Only**: MVP focuses on main markets (spreads, totals, team totals, moneylines)
3. **Template Functions**: Data fetching functions need implementation for specific sources
4. **No Live Betting**: Pre-game only in Phase 1

### Future Enhancements (Phase 2 & 3)
- NBA Cup and playoff situational adjustments
- Player props (points, rebounds, assists)
- Halves and quarters (1H pregame, live 2H, 1Q pregame, live 3Q/4Q)
- Real-time lineup optimization
- Machine learning for venue effect estimation

## References

### Model Inspiration
- **DunksAndThrees**: Industry-leading adjusted efficiency metrics
- **FiveThirtyEight**: ELO-based NBA predictions
- **Haslametrics**: Advanced NBA analytics

### Statistical Methods
- Gelman, A. et al. (2013). *Bayesian Data Analysis*
- James, G. et al. (2013). *An Introduction to Statistical Learning*
- NBA Advanced Analytics Community

---

**Disclaimer**: This model is for educational and demonstration purposes. Sports betting involves risk and may not be legal in all jurisdictions. This software is provided "as is" without warranty of any kind.

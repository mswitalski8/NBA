# Quick Start Guide

## 5-Minute Setup

### 1. Install Package

```r
# From R console
setwd("path/to/nba-betting-model")
devtools::install(".")

# Load package
library(nbabetting)
```

### 2. Run First Simulation

```r
# Define team metrics
mavericks <- list(adj_off = 118.5, adj_def = 112.3, adj_tempo = 100.2,
                  sd_off = 5.2, sd_def = 4.8, sd_tempo = 3.1)

celtics <- list(adj_off = 120.1, adj_def = 109.5, adj_tempo = 98.5,
                sd_off = 4.9, sd_def = 5.1, sd_tempo = 2.8)

# Simulate game
results <- simulate_game(
  team_a_metrics = mavericks,
  team_b_metrics = celtics,
  interaction_model = "multiplicative",
  n_sims = 10000
)

# View results
print(results$summary)
```

### 3. Calculate Market Probabilities

```r
# Define market lines
lines <- list(spread = -2.5, total = 230.5)

# Calculate probabilities
probs <- calculate_market_probabilities(results, lines)
print(probs)
```

### 4. Find +EV Bets

```r
# Market odds
odds <- data.frame(
  market = c("spread", "total"),
  odds = c(-110, -110)
)

# Find opportunities
opportunities <- find_betting_opportunities(probs, odds, min_ev = 0.02)
print(opportunities)
```

## Run Examples

```r
# Navigate to examples directory
setwd("path/to/nba-betting-model/examples")

# Run examples
source("01_backfitting_example.R")      # Backfitting analysis
source("02_simulate_game_example.R")    # Single game simulation
source("03_complete_workflow_example.R") # Full daily workflow
```

## Key Functions

| Function | Purpose |
|----------|---------|
| `simulate_game()` | Run Monte Carlo simulation |
| `calculate_weighted_mean()` | Exponential decay averaging |
| `bayesian_conjugate_update()` | Update tempo estimates |
| `calculate_lineup_adjustment()` | Injury impact analysis |
| `pregame_workflow()` | Complete pre-game analysis |
| `run_complete_backfitting()` | Empirical model selection |

## Next Steps

1. Read `README.md` for comprehensive documentation
2. Review `PROJECT_SUMMARY.md` for technical details
3. Explore example scripts in `examples/`
4. Implement data fetching functions for your sources
5. Run backfitting on real historical data

## Common Issues

**Q: Functions not found after install**
```r
# Reload package
devtools::load_all()
```

**Q: Missing dependencies**
```r
install.packages(c("dplyr", "tidyr", "purrr", "ggplot2", "lubridate"))
```

**Q: Examples fail**
```r
# Examples use simulated data
# Adapt data loading sections for your data sources
```

## Get Help

- Check function documentation: `?simulate_game`
- View package help: `help(package = "nbabetting")`
- Review examples: `dir("examples")`

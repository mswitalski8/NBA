# NBA Betting Model - Complete Specification

**Document Version:** 2.0 (December 2025)
**Status:** Final Design - Ready for Implementation

---

## Table of Contents

1. [Summary](#summary)
2. [Core Principles](#core-principles)
3. [Mathematical Foundations](#mathematical-foundations)
4. [Data Requirements](#data-requirements)
5. [Backfitting Methodology](#backfitting-methodology)
6. [Initialization](#initialization)
7. [Daily Update Workflow](#daily-update-workflow)
8. [Pre-Game Workflow](#pre-game-workflow)
9. [Simulation Engine](#simulation-engine)
10. [Post-Game Workflow](#post-game-workflow)
11. [Implementation Details](#implementation-details)
12. [Validation Framework](#validation-framework)
13. [Future Phases](#future-phases)

---

## Summary

### Model Purpose

A Bayesian NBA betting model that generates probability distributions for:
- **Phase 1 (MVP):** Spreads, totals, team totals, moneylines
- **Phase 2:** NBA Cup and Playoff situational adjustments
- **Phase 3:** Player props, halves (1H pregame, live 2H), quarters (1Q pregame, live 3Q, live 4Q)

### Core Architecture

**DunksAndThrees Integration:**
- Adjusted offensive and defensive efficiency from DnT (proven, no reinvention)
- Player EPM values (OFF/DEF per 100 possessions) scraped daily
- Leverages DnT's internal weighting and adjustment methodology
- Premium Subscription + API: $250/yr

**Internal Tempo Tracking:**
- Bayesian conjugate prior updates with 15-game half-life
- League-normalized adjusted tempo
- Hybrid variance system (weighted + Bayesian)

**Edge Generation:**
- Weighted rotation tracking (15-game half-life, 240 minutes)
- Lineup impact adjustments using player EPM values
- Team-specific venue effects (weekly recalculation)
- Universal rest and timezone adjustments (via backfitting)

**Monte Carlo Simulation:**
- 10,000 iterations per game
- Normal distributions with rolling 30-game standard deviations
- Interaction models determined by backfitting

---

## Core Principles

### 1. The 75/25 Philosophy

**15-game exponential half-life captures the balance:**

```
weight_i = (0.5)^(games_ago_i / 15)

Properties:
- Most recent game: weight = 1.0
- 15 games ago: weight = 0.5
- 30 games ago: weight = 0.25
- Last ~30 games capture 75% of total weight
```

**Interpretation:**
- **75%** = Observable recent performance (roster, form, matchups, injuries)
- **25%** = Systemic stable factors (coaching, culture, identity, intangibles)

This balances **adaptation** (responding to recent data) with **stability** (respecting fundamental team identity).

### 2. Don't Reinvent What Works

**DunksAndThrees for adjusted efficiency:**
- Proven through firsthand experience
- Industry-standard adjustments for schedule strength, pace, opponent quality
- Scraped daily as authoritative baselines
- No internal adjustments or second-guessing

**We build the edge through:**
- Lineup availability adjustments
- Venue-specific effects
- Rest and timezone impacts
- Situation-specific context

### 3. Tempo Requires Internal Tracking

**DunksAndThrees does not publish adjusted tempo**, so we calculate our own:
- League-normalize raw tempo observations
- Bayesian updates with 15-game weighted variance
- Maintains same 75/25 philosophy as DnT uses for efficiency

### 4. Variance from Rolling Windows

**For Monte Carlo sampling:**
- Rolling 30-game standard deviation (simple, stable)
- Separate calculation for adjusted offense, adjusted defense, adjusted tempo
- Drops oldest, adds newest after each game

### 5. Edge from Lineup Intelligence

**Weighted rotation (15-game half-life):**
- Track minutes played with exponential decay
- Normalize to 240 minutes total
- Calculate aggregate EPM impact for baseline rotation
- Compare to today's expected rotation (injury reports + projections)
- Adjustment = today's impact - baseline impact

### 6. Backfitting Before Betting

**Critical parameters must be empirically determined:**
- Offense-Defense interaction model
- Tempo interaction model
- Team-specific venue effects
- Universal rest adjustments
- Universal timezone adjustments

**Use 2024-25 and 2025-26 regular season data for backfitting.**

---

## Mathematical Foundations

### Universal Exponential Decay Weighting

For any metric X across last N games:

```
weights = [(0.5)^(i/15) for i in range(N)]

X_weighted = Σ(weight_i × x_i) / Σ(weight_i)
```

Where:
- i = game index (0 = most recent, N-1 = oldest)
- weight_i = exponential decay weight
- x_i = observed value in game i

### Weighted Variance

For metric X with weighted mean X_weighted:

```
σ²_weighted = Σ(weight_i × (x_i - X_weighted)²) / Σ(weight_i)
```

**Interpretation:** Recent volatility weighted more heavily than distant past.

### Bayesian Conjugate Prior Update (Tempo Only)

**Prior Distribution:**
```
μ₀ = prior mean (current baseline)
σ₀² = prior variance (from weighted historical residuals)
```

**Observation:**
```
x = observed adjusted tempo (from box score)
σ²_obs = observation variance (fixed noise parameter)
```

**Posterior Distribution:**

**Posterior Variance:**
```
σ²_post = (σ₀² × σ²_obs) / (σ₀² + σ²_obs)
```

**Posterior Mean:**
```
μ_post = (σ²_obs × μ₀ + σ₀² × x) / (σ₀² + σ²_obs)
```

**Properties:**
- σ²_post < σ₀² always (variance strictly decreasing)
- More observations → lower uncertainty
- σ²_obs controls shrinkage rate

### Hybrid Variance (Conservative Approach)

```
σ²_final = max(σ²_weighted, σ²_bayesian)
```

**Rationale:**
- σ²_weighted captures regime changes (can increase with volatility)
- σ²_bayesian rewards data accumulation (only decreases)
- Use whichever indicates more uncertainty (conservative)

### Rolling Standard Deviation (For Simulation)

```
For each metric (AdjO, AdjD, AdjTempo):
  last_30_games = [observed values]
  mean_30 = Σ(x_i) / 30
  σ_rolling = sqrt[Σ(x_i - mean_30)² / 30]
```

**This σ is used for Monte Carlo sampling distributions.**

After each game: drop oldest observation, add newest, recalculate.

### Weighted Rotation Calculation

**For each player P on roster:**

```
# Calculate weighted average minutes
games_played = [games where player P appeared in last N games]
weights = [(0.5)^(i/15) for i in range(len(games_played))]

raw_weighted_minutes_P = Σ(weight_i × minutes_i) / Σ(weight_i)
```

**Normalize to 240 minutes:**

```
all_players_raw = {player_P: raw_weighted_minutes_P for all players}
total_raw = Σ(raw_weighted_minutes_P) for all players

expected_minutes_P = (raw_weighted_minutes_P / total_raw) × 240
```

**This ensures rotation always sums to exactly 240 minutes regardless of roster changes.**

### Lineup Impact Calculation

**Baseline rotation aggregate EPM:**

```
baseline_off_impact = Σ[(expected_minutes_P / 48) × OFF_EPM_P] for all players
baseline_def_impact = Σ[(expected_minutes_P / 48) × DEF_EPM_P] for all players
```

**Today's expected rotation aggregate EPM:**

```
# From injury reports + minutes projections
today_projected_minutes = {player_P: minutes_P for available players}

# Normalize to 240 if needed
total_projected = Σ(minutes_P)
if total_projected != 240:
    normalized_minutes_P = (minutes_P / total_projected) × 240

today_off_impact = Σ[(normalized_minutes_P / 48) × OFF_EPM_P]
today_def_impact = Σ[(normalized_minutes_P / 48) × DEF_EPM_P]
```

**Lineup adjustment:**

```
lineup_off_adj = today_off_impact - baseline_off_impact
lineup_def_adj = today_def_impact - baseline_def_impact
```

**Example:**

```
Mavericks baseline rotation (15-game weighted):
- Luka: 34.2 min, OFF = +8.0 → (34.2/48) × 8.0 = +5.7
- Kyrie: 33.1 min, OFF = +5.0 → (33.1/48) × 5.0 = +3.4
- Others: 172.7 min, avg OFF = +0.6 → (172.7/48) × 0.6 = +2.2
baseline_off_impact = +11.3

Today's rotation (Luka out):
- Kyrie: 38.0 min, OFF = +5.0 → (38.0/48) × 5.0 = +4.0
- Dinwiddie: 30.0 min, OFF = +0.8 → (30.0/48) × 0.8 = +0.5
- Others: 172.0 min, avg OFF = +0.4 → (172.0/48) × 0.4 = +1.4
today_off_impact = +5.9

lineup_off_adj = 5.9 - 11.3 = -5.4 pts/100 possessions
```

---

## Data Requirements

### External Data Sources

#### 1. DunksAndThrees (Daily Scrape - 2am CT)

**Team-Level Metrics:**
- **Adjusted Offensive Efficiency (AdjO)**: Points per 100 possessions, schedule-adjusted
- **Adjusted Defensive Efficiency (AdjD)**: Points allowed per 100 possessions, schedule-adjusted
- **Raw Tempo**: Possessions per 48 minutes (unadjusted)

**Player-Level Metrics:**
- **OFF**: Offensive EPM (estimated plus-minus per 100 possessions)
- **DEF**: Defensive EPM (estimated plus-minus per 100 possessions, positive = worse)

**Update Frequency:** Daily after all games complete (~2am CT)

**API Endpoints:**
```
GET /teams/{team_id}/metrics?date={YYYY-MM-DD}
GET /players/{player_id}/epm?date={YYYY-MM-DD}
```

#### 2. Box Score Data (NBA.com or ESPN API)

**Required for possession calculation:**

```
Possessions = 0.5 × (FGA + 0.475×FTA - OReb + TO)
```

**Box score fields needed:**
- FGA (Field Goals Attempted)
- FTA (Free Throws Attempted)
- OReb (Offensive Rebounds)
- TO (Turnovers)
- Points Scored
- Game Minutes (48 or OT length)
- Player minutes played

**Update Frequency:** After game completion (~30 min post-game)

#### 3. Injury Reports (SpankOdds or Similar)

**Real-time player availability:**
- Injury status (out, questionable, probable, active)
- Game-time decisions
- Load management announcements

**Update Frequency:** Real-time, check 2 hours before tipoff

#### 4. Minutes Projections (3rd Party - TBD)

**Potential providers to evaluate:**
- ETR (Establish the Run)
- Rotowire
- Sportsline
- DnT

**Validation metrics:**
- MAE (Mean Absolute Error)
- Bias (systematic over/under projection)
- Correlation with actual minutes

**Selection criteria:** Choose provider with lowest MAE and near-zero bias.

**Update Frequency:** Daily (morning)

### Internal State (Database)

**Stored per team, updated daily:**
- Baseline adjusted offensive efficiency (from DnT)
- Baseline adjusted defensive efficiency (from DnT)
- Baseline adjusted tempo (Bayesian tracked internally)
- Weighted rotation (expected minutes per player)
- Baseline rotation EPM aggregates (OFF/DEF)
- Tempo variance (Bayesian and weighted)
- Rolling 30-game standard deviations (AdjO, AdjD, AdjTempo)
- Team-specific venue effects (home/away adjustments)
- Game history (last 60+ games)

---

## Backfitting Methodology

### Overview

**Critical: All backfitting MUST be completed before live betting begins.**

Using 2024-25 and 2025-26 regular season data, empirically determine:
1. Offense-Defense interaction model
2. Tempo interaction model
3. Team-specific venue effects (initial baselines)
4. Universal rest adjustments
5. Universal timezone adjustments

**Once established:**
- Interaction models remain **fixed**
- Venue effects are **dynamic** (recalculated weekly with 15-game half-life)
- Rest and timezone adjustments remain **universal and fixed**

---

### 1. Offense-Defense Interaction Model

**Goal:** Determine how team offensive and defensive efficiencies combine to produce scoring outcomes.

#### Candidate Models

**Model A: Simple Average (Additive)**
```python
team_a_eff = (team_a_adj_off + team_b_adj_def) / 2
team_a_points = team_a_eff × possessions / 100
```

**Assumptions:**
- Offense and defense contribute equally (50/50)
- Linear/additive interaction
- No amplification effects

**Model B: Multiplicative (Opponent-Adjusted)**
```python
league_avg_eff = 115  # updated seasonally

# Defensive adjustment factor
def_factor = team_b_adj_def / league_avg_eff

# Adjusted offensive efficiency
adjusted_off = team_a_adj_off × def_factor

team_a_points = adjusted_off × possessions / 100
```

**Assumptions:**
- Elite offense vs terrible defense = amplified scoring
- Terrible offense vs elite defense = suppressed scoring
- Multiplicative interaction (percentage-based)

#### Testing Methodology

```python
def test_interaction_models(seasons=['2024-25', '2025-26']):
    """
    Compare models on historical data using walk-forward validation.
    """
    games = load_games(seasons)

    simple_predictions = []
    mult_predictions = []

    for game in games:
        # Use ONLY data available before this game
        prior = get_data_before(game.date)

        # Calculate expected possessions
        expected_poss = (prior.team_a_tempo + prior.team_b_tempo) / 2

        # Model A: Simple average
        team_a_eff_simple = (prior.team_a_adj_off + prior.team_b_adj_def) / 2
        team_a_pts_simple = team_a_eff_simple * expected_poss / 100

        team_b_eff_simple = (prior.team_b_adj_off + prior.team_a_adj_def) / 2
        team_b_pts_simple = team_b_eff_simple * expected_poss / 100

        # Model B: Multiplicative
        league_avg = calculate_league_avg(prior.date)
        team_a_pts_mult = (
            prior.team_a_adj_off * (prior.team_b_adj_def / league_avg) *
            expected_poss / 100
        )
        team_b_pts_mult = (
            prior.team_b_adj_off * (prior.team_a_adj_def / league_avg) *
            expected_poss / 100
        )

        # Store predictions
        simple_predictions.append({
            'predicted_total': team_a_pts_simple + team_b_pts_simple,
            'predicted_spread': team_a_pts_simple - team_b_pts_simple,
            'actual_total': game.actual_total,
            'actual_spread': game.actual_spread,
        })

        mult_predictions.append({
            'predicted_total': team_a_pts_mult + team_b_pts_mult,
            'predicted_spread': team_a_pts_mult - team_b_pts_mult,
            'actual_total': game.actual_total,
            'actual_spread': game.actual_spread,
        })

    # Calculate accuracy metrics
    simple_mae_total = mean([
        abs(p['predicted_total'] - p['actual_total'])
        for p in simple_predictions
    ])
    mult_mae_total = mean([
        abs(p['predicted_total'] - p['actual_total'])
        for p in mult_predictions
    ])

    simple_mae_spread = mean([
        abs(p['predicted_spread'] - p['actual_spread'])
        for p in simple_predictions
    ])
    mult_mae_spread = mean([
        abs(p['predicted_spread'] - p['actual_spread'])
        for p in mult_predictions
    ])

    return {
        'simple_average': {
            'mae_total': simple_mae_total,
            'mae_spread': simple_mae_spread,
        },
        'multiplicative': {
            'mae_total': mult_mae_total,
            'mae_spread': mult_mae_spread,
        },
        'winner': determine_winner(simple_mae_total, mult_mae_total)
    }
```

#### Stratified Analysis

Test accuracy by matchup quality:

```python
def stratified_interaction_test(seasons):
    """
    Break down by matchup type to identify where each model excels.
    """
    games = load_games(seasons)

    # Categorize games
    buckets = {
        'extreme_mismatch': [],    # |off - def| > 15
        'elite_matchup': [],        # Both off > 120, def < 110
        'terrible_matchup': [],     # Both off < 110, def > 120
        'balanced': [],             # Everything else
    }

    for game in games:
        prior = get_data_before(game.date)

        diff_a = abs(prior.team_a_adj_off - prior.team_b_adj_def)
        diff_b = abs(prior.team_b_adj_off - prior.team_a_adj_def)
        max_diff = max(diff_a, diff_b)

        if max_diff > 15:
            buckets['extreme_mismatch'].append(game)
        elif prior.team_a_adj_off > 120 and prior.team_b_adj_def < 110:
            buckets['elite_matchup'].append(game)
        elif prior.team_a_adj_off < 110 and prior.team_b_adj_def > 120:
            buckets['terrible_matchup'].append(game)
        else:
            buckets['balanced'].append(game)

    # Test each bucket
    results = {}
    for bucket_name, bucket_games in buckets.items():
        bucket_results = test_models_on_subset(bucket_games)
        results[bucket_name] = bucket_results

    return results
```

#### Decision Criteria

1. **If multiplicative MAE is lower by ≥1.0 points:** Adopt multiplicative model
2. **If simple average MAE is lower by ≥1.0 points:** Keep simple average
3. **If difference < 1.0 points:** Choose multiplicative for theoretical reasons

#### Expected Hypothesis

Based on basketball analytics literature:
- **Multiplicative likely more accurate overall**
- **Largest improvement in extreme matchups**
- **Similar performance in balanced games**

---

### 2. Tempo Interaction Model

**Goal:** Determine how two teams' tempo preferences combine to produce actual game pace.

#### Candidate Models

**Model A: Simple Average**
```python
game_tempo = (team_a_adj_tempo + team_b_adj_tempo) / 2
possessions = game_tempo  # per team
```

**Model B: Weighted by Strength**
```python
team_a_strength = team_a_adj_off - team_a_adj_def  # net rating
team_b_strength = team_b_adj_off - team_b_adj_def

strength_sum = abs(team_a_strength) + abs(team_b_strength)
team_a_weight = abs(team_a_strength) / strength_sum
team_b_weight = abs(team_b_strength) / strength_sum

game_tempo = (team_a_weight * team_a_adj_tempo) + (team_b_weight * team_b_adj_tempo)
```

**Model C: Faster Team Dictates**
```python
faster_tempo = max(team_a_adj_tempo, team_b_adj_tempo)
slower_tempo = min(team_a_adj_tempo, team_b_adj_tempo)

game_tempo = 0.6 * faster_tempo + 0.4 * slower_tempo
```

**Model D: Defensive Focus Slows Pace**
```python
avg_tempo = (team_a_adj_tempo + team_b_adj_tempo) / 2
league_avg_def = 115

defensive_factor = (team_a_adj_def + team_b_adj_def) / (2 * league_avg_def)

game_tempo = avg_tempo * defensive_factor
```

#### Testing Methodology

```python
def test_tempo_models(seasons=['2024-25', '2025-26']):
    """
    Compare tempo interaction models on historical data.
    """
    games = load_games(seasons)

    errors = {
        'simple_avg': [],
        'weighted_strength': [],
        'faster_dictates': [],
        'defensive_focus': [],
    }

    for game in games:
        prior = get_data_before(game.date)

        # Calculate actual game tempo
        actual_poss = 0.5 * (
            (game.team_a_fga + 0.475*game.team_a_fta - game.team_a_oreb + game.team_a_to) +
            (game.team_b_fga + 0.475*game.team_b_fta - game.team_b_oreb + game.team_b_to)
        )
        actual_tempo = actual_poss * (48 / game.minutes)

        # Model A: Simple average
        pred_simple = (prior.team_a_tempo + prior.team_b_tempo) / 2
        errors['simple_avg'].append(abs(pred_simple - actual_tempo))

        # Model B: Weighted by strength
        team_a_str = prior.team_a_adj_off - prior.team_a_adj_def
        team_b_str = prior.team_b_adj_off - prior.team_b_adj_def
        str_sum = abs(team_a_str) + abs(team_b_str)
        if str_sum > 0:
            pred_weighted = (
                (abs(team_a_str) / str_sum) * prior.team_a_tempo +
                (abs(team_b_str) / str_sum) * prior.team_b_tempo
            )
        else:
            pred_weighted = (prior.team_a_tempo + prior.team_b_tempo) / 2
        errors['weighted_strength'].append(abs(pred_weighted - actual_tempo))

        # Model C: Faster dictates
        faster = max(prior.team_a_tempo, prior.team_b_tempo)
        slower = min(prior.team_a_tempo, prior.team_b_tempo)
        pred_faster = 0.6 * faster + 0.4 * slower
        errors['faster_dictates'].append(abs(pred_faster - actual_tempo))

        # Model D: Defensive focus
        avg_tempo = (prior.team_a_tempo + prior.team_b_tempo) / 2
        def_factor = (prior.team_a_adj_def + prior.team_b_adj_def) / (2 * 115)
        pred_def = avg_tempo * def_factor
        errors['defensive_focus'].append(abs(pred_def - actual_tempo))

    # Calculate MAE for each
    results = {
        model: {'mae': mean(err_list)}
        for model, err_list in errors.items()
    }

    return results
```

#### Stratified Analysis

```python
def stratify_tempo_by_differential(seasons):
    """
    Test if interaction differs by pace differential.
    """
    games = load_games(seasons)

    large_diff = []  # |tempo_diff| > 5
    small_diff = []  # |tempo_diff| <= 5

    for game in games:
        prior = get_data_before(game.date)
        tempo_diff = abs(prior.team_a_tempo - prior.team_b_tempo)

        if tempo_diff > 5:
            large_diff.append(game)
        else:
            small_diff.append(game)

    return {
        'large_differential': test_tempo_models_on_subset(large_diff),
        'small_differential': test_tempo_models_on_subset(small_diff),
    }
```

#### Decision Criteria

1. **If simple average MAE within 0.5 possessions of best model:** Keep simple average (simpler)
2. **If alternative improves MAE by >0.5 possessions:** Adopt alternative
3. **Stratified results matter:** If large differentials benefit from complex model, use conditional logic

#### Expected Hypothesis

- **Simple average likely sufficient** for most games
- **Faster team may dictate more** when tempo differential >5 poss/48
- **Defensive effect small** but measurable

---

### 3. Team-Specific Venue Effects

**Goal:** Quantify home/away performance splits for each team to isolate venue impact from matchup quality.

**CRITICAL:** Must establish interaction models FIRST, then calculate venue effects as residuals.

#### Methodology

**Step 1: Establish Interaction Models**

Complete backfitting sections 1 & 2 to determine:
- Selected offense-defense interaction model
- Selected tempo interaction model

**Step 2: Calculate Expected vs Observed**

For each historical game:

```python
# Expected (based on interaction model + lineup/rest/timezone)
expected_off_eff = calculate_with_interaction_model(
    team_adj_off, opponent_adj_def, lineup_adj, rest_adj, timezone_adj
)

# Observed (from box score)
observed_off_eff = (points_scored / possessions) * 100

# Residual
residual_off = observed_off_eff - expected_off_eff
```

**Step 3: Group by Venue and Calculate Adjustments**

```python
def calculate_venue_effects(team_id, seasons=['2024-25', '2025-26']):
    """
    Calculate team-specific home/away adjustments.
    """
    games = get_team_games(team_id, seasons)

    home_games = [g for g in games if g.venue == 'home']
    away_games = [g for g in games if g.venue == 'away']

    # Calculate 15-game weighted residuals
    home_residuals_off = [g.residual_off for g in home_games]
    home_weights = [(0.5)**(i/15) for i in range(len(home_games))]
    home_off_adj = weighted_avg(home_residuals_off, home_weights)

    away_residuals_off = [g.residual_off for g in away_games]
    away_weights = [(0.5)**(i/15) for i in range(len(away_games))]
    away_off_adj = weighted_avg(away_residuals_off, away_weights)

    # Venue impact (home advantage)
    venue_off_impact = home_off_adj - away_off_adj

    # Repeat for defense and tempo
    venue_def_impact = home_def_adj - away_def_adj
    venue_tempo_impact = home_tempo_adj - away_tempo_adj

    return {
        'off': venue_off_impact,
        'def': venue_def_impact,
        'tempo': venue_tempo_impact,
    }
```

**Step 4: Initialize Baselines**

Store initial venue effects for all teams:

```sql
INSERT INTO team_venue_effects (team_id, date, venue_off_adj, venue_def_adj, venue_tempo_adj)
SELECT
    team_id,
    '2025-10-15' as season_start_date,
    venue_off_impact,
    venue_def_impact,
    venue_tempo_impact
FROM backfit_results;
```

#### Dynamic Updates (Weekly Recalculation)

**Every Monday (or configured interval):**

```python
def update_venue_effects_weekly():
    """
    Recalculate venue effects with 15-game half-life on residuals.
    """
    for team in all_teams:
        recent_games = get_recent_games(team.id, limit=60)

        # Calculate residuals for recent games
        for game in recent_games:
            game.residual_off = game.observed_off - game.expected_off
            game.residual_def = game.observed_def - game.expected_def
            game.residual_tempo = game.observed_tempo - game.expected_tempo

        # Calculate new venue adjustments
        venue_effects = calculate_venue_effects(team.id)

        # Store updated effects
        database.update_venue_effects(team.id, today, venue_effects)
```

#### Expected Results

**Typical NBA home advantages:**
- **General:** +2 to +3 pts/100 offensive, -1 to -2 pts/100 defensive
- **Denver (altitude):** +4 to +6 pts/100 offensive
- **Teams with weak home crowds:** +0 to +2 pts/100 offensive
- **Tempo:** +0.5 to +1.5 poss/48 at home

---

### 4. Universal Rest Adjustments

**Goal:** Quantify performance impacts of back-to-backs and extended rest.

#### Rest Categories

```python
REST_CATEGORIES = {
    '0_days': 'Back-to-back (played yesterday)',
    '1_day': 'Standard rest (one off day) - BASELINE',
    '2_days': 'Extra rest (two off days)',
    '3+_days': 'Extended rest (3+ off days)',
}
```

**Use 1-day rest as neutral baseline** (most common NBA schedule pattern).

#### Methodology

**Step 1: Calculate Days Since Last Game**

```python
def calculate_rest_days(team_id, game_date):
    """
    Calculate days since team's previous game.
    """
    previous_game = database.get_previous_game(team_id, before_date=game_date)

    if previous_game is None:
        return None  # Season opener or after break

    days_since = (game_date - previous_game.date).days
    return days_since
```

**Step 2: Categorize and Analyze**

```python
def analyze_rest_impact(seasons=['2024-25', '2025-26']):
    """
    Calculate performance by rest category.
    """
    games = load_games(seasons)

    categorized = {
        'back_to_back': [],
        'one_day_rest': [],
        'two_day_rest': [],
        'extended_rest': [],
    }

    for game in games:
        for team_id in [game.team_a_id, game.team_b_id]:
            rest_days = calculate_rest_days(team_id, game.date)

            # Calculate performance metrics
            metrics = calculate_game_metrics(game, team_id)

            if rest_days == 0:
                categorized['back_to_back'].append(metrics)
            elif rest_days == 1:
                categorized['one_day_rest'].append(metrics)
            elif rest_days == 2:
                categorized['two_day_rest'].append(metrics)
            elif rest_days >= 3:
                categorized['extended_rest'].append(metrics)

    # Calculate averages per category
    results = {}
    for category, metrics_list in categorized.items():
        results[category] = {
            'mean_off_eff': mean([m.off_eff for m in metrics_list]),
            'mean_def_eff': mean([m.def_eff for m in metrics_list]),
            'mean_tempo': mean([m.tempo for m in metrics_list]),
            'sample_size': len(metrics_list),
        }

    return results
```

**Step 3: Calculate Adjustments Relative to Baseline**

```python
def calculate_rest_adjustments(results):
    """
    Calculate adjustment factors relative to 1-day rest baseline.
    """
    baseline = results['one_day_rest']

    adjustments = {
        'one_day_rest': {'off': 0.0, 'def': 0.0, 'tempo': 0.0},  # baseline
    }

    for category in ['back_to_back', 'two_day_rest', 'extended_rest']:
        adjustments[category] = {
            'off': results[category]['mean_off_eff'] - baseline['mean_off_eff'],
            'def': results[category]['mean_def_eff'] - baseline['mean_def_eff'],
            'tempo': results[category]['mean_tempo'] - baseline['mean_tempo'],
        }

    return adjustments
```

**Step 4: Statistical Significance Testing**

```python
def test_rest_significance(seasons):
    """
    Perform t-tests to validate rest effects.
    """
    categorized = categorize_by_rest(seasons)

    baseline_off = [m.off_eff for m in categorized['one_day_rest']]

    results = {}
    for category in ['back_to_back', 'two_day_rest', 'extended_rest']:
        test_off = [m.off_eff for m in categorized[category]]

        t_stat, p_value = scipy.stats.ttest_ind(baseline_off, test_off)

        results[category] = {
            'offensive': {
                't_statistic': t_stat,
                'p_value': p_value,
                'significant': p_value < 0.05,
            }
        }

        # Repeat for defense and tempo...

    return results
```

#### Expected Results

| Rest Category | Off Eff Impact | Def Eff Impact | Tempo Impact |
|---------------|----------------|----------------|--------------|
| **0 days (B2B)** | -2 to -4 pts/100 | +1 to +3 pts/100 (worse) | -1 to -2 poss/48 |
| **1 day (Baseline)** | 0 (reference) | 0 (reference) | 0 (reference) |
| **2 days** | +0.5 to +1.5 pts/100 | -0.5 to -1 pts/100 (better) | +0.5 to +1 poss/48 |
| **3+ days** | +1 to +2 pts/100 | -1 to -2 pts/100 (better) | +0.5 to +1.5 poss/48 |

#### Rest Differential Analysis

```python
def analyze_rest_differentials(seasons):
    """
    Analyze games where teams have different rest days.
    """
    games = load_games(seasons)

    significant_diff_games = []

    for game in games:
        team_a_rest = calculate_rest_days(game.team_a_id, game.date)
        team_b_rest = calculate_rest_days(game.team_b_id, game.date)

        rest_diff = abs(team_a_rest - team_b_rest)

        if rest_diff >= 2:  # B2B vs 2+ days rest
            significant_diff_games.append(game)

    # Calculate win rate for rested team
    rested_team_wins = 0

    for game in significant_diff_games:
        team_a_rest = calculate_rest_days(game.team_a_id, game.date)
        team_b_rest = calculate_rest_days(game.team_b_id, game.date)

        if team_a_rest > team_b_rest:  # Team A more rested
            if game.team_a_points > game.team_b_points:
                rested_team_wins += 1
        else:  # Team B more rested
            if game.team_b_points > game.team_a_points:
                rested_team_wins += 1

    win_rate = rested_team_wins / len(significant_diff_games)

    return {
        'sample_size': len(significant_diff_games),
        'rested_team_win_rate': win_rate,
        'rest_advantage': win_rate - 0.50,
    }
```

**Expected Finding:** Team with 2+ more days rest should win 55-60% of games.

---

### 5. Universal Timezone Adjustments

**Goal:** Quantify travel and body clock effects from timezone changes.

#### Comprehensive Testing Matrix

**All combinations to test:**

```python
TIMEZONE_COMBINATIONS = [
    # Home timezone → Game timezone
    ('ET', 'ET'),  # No travel
    ('ET', 'CT'),  # 1 zone west
    ('ET', 'MT'),  # 2 zones west
    ('ET', 'PT'),  # 3 zones west

    ('CT', 'ET'),  # 1 zone east
    ('CT', 'CT'),  # No travel
    ('CT', 'MT'),  # 1 zone west
    ('CT', 'PT'),  # 2 zones west

    ('MT', 'ET'),  # 2 zones east
    ('MT', 'CT'),  # 1 zone east
    ('MT', 'MT'),  # No travel
    ('MT', 'PT'),  # 1 zone west

    ('PT', 'ET'),  # 3 zones east
    ('PT', 'CT'),  # 2 zones east
    ('PT', 'MT'),  # 1 zone east
    ('PT', 'PT'),  # No travel
]
```

**Team timezone assignments:**
```python
TEAM_TIMEZONES = {
    'ATL': 'ET', 'BOS': 'ET', 'BKN': 'ET', 'CHA': 'ET', 'CHI': 'CT',
    'CLE': 'ET', 'DAL': 'CT', 'DEN': 'MT', 'DET': 'ET', 'GSW': 'PT',
    'HOU': 'CT', 'IND': 'ET', 'LAC': 'PT', 'LAL': 'PT', 'MEM': 'CT',
    'MIA': 'ET', 'MIL': 'CT', 'MIN': 'CT', 'NOP': 'CT', 'NYK': 'ET',
    'OKC': 'CT', 'ORL': 'ET', 'PHI': 'ET', 'PHX': 'MT', 'POR': 'PT',
    'SAC': 'PT', 'SAS': 'CT', 'TOR': 'ET', 'UTA': 'MT', 'WAS': 'ET',
}
```

#### Methodology

**Step 1: Categorize Games by Timezone Travel**

```python
def categorize_by_timezone(seasons=['2024-25', '2025-26']):
    """
    Group games by timezone combination.
    """
    games = load_games(seasons)

    timezone_buckets = {combo: [] for combo in TIMEZONE_COMBINATIONS}

    for game in games:
        # Determine game timezone (venue location)
        game_timezone = TEAM_TIMEZONES[game.home_team_id]

        # Away team's home timezone
        away_home_tz = TEAM_TIMEZONES[game.away_team_id]

        # Combination for away team
        combo_away = (away_home_tz, game_timezone)

        # Store game with away team perspective
        timezone_buckets[combo_away].append({
            'game': game,
            'affected_team': game.away_team_id,
        })

        # Home team always plays in their timezone (no adjustment)

    return timezone_buckets
```

**Step 2: Calculate Performance by Timezone Combination**

```python
def analyze_timezone_impact(seasons):
    """
    Calculate metrics for each timezone combination.
    """
    buckets = categorize_by_timezone(seasons)

    results = {}

    for combo, games_list in buckets.items():
        home_tz, game_tz = combo

        if home_tz == game_tz:
            # No travel, no adjustment
            continue

        off_effs = []
        def_effs = []
        tempos = []

        for game_data in games_list:
            game = game_data['game']
            team_id = game_data['affected_team']

            # Calculate metrics for affected team
            metrics = calculate_team_game_metrics(game, team_id)

            off_effs.append(metrics.off_eff)
            def_effs.append(metrics.def_eff)
            tempos.append(metrics.tempo)

        results[combo] = {
            'mean_off_eff': mean(off_effs),
            'mean_def_eff': mean(def_effs),
            'mean_tempo': mean(tempos),
            'sample_size': len(off_effs),
        }

    return results
```

**Step 3: Calculate Adjustments Relative to No-Travel Baseline**

```python
def calculate_timezone_adjustments(results):
    """
    Calculate adjustments for each timezone travel scenario.
    """
    # Baseline: calculate average performance when no timezone change
    no_travel_games = []
    for combo, metrics in results.items():
        home_tz, game_tz = combo
        if home_tz == game_tz:
            no_travel_games.append(metrics)

    baseline_off = mean([m['mean_off_eff'] for m in no_travel_games])
    baseline_def = mean([m['mean_def_eff'] for m in no_travel_games])
    baseline_tempo = mean([m['mean_tempo'] for m in no_travel_games])

    adjustments = {}

    for combo, metrics in results.items():
        home_tz, game_tz = combo

        if home_tz == game_tz:
            adjustments[combo] = {'off': 0.0, 'def': 0.0, 'tempo': 0.0}
        else:
            adjustments[combo] = {
                'off': metrics['mean_off_eff'] - baseline_off,
                'def': metrics['mean_def_eff'] - baseline_def,
                'tempo': metrics['mean_tempo'] - baseline_tempo,
            }

    return adjustments
```

**Step 4: Stratified Analysis**

**Additional factors to consider:**

```python
def stratify_timezone_analysis(seasons):
    """
    Test if timezone effects interact with other factors.
    """
    games = load_games(seasons)

    stratified = {
        'timezone_only': [],              # Normal rest (1 day)
        'timezone_plus_b2b': [],          # Timezone + back-to-back
        'timezone_immediate': [],         # Game day after travel
        'timezone_adjusted': [],          # 2+ days to adjust
        'late_game_east_coast': [],       # ET teams playing 10pm+ ET starts
    }

    for game in games:
        away_team_tz = TEAM_TIMEZONES[game.away_team_id]
        game_tz = TEAM_TIMEZONES[game.home_team_id]

        if away_team_tz == game_tz:
            continue  # No timezone travel

        rest_days = calculate_rest_days(game.away_team_id, game.date)
        game_start_time = game.start_time  # Local time

        # Categorize
        if rest_days == 0:
            stratified['timezone_plus_b2b'].append(game)
        elif rest_days == 1:
            stratified['timezone_only'].append(game)

        # Days to adjust (check previous games)
        days_in_tz = calculate_days_in_timezone(game.away_team_id, game.date)
        if days_in_tz == 0:
            stratified['timezone_immediate'].append(game)
        elif days_in_tz >= 2:
            stratified['timezone_adjusted'].append(game)

        # Late games for East coast teams
        if away_team_tz == 'ET' and game_tz == 'PT':
            # Convert game time to ET body clock
            et_body_clock_time = game_start_time + 3  # hours
            if et_body_clock_time >= 22:  # 10pm or later ET
                stratified['late_game_east_coast'].append(game)

    # Analyze each stratum
    results = {}
    for stratum_name, stratum_games in stratified.items():
        results[stratum_name] = analyze_performance(stratum_games)

    return results
```

#### Expected Results

**Directional hypotheses:**

1. **Westward travel (ET→PT):**
   - Slight negative impact (-0.5 to -1.5 pts/100)
   - Late games (10pm+ ET body clock) amplify effect

2. **Eastward travel (PT→ET):**
   - Minimal to slight positive impact (0 to +0.5 pts/100)
   - Early games less problematic

3. **Immediate vs adjusted:**
   - Day-of-travel games show larger impact
   - 2+ days in new timezone reduces effect by ~50%

4. **Interaction with rest:**
   - Timezone + B2B compounds effects (additive or worse)

#### Statistical Significance

```python
def test_timezone_significance(seasons):
    """
    Validate timezone effects with t-tests.
    """
    no_travel_metrics = get_no_travel_games(seasons)

    results = {}

    for combo in TIMEZONE_COMBINATIONS:
        home_tz, game_tz = combo

        if home_tz == game_tz:
            continue  # Skip no-travel baseline

        tz_travel_metrics = get_games_for_combo(seasons, combo)

        # T-test for offensive efficiency
        t_stat, p_value = scipy.stats.ttest_ind(
            [m.off_eff for m in no_travel_metrics],
            [m.off_eff for m in tz_travel_metrics]
        )

        results[combo] = {
            'offensive': {
                't_statistic': t_stat,
                'p_value': p_value,
                'significant': p_value < 0.05,
            }
        }

        # Repeat for defense and tempo...

    return results
```

---

### Backfitting Output Configuration

After completing all backfitting analysis, store results:

```python
BACKFIT_CONFIG = {
    # Interaction models (fixed)
    'offense_defense_interaction': 'multiplicative',  # or 'simple_average'
    'tempo_interaction': 'simple_average',  # or 'weighted_strength', etc.
    'league_average_efficiency': 115.0,  # updated seasonally

    # Rest adjustments (universal, fixed)
    'rest_adjustments': {
        'back_to_back': {'off': -3.0, 'def': +2.0, 'tempo': -1.5},
        'one_day_rest': {'off': 0.0, 'def': 0.0, 'tempo': 0.0},
        'two_day_rest': {'off': +1.0, 'def': -0.5, 'tempo': +0.5},
        'extended_rest': {'off': +1.5, 'def': -1.0, 'tempo': +1.0},
    },

    # Timezone adjustments (universal, fixed)
    'timezone_adjustments': {
        ('ET', 'ET'): {'off': 0.0, 'def': 0.0, 'tempo': 0.0},
        ('ET', 'CT'): {'off': -0.3, 'def': +0.2, 'tempo': -0.1},
        ('ET', 'MT'): {'off': -0.8, 'def': +0.5, 'tempo': -0.3},
        ('ET', 'PT'): {'off': -1.2, 'def': +0.8, 'tempo': -0.5},
        # ... all 16 combinations
    },

    # Venue effects (team-specific, dynamic - initial baselines)
    'venue_effects_initial': {
        'ATL': {'off': +2.1, 'def': -1.3, 'tempo': +0.8},
        'BOS': {'off': +3.2, 'def': -2.1, 'tempo': +1.2},
        'DEN': {'off': +5.5, 'def': -1.8, 'tempo': +1.5},  # Altitude
        # ... all 30 teams
    },
}
```

---

## Initialization

### Overview

Before the model can make live predictions, initialize all team states using backfitting results and historical data.

**Timeline:** Complete during preseason or early season before placing bets.

### Step 1: Load Backfitting Results

```python
def load_backfit_config():
    """
    Load all backfitting results into runtime configuration.
    """
    config = load_json('backfit_config.json')

    global INTERACTION_MODEL_OFF_DEF
    global INTERACTION_MODEL_TEMPO
    global REST_ADJUSTMENTS
    global TIMEZONE_ADJUSTMENTS

    INTERACTION_MODEL_OFF_DEF = config['offense_defense_interaction']
    INTERACTION_MODEL_TEMPO = config['tempo_interaction']
    REST_ADJUSTMENTS = config['rest_adjustments']
    TIMEZONE_ADJUSTMENTS = config['timezone_adjustments']

    return config
```

### Step 2: Initialize Team States

For each team, calculate initial state from recent historical games:

```python
def initialize_team_state(team_id, as_of_date):
    """
    Initialize team state using recent historical data.
    """
    # 1. Get DunksAndThrees current metrics
    dnt_metrics = fetch_dnt_metrics(team_id, date=as_of_date)

    baseline_adj_off = dnt_metrics.adj_offensive_efficiency
    baseline_adj_def = dnt_metrics.adj_defensive_efficiency
    raw_tempo = dnt_metrics.raw_tempo

    # 2. Calculate league-normalized tempo baseline
    league_avg_tempo = calculate_league_avg_tempo(as_of_date)
    adjusted_tempo_current = raw_tempo - league_avg_tempo + 100

    # Get last N games for weighted tempo baseline
    recent_games = get_recent_games(team_id, before_date=as_of_date, limit=60)

    tempo_observations = []
    for game in recent_games:
        # Calculate observed tempo
        poss = 0.5 * (game.fga + 0.475*game.fta - game.oreb + game.to)
        opp_poss = 0.5 * (game.opp_fga + 0.475*game.opp_fta - game.opp_oreb + game.opp_to)
        raw_tempo_obs = ((poss + opp_poss) / 2) * (48 / game.minutes)

        # Normalize
        lg_avg_on_date = calculate_league_avg_tempo(game.date)
        adj_tempo_obs = raw_tempo_obs - lg_avg_on_date + 100

        tempo_observations.append(adj_tempo_obs)

    # 15-game weighted average
    weights = [(0.5)**(i/15) for i in range(len(tempo_observations))]
    baseline_adj_tempo = sum(w * t for w, t in zip(weights, tempo_observations)) / sum(weights)

    # 3. Initialize tempo Bayesian variance
    # Start with weighted variance
    mean_tempo = baseline_adj_tempo
    variance_weighted = sum(w * (t - mean_tempo)**2 for w, t in zip(weights, tempo_observations)) / sum(weights)

    sigma_bayesian_tempo = variance_weighted  # Initial Bayesian = weighted
    sigma_final_tempo = variance_weighted

    # 4. Calculate rolling 30-game standard deviations
    last_30_games = recent_games[:30]

    adj_off_30 = [calculate_adj_off(g) for g in last_30_games]
    adj_def_30 = [calculate_adj_def(g) for g in last_30_games]
    adj_tempo_30 = tempo_observations[:30]

    sigma_rolling_off = np.std(adj_off_30)
    sigma_rolling_def = np.std(adj_def_30)
    sigma_rolling_tempo = np.std(adj_tempo_30)

    # 5. Initialize weighted rotation
    rotation = calculate_weighted_rotation(team_id, recent_games)

    # Get current EPM values
    player_epm = fetch_player_epm(team_id, date=as_of_date)

    # Calculate baseline EPM aggregates
    baseline_off_impact = sum(
        (rotation[p] / 48) * player_epm[p]['OFF']
        for p in rotation.keys()
    )
    baseline_def_impact = sum(
        (rotation[p] / 48) * player_epm[p]['DEF']
        for p in rotation.keys()
    )

    # 6. Load initial venue effects from backfitting
    venue_effects = BACKFIT_CONFIG['venue_effects_initial'][team_id]

    # 7. Store initial state
    team_state = {
        'team_id': team_id,
        'date': as_of_date,

        # Baselines (from DnT)
        'baseline_adj_off': baseline_adj_off,
        'baseline_adj_def': baseline_adj_def,

        # Tempo (internal Bayesian tracking)
        'baseline_adj_tempo': baseline_adj_tempo,
        'sigma_bayesian_tempo': sigma_bayesian_tempo,
        'sigma_weighted_tempo': variance_weighted,
        'sigma_final_tempo': sigma_final_tempo,

        # Rolling standard deviations (for simulation)
        'sigma_rolling_off': sigma_rolling_off,
        'sigma_rolling_def': sigma_rolling_def,
        'sigma_rolling_tempo': sigma_rolling_tempo,

        # Weighted rotation
        'rotation': rotation,  # {player_id: expected_minutes}
        'baseline_off_impact': baseline_off_impact,
        'baseline_def_impact': baseline_def_impact,

        # Venue effects
        'venue_off_adj': venue_effects['off'],
        'venue_def_adj': venue_effects['def'],
        'venue_tempo_adj': venue_effects['tempo'],
    }

    database.insert_team_state(team_state)

    return team_state
```

### Step 3: Initialize Game History

Store recent games for each team:

```python
def initialize_game_history(team_id, as_of_date):
    """
    Store last 60 games for each team with calculated metrics.
    """
    recent_games = get_recent_games(team_id, before_date=as_of_date, limit=60)

    for game in recent_games:
        # Calculate all metrics
        observed_off = calculate_observed_off(game, team_id)
        observed_def = calculate_observed_def(game, team_id)
        observed_tempo = calculate_observed_tempo(game)

        # Store
        database.insert_game_history({
            'game_id': game.id,
            'team_id': team_id,
            'date': game.date,
            'venue': game.venue,
            'observed_off_eff': observed_off,
            'observed_def_eff': observed_def,
            'observed_tempo': observed_tempo,
            'player_minutes': game.player_minutes,  # JSON
        })
```

### Step 4: Validation

Verify initialization completed successfully:

```python
def validate_initialization():
    """
    Verify all teams initialized correctly.
    """
    all_teams = get_all_teams()

    for team in all_teams:
        state = database.get_team_state(team.id)

        assert state is not None, f"Missing state for {team.name}"
        assert state.baseline_adj_off > 80, f"Invalid off for {team.name}"
        assert state.baseline_adj_def > 80, f"Invalid def for {team.name}"
        assert len(state.rotation) > 0, f"Empty rotation for {team.name}"

        games = database.get_game_history(team.id)
        assert len(games) >= 30, f"Insufficient history for {team.name}"

    print("✓ All teams initialized successfully")
```

---

## Daily Update Workflow

**Runs daily at approximately 2:00 AM CT** after all games complete.

### Step 1: Scrape DunksAndThrees Data

```python
def daily_scrape_dnt(date):
    """
    Scrape team and player metrics from DunksAndThrees.
    """
    # Team metrics
    for team in all_teams:
        metrics = dnt_api.get_team_metrics(team.id, date)

        database.update_team_dnt_metrics(team.id, date, {
            'adj_off': metrics.adjusted_offensive_efficiency,
            'adj_def': metrics.adjusted_defensive_efficiency,
            'raw_tempo': metrics.raw_tempo,
        })

    # Player EPM values
    all_players = dnt_api.get_all_players(date)

    for player in all_players:
        database.update_player_epm(player.id, date, {
            'OFF': player.offensive_epm,
            'DEF': player.defensive_epm,
        })
```

### Step 2: Update Team States (For Teams That Played)

For each team that played yesterday:

```python
def daily_update_team_state(team_id, date):
    """
    Update team state after processing yesterday's games.
    """
    # 1. Load current state
    state = database.get_team_state(team_id)

    # 2. Update DnT baselines (from scrape)
    dnt_metrics = database.get_team_dnt_metrics(team_id, date)
    state.baseline_adj_off = dnt_metrics.adj_off
    state.baseline_adj_def = dnt_metrics.adj_def

    # 3. Update tempo (Bayesian)
    # Get yesterday's game(s)
    yesterdays_games = database.get_games(team_id, date=date-1)

    for game in yesterdays_games:
        # Calculate observed tempo
        observed_tempo = calculate_observed_tempo(game, team_id)

        # Bayesian update
        prior_mean = state.baseline_adj_tempo
        prior_var = state.sigma_final_tempo ** 2
        obs_var = CONFIG['observation_variance_tempo']  # e.g., 25

        # Posterior
        post_var = (prior_var * obs_var) / (prior_var + obs_var)
        post_mean = (obs_var * prior_mean + prior_var * observed_tempo) / (prior_var + obs_var)

        state.baseline_adj_tempo = post_mean
        state.sigma_bayesian_tempo = np.sqrt(post_var)

    # 4. Update weighted variance (15-game half-life)
    recent_games = database.get_recent_games(team_id, limit=60)

    tempo_residuals = []
    for game in recent_games:
        expected = game.expected_tempo  # stored pre-game
        observed = game.observed_tempo
        residual = observed - expected
        tempo_residuals.append(residual)

    weights = [(0.5)**(i/15) for i in range(len(tempo_residuals))]
    sigma_weighted_tempo_sq = sum(w * r**2 for w, r in zip(weights, tempo_residuals)) / sum(weights)
    state.sigma_weighted_tempo = np.sqrt(sigma_weighted_tempo_sq)

    # 5. Hybrid variance
    state.sigma_final_tempo = max(state.sigma_weighted_tempo, state.sigma_bayesian_tempo)

    # 6. Update rolling 30-game standard deviations
    last_30_games = recent_games[:30]

    adj_off_30 = [g.observed_off_eff for g in last_30_games]
    adj_def_30 = [g.observed_def_eff for g in last_30_games]
    adj_tempo_30 = [g.observed_tempo for g in last_30_games]

    state.sigma_rolling_off = np.std(adj_off_30)
    state.sigma_rolling_def = np.std(adj_def_30)
    state.sigma_rolling_tempo = np.std(adj_tempo_30)

    # 7. Update weighted rotation
    rotation = calculate_weighted_rotation(team_id, recent_games)
    state.rotation = rotation

    # Get current EPM values
    player_epm = database.get_player_epm(date)

    # Recalculate baseline EPM aggregates
    state.baseline_off_impact = sum(
        (rotation[p] / 48) * player_epm[p]['OFF']
        for p in rotation.keys()
    )
    state.baseline_def_impact = sum(
        (rotation[p] / 48) * player_epm[p]['DEF']
        for p in rotation.keys()
    )

    # 8. Save updated state
    database.update_team_state(team_id, date, state)
```

### Step 3: Weekly Venue Effect Recalculation

**Every Monday (or configured interval):**

```python
def weekly_update_venue_effects():
    """
    Recalculate team-specific venue effects using 15-game weighted residuals.
    """
    for team in all_teams:
        recent_games = database.get_recent_games(team.id, limit=60)

        # Separate by venue
        home_games = [g for g in recent_games if g.venue == 'home']
        away_games = [g for g in recent_games if g.venue == 'away']

        # Calculate weighted residuals
        home_weights = [(0.5)**(i/15) for i in range(len(home_games))]
        away_weights = [(0.5)**(i/15) for i in range(len(away_games))]

        # Offensive residuals
        home_off_residuals = [g.residual_off for g in home_games]
        away_off_residuals = [g.residual_off for g in away_games]

        home_off_adj = sum(w * r for w, r in zip(home_weights, home_off_residuals)) / sum(home_weights)
        away_off_adj = sum(w * r for w, r in zip(away_weights, away_off_residuals)) / sum(away_weights)

        venue_off_impact = home_off_adj - away_off_adj

        # Repeat for defense and tempo
        venue_def_impact = calculate_venue_def_impact(home_games, away_games)
        venue_tempo_impact = calculate_venue_tempo_impact(home_games, away_games)

        # Update team state
        database.update_venue_effects(team.id, today, {
            'venue_off_adj': venue_off_impact,
            'venue_def_adj': venue_def_impact,
            'venue_tempo_adj': venue_tempo_impact,
        })
```

---

## Pre-Game Workflow

**Run 2 hours before tipoff** (allows time for late injury updates).

### Step 1: Load Team State

```python
def load_team_state(team_id, game_date):
    """
    Retrieve current team state.
    """
    state = database.get_team_state(team_id, date=game_date)

    return {
        'baseline_adj_off': state.baseline_adj_off,
        'baseline_adj_def': state.baseline_adj_def,
        'baseline_adj_tempo': state.baseline_adj_tempo,
        'sigma_rolling_off': state.sigma_rolling_off,
        'sigma_rolling_def': state.sigma_rolling_def,
        'sigma_rolling_tempo': state.sigma_rolling_tempo,
        'rotation': state.rotation,
        'baseline_off_impact': state.baseline_off_impact,
        'baseline_def_impact': state.baseline_def_impact,
        'venue_off_adj': state.venue_off_adj,
        'venue_def_adj': state.venue_def_adj,
        'venue_tempo_adj': state.venue_tempo_adj,
    }
```

### Step 2: Get External Inputs

```python
def get_game_inputs(game_id, team_id):
    """
    Gather all external inputs for today's game.
    """
    # 1. Player availability (injury reports)
    availability = injury_api.get_player_availability(game_id, team_id)

    # 2. Minutes projections (3rd party)
    projected_minutes = minutes_api.get_projections(game_id, team_id)

    # Filter by availability
    available_players = {
        player_id: minutes
        for player_id, minutes in projected_minutes.items()
        if availability[player_id] not in ['out', 'doubtful']
    }

    # Normalize to 240
    total_proj = sum(available_players.values())
    normalized_minutes = {
        player_id: (minutes / total_proj) * 240
        for player_id, minutes in available_players.items()
    }

    # 3. Player EPM values (from daily scrape)
    player_epm = database.get_player_epm(team_id, date=game_date)

    return {
        'projected_minutes': normalized_minutes,
        'player_epm': player_epm,
    }
```

### Step 3: Calculate Lineup Adjustment

```python
def calculate_lineup_adjustment(state, inputs):
    """
    Calculate today's lineup impact vs baseline rotation.
    """
    # Today's rotation EPM aggregate
    today_off_impact = sum(
        (inputs['projected_minutes'][p] / 48) * inputs['player_epm'][p]['OFF']
        for p in inputs['projected_minutes'].keys()
    )
    today_def_impact = sum(
        (inputs['projected_minutes'][p] / 48) * inputs['player_epm'][p]['DEF']
        for p in inputs['projected_minutes'].keys()
    )

    # Adjustment vs baseline
    lineup_off_adj = today_off_impact - state['baseline_off_impact']
    lineup_def_adj = today_def_impact - state['baseline_def_impact']

    return {
        'off': lineup_off_adj,
        'def': lineup_def_adj,
        'today_off_impact': today_off_impact,
        'today_def_impact': today_def_impact,
    }
```

### Step 4: Calculate Venue Adjustment

```python
def calculate_venue_adjustment(team_id, game_id, state):
    """
    Apply team-specific venue effect.
    """
    game_info = database.get_game_info(game_id)

    if game_info.home_team_id == team_id:
        # Playing at home
        venue_off_adj = state['venue_off_adj']
        venue_def_adj = state['venue_def_adj']
        venue_tempo_adj = state['venue_tempo_adj']
    else:
        # Playing away (inverse of home advantage)
        venue_off_adj = -state['venue_off_adj']
        venue_def_adj = -state['venue_def_adj']
        venue_tempo_adj = -state['venue_tempo_adj']

    return {
        'off': venue_off_adj,
        'def': venue_def_adj,
        'tempo': venue_tempo_adj,
    }
```

### Step 5: Calculate Rest Adjustment

```python
def calculate_rest_adjustment(team_id, game_date):
    """
    Apply universal rest day adjustment.
    """
    rest_days = calculate_rest_days(team_id, game_date)

    # Map to category
    if rest_days == 0:
        category = 'back_to_back'
    elif rest_days == 1:
        category = 'one_day_rest'
    elif rest_days == 2:
        category = 'two_day_rest'
    else:
        category = 'extended_rest'

    adjustments = REST_ADJUSTMENTS[category]

    return {
        'off': adjustments['off'],
        'def': adjustments['def'],
        'tempo': adjustments['tempo'],
    }
```

### Step 6: Calculate Timezone Adjustment

```python
def calculate_timezone_adjustment(team_id, game_id):
    """
    Apply universal timezone travel adjustment.
    """
    game_info = database.get_game_info(game_id)

    # Team's home timezone
    team_home_tz = TEAM_TIMEZONES[team_id]

    # Game timezone (venue location)
    game_tz = TEAM_TIMEZONES[game_info.home_team_id]

    # Lookup adjustment
    combo = (team_home_tz, game_tz)
    adjustments = TIMEZONE_ADJUSTMENTS.get(combo, {'off': 0, 'def': 0, 'tempo': 0})

    return {
        'off': adjustments['off'],
        'def': adjustments['def'],
        'tempo': adjustments['tempo'],
    }
```

### Step 7: Calculate Final Expected Metrics

```python
def calculate_expected_metrics(team_id, game_id):
    """
    Combine all adjustments to produce final expected metrics for simulation.
    """
    # Load state
    state = load_team_state(team_id, game_date)

    # Get inputs
    inputs = get_game_inputs(game_id, team_id)

    # Calculate adjustments
    lineup_adj = calculate_lineup_adjustment(state, inputs)
    venue_adj = calculate_venue_adjustment(team_id, game_id, state)
    rest_adj = calculate_rest_adjustment(team_id, game_date)
    timezone_adj = calculate_timezone_adjustment(team_id, game_id)

    # Final expected metrics
    expected_off = (
        state['baseline_adj_off'] +
        lineup_adj['off'] +
        venue_adj['off'] +
        rest_adj['off'] +
        timezone_adj['off']
    )

    expected_def = (
        state['baseline_adj_def'] +
        lineup_adj['def'] +
        venue_adj['def'] +
        rest_adj['def'] +
        timezone_adj['def']
    )

    expected_tempo = (
        state['baseline_adj_tempo'] +
        venue_adj['tempo'] +
        rest_adj['tempo'] +
        timezone_adj['tempo']
    )

    return {
        'expected_off_eff': expected_off,
        'expected_def_eff': expected_def,
        'expected_tempo': expected_tempo,
        'sigma_off': state['sigma_rolling_off'],
        'sigma_def': state['sigma_rolling_def'],
        'sigma_tempo': state['sigma_rolling_tempo'],
    }
```

### Step 8: Store Pre-Game Expectation

**CRITICAL:** Store expectations for post-game residual calculation.

```python
def store_pregame_expectation(game_id, team_id, expectations, adjustments):
    """
    Store all pre-game calculations for post-game analysis.
    """
    database.insert_pregame_expectation(game_id, team_id, {
        'expected_off_eff': expectations['expected_off_eff'],
        'expected_def_eff': expectations['expected_def_eff'],
        'expected_tempo': expectations['expected_tempo'],

        # Store adjustments for debugging/analysis
        'lineup_off_adj': adjustments['lineup']['off'],
        'lineup_def_adj': adjustments['lineup']['def'],
        'venue_off_adj': adjustments['venue']['off'],
        'venue_def_adj': adjustments['venue']['def'],
        'rest_off_adj': adjustments['rest']['off'],
        'rest_def_adj': adjustments['rest']['def'],
        'timezone_off_adj': adjustments['timezone']['off'],
        'timezone_def_adj': adjustments['timezone']['def'],

        # Store rotation for historical tracking
        'projected_minutes': adjustments['inputs']['projected_minutes'],
    })
```

---

## Simulation Engine

### Overview

**Monte Carlo simulation with 10,000 iterations** to generate probability distributions for betting markets.

**Inputs (per team):**
- Expected offensive efficiency (μ, σ)
- Expected defensive efficiency (μ, σ)
- Expected tempo (μ, σ)

**Outputs:**
- Spread distribution and probabilities
- Total distribution and probabilities
- Team total distributions
- Moneyline probabilities

### Simulation Process

```python
def simulate_game(team_a_id, team_b_id, game_id, num_iterations=10000):
    """
    Run Monte Carlo simulation for game.
    """
    # Get expected metrics for both teams
    team_a_metrics = calculate_expected_metrics(team_a_id, game_id)
    team_b_metrics = calculate_expected_metrics(team_b_id, game_id)

    results = []

    for iteration in range(num_iterations):
        # 1. Sample team efficiencies from normal distributions
        team_a_off = np.random.normal(
            team_a_metrics['expected_off_eff'],
            team_a_metrics['sigma_off']
        )
        team_a_def = np.random.normal(
            team_a_metrics['expected_def_eff'],
            team_a_metrics['sigma_def']
        )

        team_b_off = np.random.normal(
            team_b_metrics['expected_off_eff'],
            team_b_metrics['sigma_off']
        )
        team_b_def = np.random.normal(
            team_b_metrics['expected_def_eff'],
            team_b_metrics['sigma_def']
        )

        # 2. Sample tempos
        team_a_tempo = np.random.normal(
            team_a_metrics['expected_tempo'],
            team_a_metrics['sigma_tempo']
        )
        team_b_tempo = np.random.normal(
            team_b_metrics['expected_tempo'],
            team_b_metrics['sigma_tempo']
        )

        # 3. Calculate game tempo using selected interaction model
        game_tempo = calculate_game_tempo_interaction(
            team_a_tempo, team_b_tempo,
            team_a_off, team_a_def,
            team_b_off, team_b_def
        )

        possessions_per_team = game_tempo  # possessions per 48 minutes

        # 4. Calculate team scores using selected interaction model
        team_a_points = calculate_team_score_interaction(
            team_a_off, team_b_def, possessions_per_team
        )
        team_b_points = calculate_team_score_interaction(
            team_b_off, team_a_def, possessions_per_team
        )

        # 5. Store results
        results.append({
            'team_a_points': team_a_points,
            'team_b_points': team_b_points,
            'spread': team_a_points - team_b_points,
            'total': team_a_points + team_b_points,
        })

    return results
```

### Interaction Model Functions

**Offense-Defense Interaction:**

```python
def calculate_team_score_interaction(team_off, opp_def, possessions):
    """
    Calculate team score using selected interaction model from backfitting.
    """
    if INTERACTION_MODEL_OFF_DEF == 'simple_average':
        eff = (team_off + opp_def) / 2
        points = eff * possessions / 100

    elif INTERACTION_MODEL_OFF_DEF == 'multiplicative':
        league_avg = CONFIG['league_average_efficiency']
        defensive_factor = opp_def / league_avg
        adjusted_off = team_off * defensive_factor
        points = adjusted_off * possessions / 100

    else:
        raise ValueError(f"Unknown interaction model: {INTERACTION_MODEL_OFF_DEF}")

    return points
```

**Tempo Interaction:**

```python
def calculate_game_tempo_interaction(team_a_tempo, team_b_tempo,
                                    team_a_off, team_a_def,
                                    team_b_off, team_b_def):
    """
    Calculate game tempo using selected interaction model from backfitting.
    """
    if INTERACTION_MODEL_TEMPO == 'simple_average':
        return (team_a_tempo + team_b_tempo) / 2

    elif INTERACTION_MODEL_TEMPO == 'weighted_strength':
        team_a_str = team_a_off - team_a_def
        team_b_str = team_b_off - team_b_def
        str_sum = abs(team_a_str) + abs(team_b_str)

        if str_sum > 0:
            team_a_weight = abs(team_a_str) / str_sum
            team_b_weight = abs(team_b_str) / str_sum
            return team_a_weight * team_a_tempo + team_b_weight * team_b_tempo
        else:
            return (team_a_tempo + team_b_tempo) / 2

    elif INTERACTION_MODEL_TEMPO == 'faster_dictates':
        faster = max(team_a_tempo, team_b_tempo)
        slower = min(team_a_tempo, team_b_tempo)
        return 0.6 * faster + 0.4 * slower

    elif INTERACTION_MODEL_TEMPO == 'defensive_focus':
        avg_tempo = (team_a_tempo + team_b_tempo) / 2
        league_avg_def = CONFIG['league_average_efficiency']
        def_factor = (team_a_def + team_b_def) / (2 * league_avg_def)
        return avg_tempo * def_factor

    else:
        raise ValueError(f"Unknown tempo model: {INTERACTION_MODEL_TEMPO}")
```

### Output Analysis

```python
def analyze_simulation_results(results):
    """
    Convert simulation results to betting market probabilities.
    """
    # Extract distributions
    spreads = [r['spread'] for r in results]
    totals = [r['total'] for r in results]
    team_a_points = [r['team_a_points'] for r in results]
    team_b_points = [r['team_b_points'] for r in results]

    # Summary statistics
    spread_mean = np.mean(spreads)
    spread_std = np.std(spreads)
    total_mean = np.mean(totals)
    total_std = np.std(totals)

    # Moneyline probability
    team_a_win_prob = sum(1 for r in results if r['spread'] > 0) / len(results)
    team_b_win_prob = 1 - team_a_win_prob

    return {
        'spread': {
            'mean': spread_mean,
            'std': spread_std,
            'distribution': spreads,
        },
        'total': {
            'mean': total_mean,
            'std': total_std,
            'distribution': totals,
        },
        'team_a_total': {
            'mean': np.mean(team_a_points),
            'std': np.std(team_a_points),
            'distribution': team_a_points,
        },
        'team_b_total': {
            'mean': np.mean(team_b_points),
            'std': np.std(team_b_points),
            'distribution': team_b_points,
        },
        'moneyline': {
            'team_a_win_prob': team_a_win_prob,
            'team_b_win_prob': team_b_win_prob,
        },
    }
```

### Market Probability Calculations

```python
def calculate_market_probabilities(analysis, market_lines):
    """
    Calculate probabilities for specific betting lines.
    """
    results = {}

    # Spread
    if 'spread' in market_lines:
        line = market_lines['spread']
        prob_cover = sum(1 for s in analysis['spread']['distribution'] if s > line) / len(analysis['spread']['distribution'])
        results['spread'] = {
            'line': line,
            'prob_cover': prob_cover,
            'prob_not_cover': 1 - prob_cover,
        }

    # Total
    if 'total' in market_lines:
        line = market_lines['total']
        prob_over = sum(1 for t in analysis['total']['distribution'] if t > line) / len(analysis['total']['distribution'])
        results['total'] = {
            'line': line,
            'prob_over': prob_over,
            'prob_under': 1 - prob_over,
        }

    # Team totals
    if 'team_a_total' in market_lines:
        line = market_lines['team_a_total']
        prob_over = sum(1 for t in analysis['team_a_total']['distribution'] if t > line) / len(analysis['team_a_total']['distribution'])
        results['team_a_total'] = {
            'line': line,
            'prob_over': prob_over,
            'prob_under': 1 - prob_over,
        }

    # Moneyline (fair odds)
    results['moneyline'] = {
        'team_a_win_prob': analysis['moneyline']['team_a_win_prob'],
        'team_a_fair_odds': prob_to_american_odds(analysis['moneyline']['team_a_win_prob']),
        'team_b_win_prob': analysis['moneyline']['team_b_win_prob'],
        'team_b_fair_odds': prob_to_american_odds(analysis['moneyline']['team_b_win_prob']),
    }

    return results
```

### Helper Functions

```python
def prob_to_american_odds(prob):
    """
    Convert probability to American odds format.
    """
    if prob >= 0.5:
        # Favorite (negative odds)
        return -100 * prob / (1 - prob)
    else:
        # Underdog (positive odds)
        return 100 * (1 - prob) / prob
```

---

## Post-Game Workflow

**Runs after each game completes** (~30 minutes post-game for box scores).

### Step 1: Retrieve Box Score Data

```python
def fetch_box_score(game_id):
    """
    Fetch complete box score from NBA API.
    """
    box_score = nba_api.get_box_score(game_id)

    return {
        'game_id': game_id,
        'date': box_score.date,
        'minutes': box_score.game_minutes,  # 48 or OT

        # Team A stats
        'team_a_id': box_score.team_a_id,
        'team_a_points': box_score.team_a_points,
        'team_a_fga': box_score.team_a_fga,
        'team_a_fta': box_score.team_a_fta,
        'team_a_oreb': box_score.team_a_oreb,
        'team_a_to': box_score.team_a_to,

        # Team B stats
        'team_b_id': box_score.team_b_id,
        'team_b_points': box_score.team_b_points,
        'team_b_fga': box_score.team_b_fga,
        'team_b_fta': box_score.team_b_fta,
        'team_b_oreb': box_score.team_b_oreb,
        'team_b_to': box_score.team_b_to,

        # Player minutes
        'team_a_player_minutes': box_score.team_a_player_minutes,  # {player_id: minutes}
        'team_b_player_minutes': box_score.team_b_player_minutes,
    }
```

### Step 2: Calculate Observed Metrics

```python
def calculate_observed_metrics(box_score, team_id):
    """
    Calculate observed efficiency and tempo from box score.
    """
    # Determine if team_a or team_b
    if team_id == box_score['team_a_id']:
        team_stats = 'team_a'
        opp_stats = 'team_b'
    else:
        team_stats = 'team_b'
        opp_stats = 'team_a'

    # Calculate possessions
    team_poss = 0.5 * (
        box_score[f'{team_stats}_fga'] +
        0.475 * box_score[f'{team_stats}_fta'] -
        box_score[f'{team_stats}_oreb'] +
        box_score[f'{team_stats}_to']
    )

    opp_poss = 0.5 * (
        box_score[f'{opp_stats}_fga'] +
        0.475 * box_score[f'{opp_stats}_fta'] -
        box_score[f'{opp_stats}_oreb'] +
        box_score[f'{opp_stats}_to']
    )

    # Offensive efficiency (per 100 possessions)
    observed_off_eff = (box_score[f'{team_stats}_points'] / team_poss) * 100

    # Defensive efficiency
    observed_def_eff = (box_score[f'{opp_stats}_points'] / opp_poss) * 100

    # Raw tempo (normalized to 48 minutes)
    observed_raw_tempo = ((team_poss + opp_poss) / 2) * (48 / box_score['minutes'])

    # League-normalize tempo
    league_avg_tempo = calculate_league_avg_tempo(box_score['date'])
    observed_adj_tempo = observed_raw_tempo - league_avg_tempo + 100

    return {
        'observed_off_eff': observed_off_eff,
        'observed_def_eff': observed_def_eff,
        'observed_adj_tempo': observed_adj_tempo,
        'possessions': team_poss,
    }
```

### Step 3: Calculate Residuals

```python
def calculate_residuals(game_id, team_id, observed):
    """
    Calculate residuals (observed - expected).
    """
    # Retrieve pre-game expectation
    pregame = database.get_pregame_expectation(game_id, team_id)

    residuals = {
        'residual_off': observed['observed_off_eff'] - pregame['expected_off_eff'],
        'residual_def': observed['observed_def_eff'] - pregame['expected_def_eff'],
        'residual_tempo': observed['observed_adj_tempo'] - pregame['expected_tempo'],
    }

    return residuals
```

### Step 4: Store Game Record

```python
def store_game_record(game_id, team_id, box_score, observed, residuals):
    """
    Store complete game record for historical tracking.
    """
    # Determine venue
    if team_id == box_score['team_a_id']:
        venue = 'home' if box_score['home_team_id'] == team_id else 'away'
        player_minutes = box_score['team_a_player_minutes']
    else:
        venue = 'home' if box_score['home_team_id'] == team_id else 'away'
        player_minutes = box_score['team_b_player_minutes']

    # Get pregame data
    pregame = database.get_pregame_expectation(game_id, team_id)

    database.insert_game_history({
        'game_id': game_id,
        'team_id': team_id,
        'date': box_score['date'],
        'venue': venue,

        # Observed outcomes
        'observed_off_eff': observed['observed_off_eff'],
        'observed_def_eff': observed['observed_def_eff'],
        'observed_tempo': observed['observed_adj_tempo'],

        # Pre-game expectations
        'expected_off_eff': pregame['expected_off_eff'],
        'expected_def_eff': pregame['expected_def_eff'],
        'expected_tempo': pregame['expected_tempo'],

        # Residuals
        'residual_off': residuals['residual_off'],
        'residual_def': residuals['residual_def'],
        'residual_tempo': residuals['residual_tempo'],

        # Raw data for future recalculation
        'player_minutes': player_minutes,  # JSON
        'possessions': observed['possessions'],
    })
```

### Step 5: Update Team State

Team state updates are handled by the **Daily Update Workflow** (runs at 2am CT).

Post-game workflow only stores the game record. The daily update will:
1. Update DnT baselines (from scrape)
2. Bayesian update tempo
3. Recalculate weighted rotation
4. Update rolling standard deviations
5. (Weekly) recalculate venue effects

---

## Implementation Details

### Database Schema

#### Team State Table

```sql
CREATE TABLE team_state (
    team_id INT,
    date DATE,

    -- Baselines (from DnT)
    baseline_adj_off DECIMAL(5,2),
    baseline_adj_def DECIMAL(5,2),

    -- Tempo (internal Bayesian tracking)
    baseline_adj_tempo DECIMAL(5,2),
    sigma_bayesian_tempo DECIMAL(5,2),
    sigma_weighted_tempo DECIMAL(5,2),
    sigma_final_tempo DECIMAL(5,2),

    -- Rolling standard deviations (for simulation)
    sigma_rolling_off DECIMAL(5,2),
    sigma_rolling_def DECIMAL(5,2),
    sigma_rolling_tempo DECIMAL(5,2),

    -- Weighted rotation (JSON: {player_id: expected_minutes})
    rotation JSONB,

    -- Baseline rotation EPM aggregates
    baseline_off_impact DECIMAL(5,2),
    baseline_def_impact DECIMAL(5,2),

    -- Team-specific venue effects (dynamic, weekly recalc)
    venue_off_adj DECIMAL(5,2),
    venue_def_adj DECIMAL(5,2),
    venue_tempo_adj DECIMAL(5,2),

    PRIMARY KEY (team_id, date),
    INDEX idx_team_latest (team_id, date DESC)
);
```

#### Game History Table

```sql
CREATE TABLE game_history (
    game_id INT,
    team_id INT,
    date DATE,
    venue VARCHAR(10),  -- 'home' or 'away'

    -- Observed outcomes
    observed_off_eff DECIMAL(5,2),
    observed_def_eff DECIMAL(5,2),
    observed_tempo DECIMAL(5,2),

    -- Pre-game expectations
    expected_off_eff DECIMAL(5,2),
    expected_def_eff DECIMAL(5,2),
    expected_tempo DECIMAL(5,2),

    -- Residuals (observed - expected)
    residual_off DECIMAL(5,2),
    residual_def DECIMAL(5,2),
    residual_tempo DECIMAL(5,2),

    -- Raw data for recalculation
    player_minutes JSONB,  -- {player_id: minutes}
    possessions DECIMAL(6,2),

    PRIMARY KEY (game_id, team_id),
    INDEX idx_team_date (team_id, date DESC)
);
```

#### Player EPM Table (Daily Scrape)

```sql
CREATE TABLE player_epm (
    player_id INT,
    date DATE,

    -- From DunksAndThrees
    OFF DECIMAL(4,2),  -- Offensive EPM per 100 poss
    DEF DECIMAL(4,2),  -- Defensive EPM per 100 poss

    PRIMARY KEY (player_id, date),
    INDEX idx_date (date)
);
```

#### Pre-Game Expectations Table

```sql
CREATE TABLE pregame_expectations (
    game_id INT,
    team_id INT,

    -- Expected metrics
    expected_off_eff DECIMAL(5,2),
    expected_def_eff DECIMAL(5,2),
    expected_tempo DECIMAL(5,2),

    -- Adjustments (for debugging/analysis)
    lineup_off_adj DECIMAL(5,2),
    lineup_def_adj DECIMAL(5,2),
    venue_off_adj DECIMAL(5,2),
    venue_def_adj DECIMAL(5,2),
    rest_off_adj DECIMAL(5,2),
    rest_def_adj DECIMAL(5,2),
    timezone_off_adj DECIMAL(5,2),
    timezone_def_adj DECIMAL(5,2),

    -- Projected rotation
    projected_minutes JSONB,

    PRIMARY KEY (game_id, team_id)
);
```

#### Team DnT Metrics Table (Daily Scrape)

```sql
CREATE TABLE team_dnt_metrics (
    team_id INT,
    date DATE,

    adj_off DECIMAL(5,2),
    adj_def DECIMAL(5,2),
    raw_tempo DECIMAL(5,2),

    PRIMARY KEY (team_id, date)
);
```

### Configuration Parameters

```python
CONFIG = {
    # Temporal weighting
    'half_life': 15,  # games

    # Bayesian observation variance (tempo only)
    'observation_variance_tempo': 25,  # σ_obs = 5

    # Bayesian variance floor (prevent overconfidence)
    'bayesian_floor_tempo': 1.5,  # minimum σ

    # Lookback window
    'lookback_window': 60,  # games to keep in history

    # Rolling standard deviation window
    'rolling_window': 30,  # games

    # Simulation
    'num_iterations': 10000,

    # Phase 1 outputs
    'markets': ['spread', 'total', 'team_totals', 'moneyline'],

    # Update frequencies
    'daily_scrape_time': '02:00:00',  # 2am CT
    'venue_update_interval': 'weekly',  # Every Monday
}
```

### Core Python Functions

#### Weight Calculation

```python
def calculate_weights(num_games: int, half_life: int = 15) -> List[float]:
    """
    Calculate exponential decay weights for historical games.

    Returns weights in reverse chronological order:
    [1.0, 0.954, 0.910, ...] where index 0 = most recent game
    """
    return [(0.5) ** (i / half_life) for i in range(num_games)]
```

#### Weighted Statistics

```python
def weighted_mean(values: List[float], weights: List[float]) -> float:
    """Calculate weighted average."""
    return sum(w * v for w, v in zip(weights, values)) / sum(weights)


def weighted_variance(values: List[float], weights: List[float]) -> float:
    """Calculate weighted variance."""
    mean = weighted_mean(values, weights)
    var = sum(w * (v - mean)**2 for w, v in zip(weights, values)) / sum(weights)
    return var


def weighted_std_dev(values: List[float], weights: List[float]) -> float:
    """Calculate weighted standard deviation."""
    return np.sqrt(weighted_variance(values, weights))
```

#### Bayesian Update (Tempo Only)

```python
def bayesian_tempo_update(prior_mean: float,
                         prior_var: float,
                         observed: float,
                         obs_var: float) -> Tuple[float, float]:
    """
    Perform Bayesian update for tempo with normal-normal conjugate prior.

    Returns: (posterior_mean, posterior_variance)
    """
    posterior_var = (prior_var * obs_var) / (prior_var + obs_var)
    posterior_mean = (
        (obs_var * prior_mean + prior_var * observed) /
        (prior_var + obs_var)
    )

    # Apply floor to prevent overconfidence
    posterior_var = max(posterior_var, CONFIG['bayesian_floor_tempo']**2)

    return posterior_mean, posterior_var
```

#### Weighted Rotation Calculation

```python
def calculate_weighted_rotation(team_id: int,
                               recent_games: List[Game],
                               half_life: int = 15) -> Dict[int, float]:
    """
    Calculate weighted average minutes for each player, normalized to 240.

    Args:
        team_id: Team ID
        recent_games: List of recent games (reverse chronological)
        half_life: Exponential decay half-life

    Returns:
        {player_id: expected_minutes} normalized to sum = 240
    """
    # Aggregate player minutes across games
    player_minutes = defaultdict(list)

    for i, game in enumerate(recent_games):
        for player_id, minutes in game.player_minutes.items():
            player_minutes[player_id].append((i, minutes))

    # Calculate weighted average for each player
    weights = [(0.5)**(i/half_life) for i in range(len(recent_games))]

    raw_weighted_minutes = {}
    for player_id, game_minutes in player_minutes.items():
        # Get weights for games this player appeared in
        player_weights = [weights[i] for i, _ in game_minutes]
        minutes_values = [m for _, m in game_minutes]

        raw_weighted_minutes[player_id] = weighted_mean(minutes_values, player_weights)

    # Normalize to 240
    total_raw = sum(raw_weighted_minutes.values())

    normalized_rotation = {
        player_id: (minutes / total_raw) * 240
        for player_id, minutes in raw_weighted_minutes.items()
    }

    return normalized_rotation
```

#### League Average Tempo Calculation

```python
def calculate_league_avg_tempo(date: datetime.date) -> float:
    """
    Calculate league-wide average tempo for normalization.

    Uses rolling 30-day window.
    """
    start_date = date - timedelta(days=30)

    games = database.get_all_games(start_date=start_date, end_date=date)

    total_possessions = 0
    total_game_minutes = 0

    for game in games:
        # Calculate possessions for both teams
        team_a_poss = 0.5 * (game.team_a_fga + 0.475*game.team_a_fta -
                             game.team_a_oreb + game.team_a_to)
        team_b_poss = 0.5 * (game.team_b_fga + 0.475*game.team_b_fta -
                             game.team_b_oreb + game.team_b_to)

        avg_poss = (team_a_poss + team_b_poss) / 2

        total_possessions += avg_poss
        total_game_minutes += game.minutes

    # Average pace across all games, normalized to 48 minutes
    league_avg_tempo = (total_possessions / total_game_minutes) * 48

    return league_avg_tempo
```

---

## Validation Framework

### Layer 1: Simulation Output Validation

After each simulation run:

```python
def validate_simulation_outputs(results, team_a_metrics, team_b_metrics):
    """
    Verify that simulated outcomes aggregate correctly to inputs.
    """
    # Average across iterations
    avg_team_a_off = mean([
        calculate_eff(r['team_a_points'], r['possessions'])
        for r in results
    ])

    # Should match input (within tolerance)
    assert abs(avg_team_a_off - team_a_metrics['expected_off_eff']) < 0.5, \
        f"Simulation avg {avg_team_a_off} doesn't match input {team_a_metrics['expected_off_eff']}"

    # Check variance
    std_team_a_off = std([
        calculate_eff(r['team_a_points'], r['possessions'])
        for r in results
    ])
    assert abs(std_team_a_off - team_a_metrics['sigma_off']) < 0.3, \
        f"Simulation std {std_team_a_off} doesn't match input {team_a_metrics['sigma_off']}"
```

### Layer 2: Distribution Validation

```python
def validate_distributions(results):
    """
    Check that output distributions have realistic shapes.
    """
    spreads = [r['spread'] for r in results]

    # Should be roughly normal
    _, p_value = scipy.stats.normaltest(spreads)
    assert p_value > 0.05, "Spread distribution not normal"

    # Check for outliers
    q99 = np.percentile(spreads, 99)
    assert q99 < 40, f"Unrealistic 99th percentile spread: {q99}"

    # Total should also be roughly normal
    totals = [r['total'] for r in results]
    _, p_value_total = scipy.stats.normaltest(totals)
    assert p_value_total > 0.05, "Total distribution not normal"
```

### Layer 3: Historical Backtesting

**Walk-forward validation:**

```python
def backtest_season(season, validation_teams=None):
    """
    Simulate predictions for each game using only prior data.
    """
    games = get_all_games(season)
    predictions = []

    for game in games:
        # Use ONLY data available before this game
        team_a_metrics = calculate_expected_metrics_historical(
            game.team_a_id, game.date
        )
        team_b_metrics = calculate_expected_metrics_historical(
            game.team_b_id, game.date
        )

        # Run simulation
        results = simulate_game_historical(team_a_metrics, team_b_metrics)
        analysis = analyze_simulation_results(results)

        # Store prediction
        predictions.append({
            'game_id': game.id,
            'date': game.date,
            'predicted_spread': analysis['spread']['mean'],
            'predicted_total': analysis['total']['mean'],
            'actual_spread': game.actual_spread,
            'actual_total': game.actual_total,
        })

    # Calculate accuracy metrics
    return analyze_predictions(predictions)


def analyze_predictions(predictions):
    """
    Calculate prediction accuracy metrics.
    """
    # Mean Absolute Error
    mae_spread = mean([
        abs(p['predicted_spread'] - p['actual_spread'])
        for p in predictions
    ])
    mae_total = mean([
        abs(p['predicted_total'] - p['actual_total'])
        for p in predictions
    ])

    # Root Mean Square Error
    rmse_spread = sqrt(mean([
        (p['predicted_spread'] - p['actual_spread'])**2
        for p in predictions
    ]))
    rmse_total = sqrt(mean([
        (p['predicted_total'] - p['actual_total'])**2
        for p in predictions
    ]))

    # Directional accuracy (spread)
    correct_direction = sum([
        1 for p in predictions
        if np.sign(p['predicted_spread']) == np.sign(p['actual_spread'])
    ])
    directional_accuracy = correct_direction / len(predictions)

    return {
        'mae_spread': mae_spread,
        'mae_total': mae_total,
        'rmse_spread': rmse_spread,
        'rmse_total': rmse_total,
        'directional_accuracy': directional_accuracy,
        'sample_size': len(predictions),
    }
```

### Layer 4: Benchmarking Against Vegas

**Closing Line Value (CLV):**

```python
def calculate_clv(predictions, market_lines):
    """
    Compare model predictions to Vegas closing lines.

    CLV = Sharper predictions beat closing lines over time.
    """
    results = []

    for pred in predictions:
        game_lines = market_lines[pred['game_id']]

        # Spread CLV
        spread_diff = abs(pred['predicted_spread'] - game_lines['closing_spread'])
        actual_diff = abs(game_lines['closing_spread'] - pred['actual_spread'])

        spread_clv = actual_diff - spread_diff  # Positive = model was closer

        # Total CLV
        total_diff = abs(pred['predicted_total'] - game_lines['closing_total'])
        actual_total_diff = abs(game_lines['closing_total'] - pred['actual_total'])

        total_clv = actual_total_diff - total_diff

        results.append({
            'game_id': pred['game_id'],
            'spread_clv': spread_clv,
            'total_clv': total_clv,
        })

    return {
        'avg_spread_clv': mean([r['spread_clv'] for r in results]),
        'avg_total_clv': mean([r['total_clv'] for r in results]),
        'positive_clv_rate': sum(1 for r in results if r['spread_clv'] > 0) / len(results),
    }
```

**Acceptable Thresholds:**

```python
VALIDATION_THRESHOLDS = {
    'mae_spread': 12.0,  # Within 12 points on average
    'mae_total': 15.0,   # Within 15 points total
    'rmse_spread': 15.0,
    'rmse_total': 18.0,
    'directional_accuracy': 0.52,  # Better than coin flip
    'clv_positive_rate': 0.48,  # Close to Vegas (they're sharp)
}
```

---

## Future Phases

### Phase 2: Situational Context Adjustments

**Goal:** Account for game importance and intensity variations.

#### NBA Cup (In-Season Tournament) Impacts

**Hypothesis:** Teams play harder in tournament games (especially early rounds).

**Potential adjustments:**
- Increase defensive intensity (lower scoring)
- Decrease tempo variance (more controlled play)
- Adjust for stakes (elimination games vs group stage)

**Backfitting methodology:**
- Compare NBA Cup games to regular season games
- Stratify by round (group stage, knockout, finals)
- Measure differences in pace, efficiency variance, home court advantage

**Implementation:**
```python
if game.is_nba_cup:
    if game.nba_cup_round == 'group_stage':
        tempo_adj += NBA_CUP_ADJUSTMENTS['group']['tempo']
        sigma_tempo *= NBA_CUP_ADJUSTMENTS['group']['variance_multiplier']
    elif game.nba_cup_round == 'knockout':
        tempo_adj += NBA_CUP_ADJUSTMENTS['knockout']['tempo']
        sigma_tempo *= NBA_CUP_ADJUSTMENTS['knockout']['variance_multiplier']
```

#### Playoff Adjustments

**Hypothesis:** Playoffs feature slower pace, better defense, lower variance.

**Potential adjustments:**
- Decrease tempo by ~3-5 possessions per 48
- Improve defensive efficiency by ~2-3 pts/100
- Reduce variance (teams play more conservatively)
- Amplify home court advantage (playoff crowds)
- Series context (down 0-2, facing elimination, etc.)

**Backfitting methodology:**
- Use last 5+ years of playoff data
- Compare to regular season performance for same teams
- Stratify by series game number (Game 1 vs Game 7)
- Measure home court advantage differences

**Implementation:**
```python
if game.is_playoffs:
    # Base playoff adjustments
    tempo_adj += PLAYOFF_ADJUSTMENTS['tempo']  # e.g., -4.0
    def_adj += PLAYOFF_ADJUSTMENTS['defense']   # e.g., -2.5 (better)

    # Variance reduction
    sigma_tempo *= PLAYOFF_ADJUSTMENTS['tempo_variance_mult']  # e.g., 0.7
    sigma_off *= PLAYOFF_ADJUSTMENTS['off_variance_mult']
    sigma_def *= PLAYOFF_ADJUSTMENTS['def_variance_mult']

    # Amplified home court
    if venue == 'home':
        venue_adj *= PLAYOFF_ADJUSTMENTS['home_court_multiplier']  # e.g., 1.3

    # Series context
    if game.series_status == 'elimination':
        # Team facing elimination plays harder
        facing_elim_team_off_adj += 2.0
        facing_elim_team_def_adj -= 1.0
```

---

### Phase 3: Expanded Markets

**Goal:** Extend simulation to support player props, halves, and quarters.

#### Player Props

**Requirements:**
- Player-level simulation (allocate possessions)
- Player-specific outcomes (shooting, rebounding, assists, etc.)
- Minutes projection integration
- Prop markets: PTS, REB, AST, STL, BLK, 3PM, PRA, etc.

**High-level approach:**
1. **Lineup rotation model** (possession-based, weighted by minutes)
2. **Possession allocation** (usage rates determine who gets the ball)
3. **Player-specific outcomes:**
   - Shooting: Player FG%, 3P%, shot distribution by zone
   - Free throws: Player FT rate and FT%
   - Rebounds: Player OReb%, DReb% vs opponent rates
   - Assists: Player AST% and teammate shooting efficiency
   - Steals/Blocks: Player STL%, BLK% vs opponent TO rate

**Validation:**
- Compare to DFS projections (DraftKings, FanDuel)
- Compare to Vegas player prop lines
- Backtest historical player performance distributions

#### Halves (1H Pregame, Live 2H)

**1H Pregame:**
- Scale simulation to 24 minutes (half game)
- Adjust tempo expectations (first halves slightly slower)
- Consider opening lineup vs bench rotation

**Live 2H (During Halftime):**
- Incorporate 1H actual results into priors
- Update tempo based on 1H pace
- Adjust for foul trouble, fatigue, score differential
- Bayesian update team performance in real-time

**Implementation:**
```python
def simulate_2h_live(game_id, halftime_state):
    """
    Simulate 2H using 1H actual performance as input.
    """
    # Update priors based on 1H
    team_a_1h_off = calculate_1h_off_efficiency(halftime_state)
    team_a_off_updated = bayesian_update(
        prior=team_a_expected_off,
        observed=team_a_1h_off
    )

    # Simulate remaining 24 minutes
    results = simulate_half(
        team_a_off_updated,
        team_b_off_updated,
        expected_tempo_updated,
        minutes=24
    )

    return analyze_results(results)
```

#### Quarters (1Q Pregame, Live 3Q, Live 4Q)

**1Q Pregame:**
- Scale to 12 minutes
- Opening lineup vs bench considerations
- Higher variance (small sample)

**Live 3Q (During Halftime):**
- Use 1H data to update priors
- Simulate 3Q only (12 minutes)

**Live 4Q (Between 3Q and 4Q):**
- Use 3Q data to update priors
- Account for score differential (clock management, fouling strategy)
- End-of-game variance increases

**Special considerations:**
- Clutch performance (last 5 min, score within 5)
- Intentional fouling strategies
- Garbage time (blowouts reduce starters' minutes)

---

## Key Design Decisions Summary

### 1. Leverage DunksAndThrees for Adjusted Efficiency
Don't reinvent the wheel. DnT's AdjO and AdjD are proven and trusted. Scrape daily and use as baselines.

### 2. Internal Tempo Tracking (Bayesian)
DnT doesn't have adjusted tempo, so we calculate our own using Bayesian conjugate prior updates with 15-game weighted variance.

### 3. 75/25 Philosophy (15-Game Half-Life)
75% of performance explained by last ~30 games (observable recent form), 25% by systemic factors (coaching, culture, intangibles).

### 4. Edge from Lineup Intelligence
Weighted rotation (15-game half-life) compared to today's expected rotation generates lineup adjustments using EPM values.

### 5. Rolling 30-Game Standard Deviation
For Monte Carlo sampling, use simple rolling window (stable, interpretable).

### 6. Backfitting Before Betting
Interaction models, venue effects, rest adjustments, and timezone adjustments MUST be empirically determined before live predictions.

### 7. Venue Effects: Team-Specific and Dynamic
Calculated as weighted residuals (15-game half-life), recalculated weekly to adapt to changes.

### 8. Rest and Timezone: Universal and Fixed
Adjustments apply equally to all teams. Determined once via backfitting, then held constant.

### 9. Post-Game: Store and Wait
Post-game workflow stores game records. Daily update (2am CT) handles all Bayesian updates and rotation recalculations.

### 10. Phase 1 Focus
Team-level markets only initially. Validates core framework before adding player-level complexity.

---

## Open Questions for Future Consideration

1. **Player-level defensive assignments:** Team-level defense only, or add matchup-specific adjustments?
2. **Trade handling:** How to integrate new players beyond "pure EPM addition"?
3. **Lineup chemistry:** Should certain 5-man units get synergy bonuses?
4. **Altitude effects:** Does Denver deserve special treatment beyond general venue effects?
5. **Travel fatigue:** Should cross-country travel distance be modeled separately from timezone?
6. **Division rivals:** Do familiarity effects exist (teams play each other 3-4 times)?
7. **Schedule density:** Does 4-games-in-5-nights fatigue compound beyond single B2B penalty?

---

## Implementation Roadmap

### Pre-Season (Before Betting Begins)

**1. Data Infrastructure**
- [ ] Set up database schema (PostgreSQL or similar)
- [ ] Implement DunksAndThrees API scraper
- [ ] Implement NBA box score API integration
- [ ] Implement injury report API integration
- [ ] Evaluate and select minutes projection provider

**2. Backfitting Analysis**
- [ ] Load 2024-25 and 2025-26 regular season data
- [ ] Test offense-defense interaction models (simple vs multiplicative)
- [ ] Test tempo interaction models (simple avg, weighted, faster dictates, etc.)
- [ ] Calculate team-specific venue effects (initial baselines)
- [ ] Calculate universal rest adjustments (B2B, extended rest)
- [ ] Calculate universal timezone adjustments (all 16 combinations)
- [ ] Store backfitting results in configuration

**3. Initialization**
- [ ] Load backfitting config into system
- [ ] Initialize all 30 team states (baselines, rotations, venue effects)
- [ ] Initialize game history (last 60 games per team)
- [ ] Validate initialization (completeness checks)

**4. System Implementation**
- [ ] Daily update workflow (2am CT cron job)
- [ ] Weekly venue update workflow (Monday cron job)
- [ ] Pre-game workflow (runs 2 hours before tipoff)
- [ ] Simulation engine (Monte Carlo with 10k iterations)
- [ ] Post-game workflow (runs 30 min after game ends)

**5. Validation**
- [ ] Historical backtest on 2023-24 season
- [ ] Calculate MAE, RMSE, directional accuracy
- [ ] Compare to Vegas closing lines (CLV analysis)
- [ ] Verify thresholds met (MAE spread <12, MAE total <15)

**6. Monitoring and Deployment**
- [ ] Set up logging and monitoring
- [ ] Create dashboards for daily tracking
- [ ] Implement alerts for anomalies
- [ ] Deploy to production environment

### Regular Season (Live Operations)

**Daily:**
- [ ] 2am CT: Scrape DnT data, update team states
- [ ] Pre-game: Run simulations 2 hours before each tipoff
- [ ] Post-game: Store game records after each game completes

**Weekly:**
- [ ] Monday: Recalculate venue effects for all teams
- [ ] Review model performance (MAE, CLV)
- [ ] Identify any anomalies or systematic errors

**Monthly:**
- [ ] Update league average efficiency (if using multiplicative model)
- [ ] Review backfitting parameters (consider re-running if needed)
- [ ] Validate rolling 30-game windows still appropriate

### Phase 2 & 3 Development

**Post-Season (Off-Season):**
- [ ] Implement NBA Cup adjustments (backfit using tournament data)
- [ ] Implement Playoff adjustments (backfit using playoff data)
- [ ] Begin player-level simulation development (Phase 3)

---

**Document Status:** Complete specification ready for implementation.

**Document Version:** 2.0 (December 2025)

**Last Updated:** December 17, 2025

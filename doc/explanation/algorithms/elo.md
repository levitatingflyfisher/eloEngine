# ELO

## TL;DR — when to pick it

ELO is the default. Pick it when you want a single, stable ranking
produced by an easy-to-explain algorithm, when your users produce
dozens to hundreds of pairwise comparisons, and when you do not have a
specific reason to reach for something else. It costs O(1) per match,
it is online (updates live as matches come in), and it has sixty years
of proven track record. If you cannot decide which algorithm to
enable, enable only ELO: `EloConfig(enabledAlgorithms: {AlgorithmId.elo})`.

## The core idea

ELO's central insight is small but important. Instead of tracking
*wins and losses* for each player, track *a single number per player*
— the rating — and update the rating by comparing **what happened**
against **what the ratings predicted would happen**.

The rating is always relative. A 1600 player and an 1800 player are in
a *meaningful* relationship, but saying "1600 is good" or "1600 is bad"
is meaningless without knowing the population.

Here is the whole algorithm in five lines:

1. Assume each player has a single hidden skill.
2. From the rating gap, predict the probability that A beats B.
3. A match happens. Score A's actual result: 1 (win), 0.5 (tie), 0 (loss).
4. Update A's rating by `K × (actual − predicted)`.
5. Update B's rating by the negative of that.

That's it. The K is just a scaling constant — how big a single match
matters. Larger K means faster learning but noisier ratings; smaller K
means stable but slow.

## Worked example

Four items — "Oliver", "Eliot", "James", "Milo" — each start at 1200.

Round 1: Oliver vs Eliot, Oliver wins.

- Expected score for Oliver: `1 / (1 + 10^((1200 − 1200) / 400)) = 0.5`.
- Actual score: 1.0.
- With K=32: Oliver's delta = `32 × (1.0 − 0.5) = +16`.
- Eliot's delta: `−16`.
- New ratings: Oliver 1216, Eliot 1184.

Round 2: Oliver vs James, Oliver wins.

- Expected for Oliver: `1 / (1 + 10^((1200 − 1216) / 400)) = 0.523`.
- Actual: 1.0.
- Delta: `32 × (1.0 − 0.523) = +15.3`.
- New: Oliver 1231.3, James 1184.7.

Notice that Oliver's second win gave him *slightly less* than his first
win. ELO has built up a tiny amount of evidence that Oliver is the
stronger player, so beating another default-rated opponent is "less
surprising" and earns less reward. This is the core of the update
rule, and it is what makes ELO converge.

## The expected-score formula, geometrically

The formula

$$ E_A = \frac{1}{1 + 10^{(R_B - R_A) / 400}} $$

is a sigmoid — an S-shaped curve. Plot it with the rating gap on the
x-axis and "probability A wins" on the y-axis:

```
    E_A
     ^
  1.0|                              ___----
     |                         __---
     |                     __-
  0.5|- - - - - - - - - -+
     |              _-__
     |         __--
  0.0|__----
     +---------------+---------------+--->
                   0                   rating gap
     -400                             +400
```

- At 0 rating gap, the prediction is 50/50.
- At +400 for A, A is predicted to win about 91% of the time.
- At +800 for A, A is predicted to win about 99%.

The number 400 is a historical constant chosen so that a 400-point gap
feels like "one class higher". It is arbitrary but conventional.

## What ELO is really doing

ELO is a stripped-down online estimator for the **Bradley-Terry
model**. Bradley-Terry says: assume each item has a latent strength
$\pi_i > 0$, and the probability that $i$ beats $j$ is
$\pi_i / (\pi_i + \pi_j)$. ELO's rating $R_i$ is equivalent to $400
\log_{10} \pi_i$ — it's just Bradley-Terry's latent strength on a more
readable scale, updated by one step of gradient ascent per match.

This means ELO inherits Bradley-Terry's assumptions:

- **One-dimensional skill.** If Oliver beats Eliot at morning and
  Eliot beats Oliver at night, ELO cannot represent that. It has to
  pick one number.
- **Transitivity.** If A beats B and B beats C, ELO's rating gap
  implies A beats C. Cycles confuse it.
- **Stable latent skill.** ELO assumes the true skill is not moving.
  Real humans improve, get tired, have off days. The K-factor is the
  blunt lever ELO gives you to react faster to change.

If any of these assumptions is violated badly, you want Glicko-2 (for
uncertainty and skill change) or TrueSkill (for richer belief
tracking) or HodgeRank (for cycles).

## The K-factor and why it decays

The K-factor controls how much one match moves a rating. Classical
chess ELO uses K=32 for new players, K=16 for intermediate, K=10 for
top grandmasters. `elo_engine` ships with `{0: 64, 10: 32, 30: 16}` as
the default `kFactorStages` — higher than chess, on the theory that
most consumers have small item sets and benefit from faster
convergence.

Why decay K at all? Because:

- Early on, the rating is a *guess*. You want it to move fast so it
  finds the right neighborhood.
- Late on, the rating is *earned*. You want it to stabilize so it
  doesn't flip on a bad day.

A big K early is forgiving; a small K late is conservative. It is the
single ELO knob most worth understanding.

## Failure modes

ELO fails quietly. Here are three ways it does:

**Cycles.** Rock beats scissors beats paper beats rock. Over many
matches, ELO will converge all three toward the same rating. This
looks fine — they are all equal — but it has *lost information*. The
data was "these three form a cycle", and ELO can't say that. HodgeRank
can.

**Stale population.** If you play the same pool of opponents forever,
everyone's relative ranking is correct but the *absolute* ratings
drift (one player winning against the whole pool lifts their number,
which lifts everyone's number by symmetry). The overall rating
distribution inflates. `elo_engine` doesn't fix this because for most
consumer apps the pool is fixed and the comparison is internal to that
pool — but if you ever expose ratings *across* sessions, you need a
recalibration step.

**Too few matches.** With only 5 matches across 20 items, most items
have played once or twice. Their ratings are basically still 1200 with
a tiny wiggle. Do not trust ELO rankings until each item has been in
at least 5-10 matches. Check `EloItem.matchCount` before acting on the
ranking.

## In `elo_engine`

- Rating lives on `EloItem.rating`.
- Updated live inside `EloEngine.record()`.
- Ranked via `EloEngine.rankings` (sorts by rating, descending).
- Also exposed as `RankingComparison.eloRanking` from
  `compareAlgorithms()`.
- The expected-score formula is available for direct use as
  `expectedScore(ratingA, ratingB)` in `package:elo_engine/elo_engine.dart`.
- Disabling ELO in `enabledAlgorithms` hides it from
  `RankingComparison` but **does not** stop `record()` from updating
  ratings — the rating field is free to maintain and other algorithms
  don't use it anyway. In practice, always leave ELO enabled.

## One-sentence summary

ELO is Bradley-Terry, squinted at, with one gradient step per match and
a readable scale.

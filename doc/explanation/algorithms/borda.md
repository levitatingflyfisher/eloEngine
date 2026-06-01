# Borda

## TL;DR — when to pick it

Enable Borda when you want a **cheap, intuitive, margin-sensitive
ranking** that most users can grasp without any technical
background. The Borda count is the oldest voting method in the
ensemble (Jean-Charles de Borda proposed it in 1770), and its
idea is beautifully simple: each pairwise win is worth some points,
each pairwise loss is worth fewer points, sum them up per item, and
sort. Borda does not satisfy the Condorcet criterion (it can rank a
non-Condorcet item above a Condorcet winner in rare cases), but it
handles margin information better than Copeland and is easier to
explain than Schulze. For most informal rankings, it's a great
middle-ground choice.

## The core idea

For N items, each pairwise win against item $i$ is worth
*some points*. The classical Borda count for ordinal ballots gives
$N - 1$ points for being ranked first on a ballot, $N - 2$ for
second, and so on. But in paired-comparison settings we don't have
ballots — we have pairwise match outcomes. The `elo_engine`
adaptation:

Each pairwise match where $i$ beat $j$ contributes +1 to $i$'s
Borda score and 0 (or −1 in signed variants) to $j$'s. Ties
contribute 0.5 to each. Skips are ignored.

Formally:
$$ \text{Borda}(i) = \sum_j (w_{ij} + 0.5 \cdot t_{ij}) $$

where $w_{ij}$ is wins of $i$ over $j$ and $t_{ij}$ is ties
between $i$ and $j$.

Sort items by Borda score descending. Done. This is exactly
equivalent to "total wins counted, with half-credit for ties".
Simple, transparent, and margin-aware in the sense that an item
that wins many matches gets credit for each one.

## Worked example

Four items, pairwise win counts:

| | A | B | C | D |
|---|---|---|---|---|
| **A** | — | 4 | 2 | 5 |
| **B** | 1 | — | 3 | 2 |
| **C** | 0 | 1 | — | 3 |
| **D** | 0 | 1 | 1 | — |

(Each cell $(i, j)$ = wins of row $i$ over column $j$.)

Borda scores:
- A: 4 + 2 + 5 = 11
- B: 1 + 3 + 2 = 6
- C: 0 + 1 + 3 = 4
- D: 0 + 1 + 1 = 2

Ranking: A (11) > B (6) > C (4) > D (2).

The ranking respects wins directly. Notice that even though A only
won 2-0 against C (a narrow majority), every match A won counts.
This is the margin-sensitivity: 5 wins against D counts more than
2 wins against C.

## Borda vs Copeland

Compare this to Copeland's logic on the same data. Copeland would:

- A: wins vs B (4-1), vs C (2-0), vs D (5-0) = 3 wins, 0 losses. Copeland = +3.
- B: wins vs C (3-1), vs D (2-1), loses to A. Copeland = +1.
- C: wins vs D (3-1), loses to A and B. Copeland = −1.
- D: loses to A, B, C. Copeland = −3.

Copeland's ranking: A > B > C > D — same order in this case. But
Copeland's scores are integers based on majority head-to-heads
regardless of margin, while Borda's scores reflect the raw win
counts. On noisier data, the two can disagree.

For example, imagine B barely beats C (3-2 every time, 1000
matches) while everyone else has one or two matches. Copeland
sees B > C (majority) and A > C (majority) each as "one win",
weighted equally. Borda sees B's many tiny wins against C as
hundreds of points, while A's two wins as only two points. Borda
will rank B above A in this case; Copeland might not.

## Axiomatic properties (the honest version)

Borda **satisfies**:

- **Monotonicity**: raising an item's wins raises its score.
- **Cancellation**: adding a pair of reversed ballots is a no-op.
- **Reversal symmetry**: flipping all ballots flips the ranking.

Borda **fails**:

- **Condorcet winner criterion**: a Condorcet winner can be
  ranked below a non-Condorcet winner under Borda, if the non-
  Condorcet item accumulated more "total wins" despite losing
  head-to-head against the Condorcet winner.
- **Independence of clones**: adding an item that's essentially a
  copy of another splits the Borda support between them, dragging
  the original down. This is Borda's most famous weakness.

For `elo_engine`'s use case (preference ranking where you have no
reason to think of "clones"), the clone vulnerability is mostly
theoretical. For formal governance, consider Schulze or Ranked
Pairs instead.

## The "too many wins against weak opponents" issue

Borda can be gamed by stuffing an item's schedule with easy
opponents. If A plays and beats 50 very weak items once each,
and B plays and narrowly beats 3 strong items, Borda rewards A
with 50 points and B with 3. Is that right?

In a *fair* tournament where every item plays every other the
same number of times, Borda is a reasonable measure of "how many
wins did you accumulate". In a *skewed* tournament, it's not.

This is the core weakness of Borda: it assumes match density is
roughly uniform. For `elo_engine`, where `nextMatch()` tries to
balance pair coverage, Borda works well. For externally-supplied
match history, check the density before trusting Borda
rankings.

## When Borda is at its best

- **Small N, dense data.** Every pair has played several times.
  Borda's direct win-counting interpretation is clean and the
  clone problem doesn't arise.
- **Explanation priority.** "A item's score is the total number of
  matches it won" is the easiest explanation in the ensemble.
- **Cross-check for ELO.** Borda is model-free; it does not
  assume a latent skill. When it agrees with ELO, you have
  confidence in the ranking. When it disagrees, the data has
  anomalous match density or unusual distribution.

## When Borda is not the right choice

- **Cycles matter.** Borda will cheerfully rank cyclic data, but
  it is ignoring the non-transitivity. Use Schulze or HodgeRank
  instead.
- **Strategic voting.** If users can *choose* which items to
  compare, Borda is vulnerable to schedule-stuffing.
- **Sparse data.** Borda weights each observed win equally, so an
  item with few matches gets a low score regardless of quality.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when `AlgorithmId.borda` is
  enabled.
- Exposed as `RankingComparison.bordaRanking`, sorted descending by
  total wins (ties half).
- Cost is $O(N^2)$, a single sweep of the pairwise matrix.

## One-sentence summary

Borda is "count total wins (half for ties) and sort", the 1770
voting method that's still the simplest margin-sensitive ranking
you can run.

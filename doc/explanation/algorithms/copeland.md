# Copeland

## TL;DR — when to pick it

Enable Copeland when you want the **simplest possible Condorcet-style
ranking**: for each item, count the number of opponents it beats in
a head-to-head majority, subtract the number it loses, and sort by
the result. Copeland is cheap ($O(N^2)$), has no tunable parameters,
passes the Condorcet winner criterion (if there is an item that
beats every other in pairwise majority, Copeland ranks it first),
and produces outputs most users can audit by hand. It is the
baseline against which every other voting-theoretic algorithm in the
ensemble is measured.

## The core idea, in one sentence

Count, for each item, the number of pairwise head-to-head matchups
it wins on majority, minus the number it loses. Sort descending.
That's it.

More formally: define the head-to-head relation $A \succ B$ to mean
"A beat B more often than B beat A over all observed matches". Then
Copeland's score for $A$ is

$$ \text{Copeland}(A) = |\{B : A \succ B\}| - |\{B : B \succ A\}| $$

Ties in head-to-head (equal wins each way, or no matches at all)
contribute 0 to the score from that pair. Sort items by Copeland
score, descending.

## Worked example

Five items, with pairwise win counts already tallied:
- A beats B (4-2), A beats C (3-2), A beats D (5-1), A beats E (3-2)
- B beats C (3-1), B beats D (3-2), B loses to E (1-4)
- C beats D (2-1), C beats E (2-1)
- D beats E (3-2)

Head-to-head majorities:
- A: wins against B, C, D, E (4 wins, 0 losses) → Copeland = +4
- B: wins against C, D; loses to A, E → +2 − 2 = 0
- C: wins against D, E; loses to A, B → 0
- D: wins against E; loses to A, B, C → −2
- E: wins against B; loses to A, C, D → −2

Final Copeland ranking: A > B = C > D = E.

Note the ties. Copeland is blunt — it treats all head-to-head wins
equally and all losses equally. A decisive 10-0 sweep counts the
same as a 6-5 squeaker. This is both its strength (simplicity,
transparency) and its weakness (it discards information).

## What Copeland gets right

**Condorcet winner criterion.** If some item beats every other item
in pairwise majority, Copeland gives it the highest score (it wins
every head-to-head and loses none). This is the classical "Condorcet
criterion" in social choice theory, and it's what distinguishes
Condorcet methods (Copeland, Schulze, Ranked Pairs) from
plurality-style methods (Borda, Instant Runoff).

**Monotonicity.** Ranking an item higher cannot hurt it in
Copeland. If you change a few matches to make A win more, A's score
goes up or stays the same — never down.

**Simplicity.** You can explain Copeland to a non-technical user in
one sentence. "Count wins minus losses in head-to-head matchups."
This is the most defensible algorithm in the ensemble when the
explanation matters more than the precision.

**Monotonic robustness.** Small perturbations in the data move
Copeland scores smoothly. No phase transitions, no "suddenly the
leader changes because one match flipped". Scores are integers;
changes are discrete but local.

## What Copeland gets wrong

**Information loss.** A 4-0 sweep and a 3-2 edge both count as
"one head-to-head win". Copeland cannot tell a dominant item from a
marginally-winning one. This is the main reason Borda or Bradley-
Terry are often preferred when you have enough match data — they
use the magnitude of the wins.

**Ties are very common with few items.** For small N, many pairs
end up tied in Copeland score. With N=5, about half of real data
sets have some tied Copeland scores. You have to break ties some
other way (in `elo_engine`, we fall back to item ID order
deterministically) or accept ambiguity.

**Sensitivity to missing matches.** If two items have never played
each other, they contribute 0 to each other's score — just like a
tie. This is fine if every pair has played, and wrong if some pairs
haven't. For sparse data, Copeland's output is biased toward items
that happened to be in many comparisons.

## The relation to Schulze and Ranked Pairs

All three methods (Copeland, Schulze, Ranked Pairs) start from the
same pairwise majority comparison. They differ in what they do with
cycles:

- **Copeland** ignores cycles entirely. It just counts wins and
  losses, so a 3-way cycle contributes 0 to each item's score.
- **Schulze** finds the **strongest path** from each item to each
  other and uses those beatpath widths to break cycles.
- **Ranked Pairs** sorts all pairwise matches by margin size and
  locks them in, skipping any that would create a cycle.

On fully transitive data, all three agree. On cyclic data, they can
disagree — sometimes by a lot. Enabling all three in the ensemble is
a reasonable robustness check.

## The Condorcet winner, spotted

If `RankingComparison.copelandRanking.first` has a Copeland score of
$N - 1$ (maximum possible), it is a **Condorcet winner** —
it beat every other item in pairwise majority. Such items are rare
in practice but meaningful when they appear. If you want to detect
a Condorcet winner specifically, compare the top-ranked
Copeland item's score (not exposed as a public API yet in
`elo_engine`, but easy to compute externally) against $N - 1$.

## Failure modes

**Too many ties.** With sparse data, most items have similar
Copeland scores. The ranking is barely distinguishable from
alphabetical.

**Cyclic majority.** If A > B > C > A in pairwise majority,
Copeland scores them all 0. The ranking is arbitrary. HodgeRank or
SerialRank will tell you this is what happened.

**Dominated items.** An item that loses every match gets
Copeland = $-(N-1)$. An item that wins every match gets $+(N-1)$.
These boundary values are meaningful, but in between, small score
differences don't reflect much information.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when `AlgorithmId.copeland`
  is enabled.
- Exposed as `RankingComparison.copelandRanking`, sorted descending
  by score. Ties broken by input order (deterministic).
- Cost is $O(N^2)$ — one pass over the pairwise matrix. This is
  the cheapest non-ELO batch algorithm in the ensemble.

## One-sentence summary

Copeland is "count wins minus losses in head-to-head majority
matchups and sort": the simplest Condorcet-compliant method and the
baseline voting-theoretic algorithm in the ensemble.

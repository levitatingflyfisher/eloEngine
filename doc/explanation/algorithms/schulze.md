# Schulze

## TL;DR — when to pick it

Enable Schulze when you want a **voting-theory-grade** ranking that
handles cycles gracefully and has been adopted by real-world
organizations (Debian, the Wikimedia Foundation, Software in the
Public Interest) specifically because its fairness properties are
well-studied. Schulze satisfies more voting-theory axioms than any
other algorithm in the ensemble — Condorcet winner, Condorcet loser,
monotonicity, independence of clones, reversal symmetry. Use it
when your ranking will be defended in a meeting and "we used Schulze,
which is what Debian uses for its DPL elections" is an acceptable
argument.

## The core idea: beatpaths

Copeland and Borda look at pairwise matches directly. Schulze does
something cleverer: it looks at **chains of pairwise matches**.

Intuition: maybe A didn't directly beat B, but A beat C decisively
and C beat B decisively. That's a "path" from A to B through C,
and the **strength** of the path is the weakest link in the chain —
the smallest margin along the way.

Schulze's algorithm:

1. For every ordered pair $(i, j)$, compute the margin $d_{ij}$
   = wins of $i$ over $j$ minus wins of $j$ over $i$.
2. For every pair, find the **widest** path from $i$ to $j$ — the
   maximum over all possible paths of the minimum margin along each
   path. This is the **beatpath strength** $p_{ij}$.
3. Say $i$ beats $j$ in the Schulze sense if $p_{ij} > p_{ji}$.
4. Rank items by the number of beatpath wins, descending. (Or use
   a stable topological sort of the beatpath relation.)

The beatpath widths are computed with a variant of the Floyd-Warshall
all-pairs-shortest-paths algorithm — the "widest path" variant,
where min replaces plus and max replaces min. Cost: $O(N^3)$.

## Worked example

Three items, A, B, C. Pairwise margins:
- A beats B by margin 3 (direct edge $A \to B$ with strength 3).
- B beats C by margin 5 (direct edge $B \to C$ with strength 5).
- C beats A by margin 1 (direct edge $C \to A$ with strength 1).

This is a cycle. What is each pair's beatpath strength?

- $A \to B$: direct path (margin 3) or through C ($A \to C$? But C
  beats A, not A beats C. Need to go $A \to B \to C \to A$? No,
  that's a loop). Best $A \to B$ = direct, strength 3.
- $A \to C$: direct is missing (C beats A, not the other way). Go
  $A \to B \to C$, with strength $\min(3, 5) = 3$. So $p_{AC} = 3$.
- $B \to A$: $B \to C \to A$ with strength $\min(5, 1) = 1$.
- $B \to C$: direct, strength 5.
- $C \to A$: direct, strength 1. Longer path $C \to A \to B$?
  First step $C \to A$ margin 1. Going through $B$: $C \to ?$, no
  direct $C \to B$. So $p_{CA} = 1$.
- $C \to B$: no direct, $C \to A \to B$ with $\min(1, 3) = 1$.
  So $p_{CB} = 1$.

Beatpath winners (strict majority):
- A vs B: $p_{AB} = 3, p_{BA} = 1$. A beats B in Schulze.
- A vs C: $p_{AC} = 3, p_{CA} = 1$. A beats C in Schulze.
- B vs C: $p_{BC} = 5, p_{CB} = 1$. B beats C in Schulze.

Schulze ranking: A > B > C.

Notice what happened. The raw pairwise data was a cycle — no item
beats every other directly. But when you look at beatpaths, A's
path to C through B is stronger (width 3) than C's direct edge to
A (width 1). Schulze interprets this as "A's beatpath-based
advantage is larger" and ranks accordingly.

This is the key insight: **margin sizes carry information that
pure head-to-head counts discard**. A 5-point margin means more than
a 1-point margin, and Schulze uses those magnitudes to break
cycles in favor of the stronger-margin-preserving ordering.

## Why it has so many nice axiomatic properties

Schulze satisfies:

- **Condorcet winner criterion.** If a Condorcet winner exists,
  Schulze picks it first.
- **Condorcet loser criterion.** A Condorcet loser (an item that
  loses every head-to-head) is ranked last.
- **Monotonicity.** Changing ballots in favor of an item cannot
  decrease its Schulze rank.
- **Independence of clones.** If you add a clone of an existing
  item (an item with identical preferences), neither the original
  nor the clone gets a disproportionate advantage. Borda badly
  fails this; Schulze passes.
- **Reversal symmetry.** If you reverse all ballots, Schulze's
  top item becomes the last item and vice versa.

These are not accidents. Schulze's designer, Markus Schulze,
published the method in 1997 explicitly as an axiom-driven
construction — he picked the algorithm that satisfies the most
classical fairness properties simultaneously.

The price is complexity. Schulze's $O(N^3)$ cost is more expensive
than Copeland's $O(N^2)$, and the beatpath computation is harder
to explain to laypeople. "We pick the winner based on the widest
chain of pairwise wins" is not an easy sell compared to "count
wins minus losses".

## Comparison to Ranked Pairs

Schulze and Ranked Pairs are the two most-studied Condorcet methods.
They usually agree but can differ:

- **Schulze** builds up beatpaths via all-pairs widest paths, then
  derives a ranking from the beatpath relation.
- **Ranked Pairs** sorts all pairwise match results by margin and
  commits them one at a time, rejecting any that would create a
  cycle with already-committed results.

Both handle cycles with margin-sensitivity. In practice:
- Schulze is slightly smoother — small changes in the data produce
  small changes in the output.
- Ranked Pairs is slightly more interpretable — you can explain it
  as "lock in the biggest wins first".

Enable both for a cross-check. When they agree, your cyclic data
has a clear direction-of-force. When they disagree, the cycles
matter a lot.

## Failure modes

**Ties everywhere.** Schulze can produce tied beatpaths for
multiple items when the data is symmetric. `elo_engine` breaks ties
by input order deterministically, but the ranking in that region is
arbitrary.

**Very sparse data.** Beatpaths require paths to exist. If items
are disconnected in the match graph, there is no beatpath between
them and the algorithm falls back on arbitrary choices. Make sure
your match graph is connected before trusting Schulze output.

**Performance on large N.** $O(N^3)$ starts to hurt at N=500 and
becomes noticeable at N=1000. For `elo_engine`'s typical consumer-
app sizes (tens to a few hundred), this is fine.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when `AlgorithmId.schulze`
  is enabled.
- Exposed as `RankingComparison.schulzeRanking`.
- Uses the Floyd-Warshall widest-path variant over margins, then
  derives a strict beatpath relation, then does a topological sort.
- Cost is $O(N^3)$. At N=200 this is a few milliseconds.

## One-sentence summary

Schulze is "find the widest chain of pairwise wins from each item
to each other, and rank by who has more dominant chains" — the
voting theory workhorse that Debian uses, and the algorithm with
the best axiomatic pedigree in the ensemble.

# SerialRank

## TL;DR — when to pick it

Enable SerialRank when you want to know whether your items **can
even be put in a linear order** — and, if yes, what that order is.
SerialRank is a **seriation** algorithm: it finds the single best
ordering of items such that preferences decay smoothly with
distance along the order. It gives you a ranking *and* a
"rankability" score in $[0, 1]$ — low score means no 1-D ordering
fits the data well. Pair it with HodgeRank for a two-sided check on
whether your users' preferences are genuinely 1-dimensional.

## The problem: is a ranking meaningful?

Most of the algorithms in this package **assume** your data is
rankable and produce a ranking regardless. SerialRank and HodgeRank
are the only two that push back and ask: "hold on — does it even
make sense to put these items on a line?"

Here's an example where a ranking doesn't fit:

Five pizza toppings, voted on by two groups. Group 1: meat-lovers,
who rank pepperoni > sausage > mushrooms > olives > peppers. Group
2: vegetarians, who rank mushrooms > olives > peppers > sausage >
pepperoni. Combine the two groups' pairwise preferences: you get a
mess where pepperoni beats sausage, sausage beats mushrooms,
mushrooms beat olives, olives beat peppers, and peppers beat
pepperoni — a cycle.

If you try to force this onto a single ranking, you'll get
something like "sausage ≈ mushrooms ≈ olives, tied, with pepperoni
and peppers at the ends". That ranking is misleading: the real
structure is **two 1-D rankings**, not one. SerialRank detects this
and reports a low rankability score.

## The seriation view

Seriation is an old archaeology problem: given a pile of artifacts
and partial information about which ones are "similar" (same
period, same culture), can you put them in chronological order?
The answer reduces to a matrix-reordering problem — find a
permutation of the rows and columns that clusters the similarity
values near the diagonal.

For paired comparisons, the "similarity" becomes "win rate" on an
anti-symmetric scale: $C_{ij} \in [-1, 1]$ where positive means
$i$ beats $j$ more than half the time, $C_{ii} = 0$, and $C_{ij}
= -C_{ji}$. SerialRank asks: can we reorder the rows/columns of
$C$ so that large positive values cluster in the upper-right,
large negatives in the lower-left, and the values decrease smoothly
as you move away from the diagonal?

That decay-with-distance property is what a 1-D ranking **is**, in
matrix language.

## The spectral trick

The brilliant move in SerialRank (Fogel, d'Aspremont, Vojnovic
2014) is that this ordering can be read off a **single
eigenvector** of a related matrix. Specifically:

1. Construct $C$, the comparison matrix.
2. Compute $S = C C^T$, which measures how "similarly" each pair
   of items compares to the rest.
3. Take the eigenvector corresponding to the **second-smallest**
   eigenvalue of the graph Laplacian associated with $S$ — this
   is the "Fiedler vector", the same one used in spectral graph
   clustering.
4. Sort items by the value of this eigenvector. That's your
   ranking.

Why does this work? The Fiedler vector is the direction along
which the graph has the smoothest variation — it's the closest
thing the graph has to a "1-D coordinate". If the data is really
1-dimensional, the Fiedler vector will recover that dimension
exactly. If the data is 2-D or noisy, the Fiedler vector gives the
best 1-D projection, and the next eigenvector captures the second
dimension.

## The rankability score

SerialRank outputs a single number in $[0, 1]$ called
`rankability`. It is derived from the **eigengap** — the difference
between the second-smallest and third-smallest Laplacian
eigenvalues. A large gap means the 1-D structure dominates the
data; a small gap means the second and third dimensions are almost
as important, i.e., your data is multi-dimensional.

The `rankability` in `elo_engine` is the Fiedler eigenvalue rescaled
to $[0, 1]$ so that:
- Near 1.0: a 1-D ordering fits very well.
- Near 0.5: moderately rankable.
- Near 0.0: the data resists linear ordering.

Use this as a sanity check. If your user interface shows a ranking
but `rankability < 0.3`, you should display a warning — the
ranking is partially fictional.

## Worked example

Four items, perfectly linear preferences: A > B > C > D, each pair
with a clean 2-0 or 3-0 win record.

The comparison matrix $C$ has positive values on the upper
triangle, negatives on the lower triangle, and the magnitudes
decrease as you move away from the diagonal. The similarity
$C C^T$ is a banded matrix. The Fiedler vector recovers the
order (A, B, C, D) and the rankability is near 1.0.

Now add noise: swap two results so B occasionally beats A and C
occasionally beats B. The Fiedler vector still recovers the correct
order (the signal dominates), and rankability drops to maybe 0.85.

Now replace the data with rock-paper-scissors-lizard-spock: five
items in a cyclic preference loop. The comparison matrix has no
sortable structure. The Fiedler vector is essentially random, and
rankability drops below 0.3. The algorithm is telling you: "don't
trust my output, there is no good ranking here".

## When SerialRank disagrees with HodgeRank

The two algorithms measure similar things from different angles:

- **HodgeRank** tells you the magnitude of the cyclic flow around
  triangles, relative to the gradient flow. It operates on edges.
- **SerialRank** tells you the eigengap of the comparison matrix.
  It operates on the whole matrix.

In practice they usually agree: both spot cyclic data and both say
so. When they disagree, it's usually because SerialRank is more
sensitive to dense multi-cluster structure (many items, few
triangles) while HodgeRank is more sensitive to sparse triangle
cycles.

Enable both and trust the one with the bigger warning. If SerialRank
says "rankability 0.2" and HodgeRank says "cyclic is small, gradient
is fine", your data probably has two clusters that each rank
internally but conflict with each other — a 2-D structure, not a
cycle.

## Failure modes

**Disconnected components.** The Fiedler vector on a disconnected
graph is degenerate — it becomes the indicator vector for the
smallest component. `elo_engine` guards against pathological
disconnection with ridge regularization on the Laplacian, but
rankability between truly-disconnected clusters is meaningless.

**Very small N.** With only 2 items, there's nothing to seriate.
`elo_engine` short-circuits: for N=2 it uses the direct pairwise
winner and sets rankability to 1 (or 0 if they tied).

**Noisy ties.** If many items have roughly 50/50 win rates against
each other, the comparison matrix is close to zero and the Fiedler
vector is dominated by noise. The rankability will be low for a
reason — the data is noisy, not cyclic — but SerialRank cannot
distinguish the two.

## Connections

- **HodgeRank** is the direct cousin — both measure non-rankability.
- **Matrix factorization** reveals latent dimensions when rankability
  is low; it tells you "here are two or three orthogonal preference
  axes" rather than just "there's no single axis".
- **Spectral clustering** uses the same Fiedler-vector trick to
  partition graphs, just for a different purpose.
- **Classical ELO** will happily produce a ranking even when
  SerialRank says the data is not rankable. This is fine if you
  need *an* answer, but know that ELO is being forced to lie.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when `AlgorithmId.serialRank`
  is enabled.
- Exposed as `RankingComparison.serialRank`, a `SerialRankResult`
  with:
  - `ranking` — the items sorted by their Fiedler vector values
    (this is the 1-D embedding).
  - `rankability` — a scalar in $[0, 1]$ indicating how well the
    1-D ordering fits the data.
- Uses direct eigendecomposition on a small Laplacian (N×N) via
  power iteration with deflation. Cost is $O(N^3)$ in the worst
  case.

## One-sentence summary

SerialRank is seriation as ranking: find the single Fiedler
eigenvector that best embeds your comparison matrix on a line, and
report both the resulting order and how well the line actually
fits.

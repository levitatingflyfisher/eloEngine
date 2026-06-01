# SpringRank

## TL;DR — when to pick it

Enable SpringRank when your domain is **hierarchical** — dominance
relationships, prestige orderings, organizational rank — and you
want an algorithm that explicitly models the "higher beats lower"
structure. SpringRank was published by De Bacco, Larremore, and Moore
(2018) as a method for recovering hierarchies in social networks
(faculty hiring, animal dominance, Twitter mentions), and it handles
some things ELO does poorly: asymmetric hierarchies where strong
items beat weak items *very* consistently, and situations where you
want a ranking that minimizes "upsets" in a physical sense.

## The physics analogy

SpringRank models each item as a **bead on a number line** and each
match as a **spring** connecting the two beads involved. Here is the
key move: the spring has a **natural resting length of 1**, but with
a direction. If A beats B, the spring pulls A to be "one unit above"
B on the line. The natural length is signed: the spring wants A at
position $s_A = s_B + 1$.

Given N items and many matches, you get a tangled mess of springs,
each one pulling in its preferred direction. Find the positions
$s_1, \ldots, s_N$ that minimize the total spring energy:

$$ H(s) = \frac{1}{2} \sum_{(i, j) \in \text{matches}} (s_i - s_j - 1)^2 $$

where the sum is over all directed match edges (if A beat B three
times, that's three edges in the sum). Take a derivative, set to
zero, solve the linear system. Sort items by $s_i$. Done.

SpringRank is literally a least-squares problem. The "physics" is a
visualization hook — the math is just linear regression on a
carefully constructed matrix. This is why it is fast ($O(N^3)$ via
direct solve) and why it has a closed form rather than iterative
fitting.

## Why the natural length of 1?

You could pick any constant. The number 1 is a scale choice — the
"gap between rank $i$ and rank $i+1$" is normalized to one unit,
and the resulting positions land in a comparable range regardless of
match count. If you want wider rank gaps, multiply $s$ by any
constant after the fact.

The *signed* direction is the crucial part. A symmetric spring
model (no direction, spring just wants "some distance") would not
recover a ranking — it would just spread items out. The signed
version says "A beat B" means "A is higher than B by one unit", and
the least-squares fit finds the arrangement that honors as many of
those signed constraints as possible.

## Worked example

Four items, matches:
- A beats B (once)
- A beats C (once)
- B beats C (twice)
- B beats D (once)
- C beats D (once)

The energy function has five terms, one per match (counted with
multiplicity). Taking the gradient with respect to each $s_i$ and
setting to zero gives a linear system:

- $\partial H / \partial s_A = (s_A - s_B - 1) + (s_A - s_C - 1) = 0$
- $\partial H / \partial s_B = -(s_A - s_B - 1) + 2(s_B - s_C - 1) + (s_B - s_D - 1) = 0$
- $\partial H / \partial s_C = -(s_A - s_C - 1) - 2(s_B - s_C - 1) + (s_C - s_D - 1) = 0$
- $\partial H / \partial s_D = -(s_B - s_D - 1) - (s_C - s_D - 1) = 0$

This is a 4×4 linear system. The solution is not unique — adding a
constant to every $s_i$ gives the same energy — so we fix one item
(say $s_D = 0$). Solving: $s_A \approx 2.5, s_B \approx 1.5,
s_C \approx 0.8, s_D = 0$. Sort: A, B, C, D. Which matches the
intuition (A won all its matches, D lost all its matches).

## What SpringRank reveals that ELO hides

Consider a setting where the win graph has two clean levels: five
"top" items that always beat five "bottom" items, and within each
level they split roughly 50/50.

- **ELO** will rank the top five correctly as above the bottom five,
  but within each level, ratings will wander based on match order
  and noise. It can't "see" the two-level structure.
- **SpringRank** will place the top five near position 1 and the
  bottom five near position 0 (after normalization), naturally
  capturing the two-cluster hierarchy. Items within each cluster
  will be clumped, and the cluster gap will be clear.

This is what hierarchical means in practice: the algorithm preserves
**level structure**, not just pairwise order.

## Handling cycles

Pure intransitive data (A beats B, B beats C, C beats A, 1-1 each)
has no consistent 1-D order. What does SpringRank do?

It **fails gracefully**. The least-squares solver finds the
arrangement that minimizes total spring energy even though no
arrangement satisfies all the springs. For a perfect cycle, it
returns positions very close together (the data has no signal
beyond noise). For a partial cycle embedded in otherwise-hierarchical
data, it absorbs the cycle as error and gives you the closest-fit
ranking anyway.

`RankingComparison` does not expose a "how much spring energy
remained" metric, but HodgeRank (see
[`hodge.md`](hodge.md)) does measure the cyclic component directly.
Pairing SpringRank with HodgeRank gives you both "here's the best
linear fit" and "how non-linear is your data".

## The link to other methods

SpringRank turns out to be **equivalent to a special case of
Bradley-Terry with Gaussian noise** — it's the same latent-strength
idea, but with a squared loss instead of a logistic loss. Squared
loss is easier to optimize (closed form!) but less tolerant of
extreme wins. In practice, SpringRank gives slightly "flatter"
hierarchies than Bradley-Terry.

It is also equivalent to solving a **random walk Laplacian** on the
signed win graph, which is why it shares DNA with PageRank and the
Markov chain method. The common thread: represent the matches as a
graph, do linear algebra on that graph, read off the ranking.

## Failure modes

**Disconnected items.** If item A has never played any opponent of
item B (even transitively), their relative positions in the
spring system are undefined. The solver needs a connected graph to
produce a unique ranking. `elo_engine` handles this with ridge
regularization: add a small identity term to the Laplacian so the
matrix is invertible even if the graph is disconnected. The
resulting ranks for disconnected clusters are arbitrary relative to
each other, but ranks *within* each cluster are still meaningful.

**Many identical matches.** If every item has played every other
exactly once with no repetitions, SpringRank is the most efficient
of all batch methods at recovering the implied order. This is the
best case.

**Sparse outliers.** A single crazy win-against-all item will get a
very high $s$, which pulls neighboring items slightly. The
$L_2$ loss is not as robust as, say, median-based methods. If your
data has occasional weird results, consider Copeland or Schulze as a
robustness check.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when
  `AlgorithmId.springRank` is enabled.
- Exposed as `RankingComparison.springRankRanking`, sorted descending
  by the fitted $s_i$.
- Uses direct matrix solve on a ridge-regularized Laplacian system.
  Cost is $O(N^3)$ — the most expensive batch algorithm in the
  ensemble after matrix factorization.
- The $s$ values are not surfaced as a public API; only the sorted
  order is. If you need the raw positions for a custom visualization,
  you'll have to add an accessor.

## One-sentence summary

SpringRank is least-squares on a graph where each match is a spring
that wants A one unit above B — the closed-form hierarchical ranking
that drops out of a linear system.

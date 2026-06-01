# Markov

## TL;DR — when to pick it

Enable Markov when you want **PageRank's cousin** — a stationary
distribution over the win graph — without PageRank's damping-factor
arbitrariness. The two algorithms answer the same question ("how
often would a random walker visit each item?") but regularize the
answer slightly differently. Markov is the textbook approach: treat
the normalized win matrix as a transition kernel and find its
leading eigenvector. Use it alongside PageRank for a second
opinion; the two rankings usually agree closely, and when they
disagree it's often informative about your graph's structure.

## The core idea

Build a square matrix $M$ where $M_{ij}$ is the probability that,
if you are currently thinking about item $i$, your next thought is
item $j$. In the `elo_engine` construction:

$$ M_{ij} = \frac{w_{ij}}{\sum_k w_{ik}} $$

where $w_{ij}$ is the number of times $j$ beat $i$. In words:
"starting from $i$, jump to the item that beat me, proportional to
how many times they beat me".

This matrix is **row-stochastic**: each row sums to 1 (as long as
$i$ has at least one loss). A Markov chain whose transitions are
$M$ has a **stationary distribution** $\pi$ satisfying $\pi M =
\pi$ — the row vector $\pi$ that stays the same when you apply
one step of the chain.

$\pi_i$ is the long-run probability that a walker wandering by this
rule ends up sitting on item $i$. Items with high $\pi$ are items
that frequently win against items that are themselves strong.

This is the same intuition as PageRank. The math is literally the
same idea. The difference is in how edge cases (rows that don't
sum to 1 because the item has never lost) are handled.

## How to find the stationary distribution

Two approaches, both implemented variants of the same thing:

1. **Power iteration.** Start with $\pi = (1/N, 1/N, \ldots, 1/N)$.
   Repeatedly compute $\pi \leftarrow \pi M$. After a few dozen
   iterations, $\pi$ stops changing. That's your answer.

2. **Eigenvector decomposition.** The stationary distribution is the
   left eigenvector of $M$ with eigenvalue 1. Compute it directly.

Power iteration is simpler and works well; `elo_engine` uses it.

## Worked example

Three items, matches:
- A beat B (once)
- B beat C (twice)
- C beat A (once)

Win counts ($w_{ij}$ = times $j$ beat $i$):
- $w_{AB} = 0$, $w_{AC} = 1$ (C beat A once)
- $w_{BA} = 1$ (A beat B once), $w_{BC} = 0$
- $w_{CA} = 0$, $w_{CB} = 2$ (B beat C twice)

Normalize by row:
- Row A: $[0, 0, 1]$ (100% of A's losses are to C)
- Row B: $[1, 0, 0]$ (100% of B's losses are to A)
- Row C: $[0, 1, 0]$ (100% of C's losses are to B)

So M is:
```
     A   B   C
A [ 0   0   1 ]
B [ 1   0   0 ]
C [ 0   1   0 ]
```

Start $\pi = (1/3, 1/3, 1/3)$.

Iterate $\pi \leftarrow \pi M$:
- Step 1: $\pi_A = 1/3 \cdot 1 = 1/3$; $\pi_B = 1/3 \cdot 1 = 1/3$;
  $\pi_C = 1/3 \cdot 1 = 1/3$. Same distribution — this is a
  rock-paper-scissors cycle and it's already stationary.

The three items tie. Which is the correct answer for a perfect
3-way cycle. Markov saw the symmetry and refused to break it.

## When Markov diverges from PageRank

**Dangling rows.** If an item has no losses (an undefeated item),
its row in $M$ sums to 0 instead of 1 — it has nowhere to jump. The
power iteration leaks probability out of such rows and never puts
it back.

PageRank's solution: the damping-factor trick, teleporting to a
uniform random item. This is a clean, generic fix.

Markov's solution in `elo_engine`: add a small uniform "escape"
probability to every row (similar to damping) and re-normalize.
Conceptually equivalent, but the specific constant is different
from PageRank's 0.85, so the two algorithms produce slightly
different rankings on graphs with many dangling nodes.

**Multiple strongly-connected components.** If the match graph has
two clusters with no cross-matches, Markov's chain has two absorbing
subsets. The stationary distribution puts all probability in one of
them (arbitrarily). PageRank's uniform teleport bleeds probability
between the clusters so both get nonzero rank.

For well-connected match graphs (what most apps have), the two
algorithms agree within rounding error.

## What the stationary distribution really means

Here's the clean interpretation: imagine you start with 100
tokens uniformly distributed across items. At each step, each token
moves according to the row-probabilities of the matrix. After many
steps, the token distribution has settled into $\pi$, where
items that "pull in" probability mass are high-ranked and items
that "leak out" are low-ranked.

Another framing: $\pi_i$ is the long-run fraction of time a random
walker (who always moves *toward* the item that beat them) would
spend thinking about item $i$. That walker, in the long run, spends
most time thinking about items that frequently beat other winners.

## Connections

- **PageRank** is Markov with Google's specific damping. Same
  algorithm, different regularization.
- **Bradley-Terry** and **Thurstone** are latent-strength models;
  Markov does not assume a latent strength.
- **SpringRank** is linear algebra on the signed graph; Markov is
  linear algebra on the win-transition matrix. Different matrices,
  similar flavor.
- **Perron-Frobenius theorem** is the mathematical reason Markov
  works: any non-negative matrix with a connected underlying graph
  has a unique largest real eigenvalue with a non-negative
  eigenvector, and for row-stochastic matrices that eigenvalue is 1
  and the eigenvector is the stationary distribution.

## Failure modes

**Undefeated items and absorbing sinks.** As above — the algorithm
needs damping or similar regularization to behave. `elo_engine`
handles this, but if you're implementing from scratch, expect weird
results without it.

**Small sample sizes.** The transition matrix is noisy when each
row has only a handful of entries. For N=20 items with 5 matches
each, the stationary distribution is basically "who won their few
matches" — not much signal. Markov, like all eigenvector methods,
needs some match density to produce stable rankings.

**Periodicity.** A chain like A → B → C → A (deterministic, with no
teleport) is technically periodic — the iteration never converges
to a single distribution but cycles through $(1, 0, 0)$,
$(0, 1, 0)$, $(0, 0, 1)$. Uniform damping kills periodicity, which
is part of why both PageRank and Markov use it.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when `AlgorithmId.markov` is
  enabled.
- Exposed as `RankingComparison.markovRanking`, sorted descending by
  stationary probability.
- Uses power iteration on the normalized win matrix with uniform
  escape regularization, fixed iteration budget.
- Cost is $O(N^2 \cdot I)$.

## One-sentence summary

Markov is the stationary distribution of a random walk on the win
graph — PageRank's cousin, textbook form, with slightly different
handling of dangling nodes.

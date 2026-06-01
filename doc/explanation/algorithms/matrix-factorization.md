# Matrix Factorization

## TL;DR — when to pick it

Enable matrix factorization when you want to ask "**how many
dimensions** of preference are hidden in my data?" — and, for each
dimension, "which items are the poles". All the other algorithms in
the ensemble try to collapse the data onto a single axis. Matrix
factorization asks: *should I be collapsing at all*? If your users
have complex, multi-dimensional tastes (some prefer red over blue
**and** small over big, while others prefer the opposite), matrix
factorization will surface that structure in a way ELO, Bradley-
Terry, and the voting methods cannot. Use it for exploratory
analysis, for data where you suspect multiple preference axes, and
for second-opinion rankings that might flag "this ranking is
oversimplifying the data".

## The core idea

Build a pairwise-comparison matrix $P$ of size $N \times N$
where $P_{ij}$ is some measure of "how much $i$ is preferred to
$j$". A standard choice:

$$ P_{ij} = \frac{w_{ij}}{w_{ij} + w_{ji}} - 0.5 $$

This is the centered win rate: positive if $i$ usually beats
$j$, negative if the reverse, zero if they're even. Missing cells
(pairs with no matches) are filled with 0.

Now try to write $P$ as a **product of two smaller matrices**:

$$ P \approx U V^T $$

where $U$ is $N \times k$ and $V$ is $N \times k$ for some small
$k$ (the "rank" of the approximation). Each row $u_i$ of $U$ is a
$k$-dimensional embedding of item $i$ as an "attacker" — its
strength along each of $k$ latent axes. Each row $v_j$ of $V$ is
an embedding of $j$ as a "defender".

The prediction that $i$ beats $j$ is the inner product $u_i \cdot
v_j$, and the approximation fits the observed $P_{ij}$. For skew-
symmetric $P$ (which paired comparisons naturally give), you can
further constrain $V = -U$, reducing the problem to finding a
single $N \times k$ matrix $U$.

## Why this reveals dimensions

A rank-1 approximation says: "there is a single latent skill axis,
and each item has a single skill value". This is exactly the ELO
/ Bradley-Terry assumption.

A rank-2 approximation says: "there are two latent preference axes,
and each item has two coordinates". This can represent:
- Red vs blue
- Small vs big

And now item A (red, small) beats item B (blue, big) when the
chooser values redness more than bigness, but loses when the
chooser values bigness more than redness. A single axis cannot
represent this; two axes can.

Higher ranks can represent more complex tastes. The question is:
**what is the smallest rank that fits your data well?**

That's what matrix factorization in `elo_engine` computes. It tries
rank 1, rank 2, ..., up to a small cap (5 by default), and picks
the smallest rank whose approximation explains enough of the
observed variance.

## Worked example

Imagine four items: red-small (A), red-big (B), blue-small (C),
blue-big (D).

Two groups of choosers:
- Group 1 prefers red: rankings go A ≈ B > C ≈ D.
- Group 2 prefers small: rankings go A ≈ C > B ≈ D.

Pairwise match outcomes across both groups:
- A beats B: half the time (same color, different size; splits on
  size preference). Win rate ≈ 0.5, centered = 0.
- A beats C: depends on group weights; let's say 0.6 (red
  preference slightly dominant). Centered = 0.1.
- A beats D: both groups agree — red-small beats blue-big. Win
  rate ≈ 0.8. Centered = 0.3.
- B beats C: both groups disagree with each other; ≈ 0.5.
  Centered = 0.
- B beats D: red preference wins, size preference disagrees. ≈ 0.55.
  Centered = 0.05.
- C beats D: small preference wins, red preference disagrees. ≈ 0.45.
  Centered = -0.05.

The centered pairwise matrix has structure that cannot be written
as $u_i - u_j$ for any single coordinate $u$. A rank-1 fit will
have residuals. A rank-2 fit, with coordinates $(\text{red},
\text{small})$, will fit perfectly: $u_A = (1, 1)$, $u_B = (1,
-1)$, $u_C = (-1, 1)$, $u_D = (-1, -1)$, and the predictions $u_i
- u_j$ match the data exactly.

Matrix factorization reports `bestRank = 2`, indicating that the
data has two preference dimensions. A single ranking would collapse
this structure — you'd get some compromise order like A > B ≈ C > D
that hides the 2-D nature.

## The consensus ranking

For consumers who still want a single output, matrix factorization
in `elo_engine` also produces a **consensus ranking**. It picks the
leading latent factor (the first column of $U$) and sorts items by
their coordinate along it. This is the "most important single axis"
in the fit — useful as a 1-D summary when you need one, but less
informative than looking at the full embedding.

## Explained variance

Along with `bestRank`, matrix factorization reports
`explainedVariance` — the fraction of the Frobenius norm of $P$
that the chosen rank-$k$ approximation captures. Values close to
1.0 mean the fit is essentially perfect; values near 0.5 mean half
the information is still unexplained noise.

Use this as a confidence metric:
- `explainedVariance > 0.9` and `bestRank == 1` → your data is
  strongly 1-dimensional. Trust any single ranking.
- `explainedVariance > 0.9` and `bestRank > 1` → your data is
  multi-dimensional and a single ranking is a lossy summary.
- `explainedVariance < 0.5` → the data is mostly noise or the
  rank cap was too low. Treat any ranking with skepticism.

## Failure modes

**Missing data is filled with zero.** This is a common choice but
not a neutral one. Zero means "50/50" in the centered scale, which
is not the same as "unknown". Items with few matches get pulled
toward the population mean — which is reasonable but biases the
rank-inference slightly.

**Expensive.** The SVD-based fit is $O(N^3)$ for each rank, and
`elo_engine` tries multiple ranks, so the cost is the most
expensive in the ensemble. For N=200, this is the algorithm most
responsible for the ~730ms full-ensemble benchmark time.

**Interpretation requires domain knowledge.** The algorithm tells
you the data has, say, 2 latent dimensions, but it cannot tell you
*what those dimensions mean*. "This axis separates red from blue"
is something you infer by looking at the item embeddings — the
algorithm just hands you numbers.

**Sparse data hides structure.** If you only have 5 matches per
item, the "data has 2 dimensions" conclusion is not reliable.
Matrix factorization needs ~10+ matches per item to say anything
stable about latent dimensionality.

## Connections

- **SerialRank** also uses spectral methods, but projects onto the
  single Fiedler eigenvector. Matrix factorization looks at the
  leading $k$ eigenvectors jointly.
- **HodgeRank** decomposes flows into gradient, curl, and harmonic.
  Matrix factorization decomposes the matrix into singular vectors.
  Different views of the same question: "what structure is in your
  preference data?"
- **PCA / SVD**: matrix factorization here is basically SVD with a
  rank selection heuristic. It's the oldest trick in exploratory
  data analysis.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when
  `AlgorithmId.matrixFactorization` is enabled.
- Exposed as `RankingComparison.matrixFactorization`, a
  `MatrixFactorizationResult` with:
  - `bestRank` (int, clamped to $[1, 5]$) — the smallest rank that
    explained enough variance.
  - `explainedVariance` (double in $[0, 1]$) — fraction of
    Frobenius norm captured by the rank-$k$ fit.
  - `consensusRanking` (`List<EloItem>`) — items sorted by the
    leading latent factor.
- Uses SVD-based fit with iterative rank search. The most expensive
  algorithm in the ensemble; disable it if performance matters and
  you don't need dimensionality analysis.

## One-sentence summary

Matrix factorization is SVD on your pairwise-comparison matrix,
with a rank search that tells you *how many dimensions* of
preference are hiding in your data — the only algorithm in the
ensemble that can say "a single ranking is an oversimplification".

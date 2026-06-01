# PageRank

## TL;DR — when to pick it

Enable PageRank when you want to rank based on **who endorses whom**,
where "endorse" is "lose to" in the `elo_engine` model. PageRank was
famously built for the web — a page's rank comes from the ranks of
pages that link to it — but its math works on any directed graph. In
the match setting, "A loses to B" is an endorsement: A is saying,
with their loss, "B is better than me". The item with the most
endorsements from items that are themselves heavily endorsed wins.
PageRank is especially good when you want to reward items that beat
**other strong items**, and when your match graph has some structure
(clusters, strong core, weak periphery).

## The core intuition

Imagine a random walker hopping around your win graph. At each step,
they are standing on some item; they look at all the items that
**beat** this one (so that the current item is an endorsement of
them), pick one uniformly at random, and jump there.

If they do this forever, some items will be visited more often than
others. The **stationary distribution** of this walk — the
probability of finding the walker at each item in the limit — is
PageRank.

Items visited often are items that receive many endorsements *and*
are endorsed by items that are themselves endorsed often. The recursion
is: "your rank is the sum of the ranks of the items pointing to
you". It has a fixed-point solution that you can find by iteration
or by a single eigenvector computation.

## Worked example

Three items: A, B, C.
- A loses to B (B endorsed by A)
- A loses to C (C endorsed by A)
- B loses to C (C endorsed by B)

The win graph, drawn with arrows "endorser → endorsee":

```
  A ──→ B
  │     │
  └──→ C ←┘
```

Start the walker at A. Step 1: it can jump to B or C with equal
probability (A's two endorsements). Say C. Step 2: C has no outgoing
endorsement arrows at all (C never lost), so the walker is stuck.
**Dangling nodes** are a PageRank classic problem.

Google's solution: **damping**. At each step, with probability
$(1 - d)$ (typically $d = 0.85$), the walker teleports to a
uniformly-random item. This prevents stuck walkers and also
guarantees convergence regardless of graph structure.

Rewriting: the PageRank $r_i$ of item $i$ is
$$ r_i = (1 - d) / N + d \sum_{j : j \to i} r_j / \text{out}(j) $$
where $\text{out}(j)$ is the number of outgoing endorsements from
$j$.

For the A→B, A→C, B→C example, iterating with $d=0.85$ and $N=3$,
you get roughly:
- $r_C \approx 0.545$ (endorsed by A and B, no outgoing)
- $r_B \approx 0.266$ (endorsed by A, endorses C)
- $r_A \approx 0.189$ (endorses two, endorsed by none)

C wins, as expected — it beat everything. B is second. A is last.

## What PageRank captures that other algorithms don't

**Quality of opposition matters.** Losing to a heavily-endorsed item
(a strong opponent) is less bad than losing to a weak one — because
when PageRank aggregates, losing to a strong opponent is an
"endorsement of a strong opponent" and that strength gets passed
through the iteration.

ELO has the same intuition baked in via the expected-score update,
but ELO's version is *local* — it only accounts for the immediate
opponent's rating. PageRank's recursion is **global** — an item's
rank depends on the entire reachable structure of the graph.

**Robust to graph structure.** PageRank degrades gracefully on
disconnected, asymmetric, or cyclic graphs. The damping factor
guarantees a unique stationary distribution, and the iterative power
method converges in a few dozen passes regardless of shape.

## The weighted version

Plain PageRank treats each outgoing edge equally: if A lost to B
once and to C five times, both get the same endorsement flow from A.
That throws away information. The **weighted** PageRank used in
`elo_engine` normalizes each item's outgoing endorsements by the
number of times they lost, then weights each edge:

$$ r_i = (1 - d) / N + d \sum_{j} \frac{w_{ji}}{\sum_k w_{jk}} r_j $$

where $w_{ji}$ is the number of times $j$ lost to $i$. This is the
Markov-chain transition probability from $j$ to $i$, weighted by how
strongly $j$ "endorses" each of its conquerors.

## PageRank vs Markov

The [Markov algorithm](markov.md) in `elo_engine` is very similar —
same transition-matrix idea, same power iteration. The difference:

- **PageRank** uses the dangling-node damping trick. It's robust to
  disconnected or sink-heavy graphs.
- **Markov** is the pure stationary distribution. It assumes the
  graph is ergodic or uses a slightly different regularization.

For most data they produce nearly identical rankings. Enabling both
gives you two independent power-method estimates, which is useful as
a sanity check.

## Failure modes

**Sink items (items that always win).** A pure Condorcet winner
that beats everyone and never loses has no outgoing edges at all.
Without damping, all PageRank flows into this item and stays there.
With damping, the teleport term forces the walker to eventually leak
out. The sink item gets a very high rank, as it should, but the
*absolute value* is inflated.

**Tiny clusters.** A disconnected cluster of two items that only
play each other gets its own tiny stationary distribution. PageRank
ranks within the cluster correctly but cannot compare across
clusters — and the damping teleport adds noise.

**The damping factor is arbitrary.** 0.85 is Google's historical
choice for web pages. There is no principled reason it is the right
number for your match data. Higher $d$ gives more weight to graph
structure and less to teleport; lower $d$ does the opposite. 0.85
is fine in practice but know that the ranking is somewhat sensitive
to this constant.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when
  `AlgorithmId.pageRank` is enabled.
- Uses weighted outgoing normalization based on loss counts, with
  damping $d = 0.85$ and a fixed iteration budget.
- Exposed as `RankingComparison.pageRankRanking`, sorted descending
  by stationary probability.
- Cost is $O(N^2 \cdot I)$ where $I$ is the iteration count. The
  matrix is dense (most items eventually have some weighted edge to
  most others) so there's no speedup from sparsity.

## One-sentence summary

PageRank is the random-walk stationary distribution over the
endorsement graph — you rank high when many strong items lost to
you.

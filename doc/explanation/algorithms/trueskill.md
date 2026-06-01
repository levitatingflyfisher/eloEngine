# TrueSkill

## TL;DR — when to pick it

Enable TrueSkill when you want Glicko-2-style uncertainty tracking,
but you also want the option to extend later to **team matches**,
**free-for-alls**, or **any multi-player outcome**. TrueSkill was
designed by Microsoft Research for Halo matchmaking, where "four
people on a team fought four others and these three individuals on
the winning side performed better than those two" is a single data
point. `elo_engine` only uses the 1v1 form today, so in practice
TrueSkill behaves very similarly to Glicko-2 — enable it as a
second-opinion score, or as a smoother alternative that uses
Gaussian belief propagation instead of Glicko's method-of-moments.

## The core idea

Like Glicko-2, TrueSkill represents each player as a **Gaussian belief
distribution** over their true skill, summarized by two numbers:

- $\mu$ — the mean of the belief.
- $\sigma$ — the standard deviation of the belief.

The difference from Glicko-2 is *how* the belief is updated.
Glickman's math is a Bayesian approximation with an explicit
volatility parameter. TrueSkill's math is full-on **factor graph
message passing**: you treat the match as a tiny graphical model,
pass beliefs around the nodes, and read the updated beliefs off the
player nodes when the messages stop changing. This is more elegant,
generalizes more easily to teams, and produces slightly smoother
updates on pathological data.

For 1v1 matches — which is what `elo_engine` uses — the difference is
mostly cosmetic. TrueSkill and Glicko-2 will usually agree. Which
means enabling TrueSkill gives you a *second independent estimate*
with the same shape, which is useful as a cross-check.

## The performance model

TrueSkill assumes each player has a true skill $s_i \sim
\mathcal{N}(\mu_i, \sigma_i^2)$, but on the day of the match, they
**perform** at a slightly different level:

$$ p_i \sim \mathcal{N}(s_i, \beta^2) $$

where $\beta$ is the **performance spread** — how much your
day-to-day performance wobbles around your true skill. TrueSkill
sets $\beta = \sigma_0 / 2$ by convention, so at default settings
$\beta = 25/6 \approx 4.17$.

Player A beats player B iff $p_A > p_B$. Given the ratings you've
seen so far, you can compute the probability of this event — and
then, when it happens, you update each player's belief *conditioned
on* the fact that their performances produced this outcome.

It's Bayes' rule applied carefully. The beauty is that when you apply
it to Gaussians, you get more Gaussians back, and the update has a
clean closed form.

## The Gaussian update, in plain English

Here's what TrueSkill's 1v1 update is actually computing:

1. Compute $c$, the combined spread: $c^2 = 2\beta^2 + \sigma_A^2 +
   \sigma_B^2$. This is how much total performance variance is
   swirling in this match.

2. Compute $t$, the predicted rating difference: $t = (\mu_A -
   \mu_B)/c$. Positive $t$ means A is expected to win; large
   positive means A is a heavy favorite.

3. Compute $v$ and $w$, two truncation correction factors. $v$
   captures "how far did the actual outcome sit in the tail of
   the predicted distribution"; $w$ captures "how strong is our
   information gain".

4. Update:
   - $\mu_A \mathrel{+}= \sigma_A^2 \cdot v / c$
   - $\mu_B \mathrel{-}= \sigma_B^2 \cdot v / c$
   - $\sigma_A^2 \mathrel{*}= (1 - \sigma_A^2 \cdot w / c^2)$
   - $\sigma_B^2 \mathrel{*}= (1 - \sigma_B^2 \cdot w / c^2)$

Notice the shape: **players with higher $\sigma^2$ move more**. If A
is uncertain and B is settled, A's $\mu$ jumps a lot and B's $\mu$
barely moves. This is the "heavy learns fast, stable moves slow"
behavior you want — same qualitative story as Glicko-2, derived from
different machinery.

## Worked example

Two players start at the TrueSkill defaults: $\mu = 25$, $\sigma =
25/3 \approx 8.33$. (TrueSkill's scale is its own thing; Microsoft
picked 25 as a convenient midpoint and everyone else copied it.)

Round 1: A beats B.

- $c^2 = 2 \cdot (25/6)^2 + (25/3)^2 + (25/3)^2 \approx 152.78$,
  so $c \approx 12.36$.
- $t = 0 / 12.36 = 0$ (even match predicted).
- Look up truncation corrections at $t = 0$: $v \approx 0.798$,
  $w \approx 0.637$.
- $\mu_A \mathrel{+}= (25/3)^2 \cdot 0.798 / 12.36 \approx 4.48$,
  so $\mu_A \approx 29.48$.
- $\sigma_A^2 \mathrel{*}= (1 - (25/3)^2 \cdot 0.637 / 152.78)
  \approx 0.711$, so $\sigma_A \approx 7.03$.

Compare this to plain ELO's +16: here, a single win moved $\mu$ by
about +4.5 on a scale where the spread is ~8, so the relative effect
size is similar. But critically, **$\sigma_A$ shrank** — we now know
more about A than we did.

## The conservative-score leaderboard

TrueSkill leaderboards do not display $\mu$. They display $\mu - 3\sigma$
— the **conservative skill estimate**. This is "the skill level we
are 99.7% confident this player exceeds".

Why? Because a player who has won 5 matches out of 5 might have
$\mu = 40$ but $\sigma = 6$, meaning "we think they're great but
we're not sure". A player with 500 matches at $\mu = 38$ and
$\sigma = 1$ actually has a higher conservative score (35 vs 22) and
deserves the higher leaderboard position.

In `elo_engine`, `RankingComparison.trueskillRanking` sorts by
`conservativeScore` for exactly this reason. Displaying $\mu$ alone
would punish newcomers with lucky streaks and reward veterans with
long, boring records — which is the inverse of what you want from a
leaderboard.

## Failure modes

**No volatility tracking.** Unlike Glicko-2, vanilla TrueSkill
assumes true skill is *static*. If a player actually gets better over
time, their $\sigma$ has already shrunk and the updates move $\mu$
too slowly. Microsoft's production Halo system added a small
additive $\sigma$ increase per match to counter this; `elo_engine`'s
TrueSkill implementation does not. If your users improve
measurably during a session (a baby-name ranker won't, a Halo match
will), keep that caveat in mind.

**The truncation approximation breaks at extreme rating gaps.** The
$v$ and $w$ corrections come from the standard normal CDF and are
accurate for $|t| < 5$ or so. For ratings that are essentially
deterministic (gap of 20+ standard deviations), you get numerical
weirdness. Rare in practice.

**Ties are approximated.** The canonical TrueSkill draw update uses a
"draw margin" parameter $\varepsilon$ that most implementations set
to zero. `elo_engine` approximates a tie as the average of a win and
a loss update, preserving the correct qualitative behavior ($\mu$
barely changes for equal opponents, both $\sigma$s shrink) without
introducing another tunable knob.

## Why use it alongside Glicko-2?

Both algorithms produce similar-shaped output: a $\mu$ and a
$\sigma$ per item, with the interpretation that narrower $\sigma$
means more confident rating. In practice they produce rankings that
correlate very highly — but not identically.

When they **agree**, you have strong evidence that your ranking is
real.

When they **disagree**, the source of the disagreement is usually
informative: Glicko-2's volatility term may have flagged a player as
unstable, while TrueSkill (without volatility) rated them
confidently. This is a nudge that the player's underlying skill may
be changing, and you should probably trust Glicko-2.

## In `elo_engine`

- State lives in private `_trueSkillStates` inside `EloEngine`.
- Updated live inside `record()` when `AlgorithmId.trueskill` is
  enabled.
- Exposed via `RankingComparison.trueskillRanking`, sorted by
  `conservativeScore` descending.
- Disabling TrueSkill in `enabledAlgorithms` saves CPU on the match
  hot path — all the $v/w$ lookups and belief updates are skipped.

## One-sentence summary

TrueSkill is Gaussian belief propagation over a factor graph;
`elo_engine` uses the 1v1 closed form, which behaves a lot like
Glicko-2 but makes different assumptions and so serves as a useful
cross-check.

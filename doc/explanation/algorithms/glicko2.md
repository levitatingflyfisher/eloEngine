# Glicko-2

## TL;DR — when to pick it

Enable Glicko-2 when you want ELO-style live ranking **plus a measure
of uncertainty**. Glicko-2 tells you not just "Oliver's rating is
1412" but also "…and we're pretty sure about that, the error bar is
about 65 points" — or conversely, "Eliot's rating is 1800 but we've
barely seen him, so anywhere from 1400 to 2200 is plausible". Use it
for leaderboards that need to distinguish "locked in" from "still
figuring it out", for matchmaking (pair players whose uncertainty
overlaps), and for any system where the user asks "how sure are you?".

## The problem with plain ELO

ELO gives every player one number, and every match moves that number
by `K × (result − expected)`. This has a hidden assumption: **all
ratings are equally certain**. A brand new player at 1200 is treated
identically to a 500-match veteran at 1200. That's wrong. The veteran
has earned that 1200; the newcomer is just *provisionally* there until
evidence arrives.

Classical ELO papers over this with the K-factor schedule — "new
players get K=64, veterans get K=16". That's a coarse proxy for
uncertainty and it is all one number can express. What you actually
want is to track, *separately*, "what do we think the rating is" and
"how sure are we". That is what Glicko-2 does.

## The core idea

Glicko-2 represents each player as a **Gaussian distribution over
rating** — a bell curve, not a point. Two numbers summarize the
distribution:

- $\mu$ — the center of the bell curve, which is the best guess for
  the player's true rating.
- $\phi$ — the width of the bell curve (rating deviation, or RD).
  High $\phi$ means we're guessing; low $\phi$ means we're
  confident.

Glicko-2 adds a third:

- $\sigma$ — **volatility**. How much has this player's underlying
  skill been changing? A player whose results have been steady gets
  low $\sigma$. A player who just jumped three rating classes gets
  high $\sigma$, and Glicko-2 responds by widening their RD faster.

So a Glicko-2 player is a bell curve that also **breathes** — it
widens when the player surprises us, narrows when they don't play for
a while (wait, see below), and shifts as matches happen.

## How a match updates the state

Glickman (2012) derives the update from Bayesian statistics, but
here's what the math is doing in plain English:

1. **Predict** the match. Glicko-2 computes the expected score for A
   against B, but — crucially — it takes B's uncertainty into
   account. Facing a wide-RD opponent is *less informative* than
   facing a narrow-RD opponent, because the wide one might be anyone.

2. **Measure the surprise.** Did the result match the prediction? How
   badly?

3. **Update $\mu$** toward where the surprise points. Like ELO, but
   scaled by each side's uncertainty.

4. **Update $\phi$** — shrink it, because we just learned something.
   The more informative the match (i.e., the narrower the opponent's
   RD), the more we shrink.

5. **Update $\sigma$** — if the player's results are inconsistent with
   their current rating, push volatility up; if they're consistent,
   push it down. This lets Glicko-2 notice when someone's actual
   skill is drifting.

Between matches, $\phi$ **grows over time** — because the longer it
has been since we saw this player, the less we know about their
current skill. In `elo_engine`, this "rating period" drift is not
applied explicitly; we treat every session as a single period. That's
fine for most consumer apps.

## Worked example

Three items start at the Glicko-2 defaults: $\mu = 1500$ (the
Glicko-2 starting rating, re-scaled in `elo_engine` to match
`startingRating`), $\phi = 350$, $\sigma = 0.06$.

Oliver beats Eliot. Because both RDs are large (350 is Glickman's
"maximum uncertainty"), this single match is quite informative: neither
side had strong priors. Oliver's $\mu$ moves sharply upward (much more
than ELO's +16 would move), and *both* players' $\phi$ shrinks
noticeably.

Now Oliver beats Eliot a second time. Because Oliver's $\phi$ is now
smaller, his expected score is higher, and so the surprise-per-match
is smaller. His $\mu$ still moves up, but less. His $\phi$ shrinks
again, but less. Classical "diminishing returns on a repeated result".

Now Oliver loses to Eliot. Surprise! Oliver's $\mu$ drops. But also —
because the result contradicts the trend — his $\sigma$ creeps up,
which will prevent his $\phi$ from shrinking as quickly next time.
Glicko-2 just noticed that Oliver's skill might be less settled than
it thought.

## The "confidence interval" interpretation

A Glicko-2 player's 95% confidence interval for their true rating is
approximately $\mu \pm 2\phi$ (on the display scale, $\mu \pm 2
\cdot \text{RD}$). Use this in your UI:

- If two players' intervals **overlap heavily**, you cannot reliably
  say one is better. Match them more.
- If a player's interval is **wider than 200 rating points**, their
  rating is still provisional.
- If a player's interval is **narrower than 50 points**, their rating
  is locked in; further matches will barely move it.

This is the single most useful thing Glicko-2 gives you that ELO does
not.

## Why two scales?

Internally, Glickman's equations use a **standardized scale** where
$\mu$ is measured in standard-deviation units around 1500. The
"display rating" you see in leaderboards is
$173.7178 \cdot \mu + 1500$, and display RD is $173.7178 \cdot \phi$.
The constant 173.7178 is chosen so that the natural-log updates of
Glicko-2 map cleanly onto the base-10 log scale that chess ELO uses.
You should never need to care about this unless you are
re-implementing Glicko-2 by hand.

In `elo_engine`, you access both via `Glicko2State.mu` (internal) and
`Glicko2State.displayRating` (what to show users).

## Failure modes

**Too few matches.** Glicko-2 is only as good as the information it
gets. A player with 3 matches has a huge $\phi$ — all three matches
are worth taking seriously, but the overall rating is genuinely
uncertain. Do not trust the ranking; trust the *interval*.

**All-wins or all-losses streaks.** A new player who wins all 5 first
matches will get $\mu$ pushed very high very fast, with $\phi$
shrinking quickly. If this player is genuinely a novice who just got
lucky, Glicko-2 will eventually recover — volatility rises when later
matches contradict the rating. But the initial response is
overconfident. Mix in low-K "warmup" matches if this matters for your
UX.

**The volatility constraint τ.** Glickman's τ parameter (not exposed
in `elo_engine`; we use the standard 0.5) controls how much volatility
is allowed to change per rating period. If τ is too low, Glicko-2 is
slow to notice genuine skill changes. If τ is too high, it will
mistake noise for skill change. 0.5 is a safe, well-tested default.

## In `elo_engine`

- State lives in private `_glicko2States` inside `EloEngine`.
- Updated live inside `record()` when `AlgorithmId.glicko2` is enabled.
- Exposed via `RankingComparison.glicko2Ranking` — sorted by the
  **conservative estimate** $\mu - 2\phi$, which is the standard
  Glicko-2 leaderboard score.
- Disabling Glicko-2 in `enabledAlgorithms` saves real CPU on the
  match hot path, because the per-match update is skipped entirely.

## One-sentence summary

Glicko-2 is ELO with error bars — every rating is a bell curve that
tightens with evidence and widens with surprise.

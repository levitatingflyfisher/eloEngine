# Thurstone (Case V)

## TL;DR — when to pick it

Enable Thurstone when you want a **statistical ranking model** very
similar to Bradley-Terry but grounded in **Gaussian performance**
assumptions rather than logistic ones. Thurstone predates Bradley-Terry
by two decades and shows up in psychometrics, product ranking
literature, and some applied statistics curricula. It produces
rankings almost identical to Bradley-Terry's on most data, but with
slightly different tails — a useful cross-check, and the "I'm
assuming normal performance" answer to any reviewer who asks.

## The historical setup

Louis Thurstone was an American psychologist who, in 1927, published
"A law of comparative judgment". The question he was attacking:
given a pile of pairwise preferences ("which flavor is sweeter?",
"which face is more trustworthy?"), how do you turn them into a
single ranking on a psychological scale?

Thurstone's answer: model each item's appearance on a judgment trial
as a Gaussian random variable around its true "scale value". When
item $i$ and item $j$ are compared, you draw a perceived strength
for each:

$$ s_i \sim \mathcal{N}(\mu_i, \sigma^2), \quad s_j \sim \mathcal{N}(\mu_j, \sigma^2) $$

and the observer picks whichever has the larger perceived strength.
The probability that $i$ is chosen over $j$ is then

$$ P(i > j) = \Phi\left(\frac{\mu_i - \mu_j}{\sigma\sqrt{2}}\right) $$

where $\Phi$ is the standard normal CDF. "Case V" refers to Thurstone's
assumption that all items share the same variance $\sigma^2$ and that
the perceptions of different items are independent. This is the
simplest and most commonly fit version, and it's what `elo_engine`
implements.

## Compared to Bradley-Terry

The two models are almost the same thing. Both say: each item has a
latent number, and the probability one beats another is a smooth
function of the difference.

- Bradley-Terry uses the **logistic** function: $\sigma(x) =
  1/(1 + e^{-x})$.
- Thurstone uses the **probit** function: $\Phi(x)$ (standard normal CDF).

These two S-curves are visually indistinguishable in the middle
region and differ only at the extremes. The logistic has slightly
fatter tails; the probit decays faster.

Practically, the fits will agree on 99% of the ranking. The last 1%
is where the data has extreme outliers (e.g., one item that beats
everyone). In those cases, Thurstone's faster-decaying tails are
sometimes slightly more stable.

## Worked example

Three items, A, B, C. You observe:
- A beats B: 4-1
- B beats C: 3-2
- A beats C: 5-0

Thurstone wants to pick $\mu_A, \mu_B, \mu_C$ (with
$\sigma$ fixed at 1 for identifiability) to maximize the likelihood
of this data.

Start: $\mu = (0, 0, 0)$.

- Observed AB win rate: 4/5 = 0.8. Predicted: $\Phi(0) = 0.5$.
  Gradient push on $\mu_A$: positive. Push on $\mu_B$: negative.
- Observed BC win rate: 3/5 = 0.6. Push $\mu_B$ up, $\mu_C$ down.
- Observed AC win rate: 5/5 = 1.0. Push $\mu_A$ up very hard,
  $\mu_C$ down very hard.

After a few iterations of gradient ascent (or Newton's method, which
converges faster), the fit settles around:
- $\mu_A \approx +1.1$ (clearly strongest)
- $\mu_B \approx +0.2$ (middle)
- $\mu_C \approx -1.2$ (clearly weakest)

The predicted win rates from these: $\Phi(1.1 - 0.2)/\sqrt{2} \approx
\Phi(0.636) \approx 0.74$ (vs observed 0.8), $\Phi(0.2 + 1.2)/\sqrt{2}
\approx 0.84$ (vs observed 0.6)… the fit is imperfect because five
matches over three items is thin data, but the ranking is clearly
A > B > C.

## The probit vs logit choice, in one paragraph

Why would you ever pick probit over logit? Historically, Thurstone
came first, so psychometrics adopted it. The Gaussian assumption is
also slightly more defensible when you believe the underlying
"strength on any given trial" is genuinely normally distributed —
which shows up in sensory discrimination tasks (is this tone louder?)
where the underlying perceptual noise really is Gaussian by the
Central Limit Theorem. For social or skill comparisons, the choice
is largely cosmetic.

## Signals that Thurstone handles a bit differently than Bradley-Terry

**Sweeps.** A item that wins 10-0 against another: Bradley-Terry
pushes its strength toward infinity (and has to be regularized);
Thurstone's faster-decaying Gaussian tail forces a finite answer
sooner. In practice, Thurstone gives slightly more conservative
rankings on perfect records.

**Intermediate cases.** When one item has a 60% win rate, both
models give essentially the same answer.

**Extreme rating gaps.** At 95%+ predicted win rate, the logistic
still predicts 0.99 for truly lopsided matches while the probit
predicts 0.9999 much sooner. Tiny differences in the fit.

## The ranking is what you want; the absolute numbers are not

Thurstone's absolute $\mu$ values depend on the choice of scale
(we fix $\sigma = 1$) and the reference item. Only **differences**
between $\mu$s are meaningful. Sort by $\mu$, report the sort
order — don't tell users "your Thurstone score is 1.3" because 1.3 is
meaningless without context.

`elo_engine` exposes only the sorted list (`thurstoneRanking`) for
this reason.

## Failure modes

**Same as Bradley-Terry.** Disconnected match graphs make the
ranking between clusters meaningless. Perfect sweeps push estimates
hard. Sparse data gives imprecise point estimates with no
uncertainty quantification.

**No uncertainty output.** The MLE is a single point. If you want
"how sure are we", stack Thurstone with Glicko-2 or TrueSkill, which
explicitly track posterior variance.

**Convergence assumes connectivity.** If items A and B have never
played each other directly or transitively (through common
opponents), the relative scale is indeterminate. Keep the budget
bounded (we iterate for a fixed count) and accept that disconnected
items get arbitrary relative ranks.

## In `elo_engine`

- Computed inside `compareAlgorithms()` when
  `AlgorithmId.thurstone` is enabled.
- Exposed as `RankingComparison.thurstoneRanking`, sorted descending
  by the fitted $\mu_i$.
- Uses gradient ascent on the Gaussian-CDF log-likelihood with a
  fixed iteration budget. Cost is similar to Bradley-Terry ($O(N^2
  \cdot I)$), but with a slightly more expensive per-step
  computation (normal CDFs are slower than logistics).

## One-sentence summary

Thurstone is Bradley-Terry with a probit link instead of a logit —
almost the same model, almost the same answer, but valuable as an
independent cross-check and as a historically grounded "Gaussian
performance" baseline.

# Range-limb security regression candidates (UNTESTED)

These cases are proposals for `Examples.EUair` on upstream PR #5, **not runnable against the fork's current `base` branch**. The fork branch contains documentation only until the upstream change is merged or ported.

## Candidate cases
1. Mutate a single 8-bit limb while preserving its parent 32-bit column; the prover should reject.
2. Set a limb cell to 256 (outside Word(8)); the prover should reject.
3. Mutate a limb only at the final padded row while leaving the parent column unchanged; the back-shifted spelling should force rejection.

## Important validation notes
- Existing `pointer_bounds_have_fixed_degree` and `forged_remainder_verdicts` examples already cover related cases. Confirm the proposed tests add coverage rather than duplicate it.
- Use `slacked_trace()` from `lib/examples/e_uair.ex`, selecting `{bounded, [low | _]}` from `uair.limbs`.
- Assert the parent column remains unchanged and the limb changes, then assert `{:error, _}` from `Prover.prove_uair/1`.
- Verify both base and patched behavior where applicable; run the complete Elixir/Rust suite before proposing a PR.
- No tests have been executed, and no new vulnerability is claimed.
- This is independent of ModulusZK unless an implementation link is established.

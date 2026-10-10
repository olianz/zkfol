# Candidate tests for Examples.EUair on zkFOL PR #5
# UNTESTED. This file is a snippet, NOT a standalone runnable ExUnit suite.
# Requires PR #5's Uair.limbs field and Examples.EUair context.

  @doc "A tampered limb must be rejected while its parent value stays unchanged."
  example changing_only_a_limb_is_refused do
    uair = slacked_trace()
    assert [{bounded, [low | _]} | _] = uair.limbs
    original_parent = Enum.at(uair.columns, bounded)
    original_limb = Enum.at(uair.columns, low)

    changed =
      List.update_at(uair.columns, low, fn cells ->
        List.update_at(cells, 0, &rem(&1 + 1, 256))
      end)

    assert changed != uair.columns
    assert Enum.at(changed, bounded) == original_parent
    assert Enum.at(changed, low) != original_limb
    assert {:error, _reason} = Prover.prove_uair(%{uair | columns: changed})
  end

  @doc "A limb outside the Word(8) table must be rejected."
  example a_limb_above_255_is_refused do
    uair = slacked_trace()
    assert [{_bounded, [low | _]} | _] = uair.limbs
    changed = List.update_at(uair.columns, low, &List.replace_at(&1, 0, 256))
    assert {:error, _reason} = Prover.prove_uair(%{uair | columns: changed})
  end

  @doc "A tampered final padded row limb must be rejected."
  example a_final_row_limb_tamper_is_refused do
    uair = slacked_trace()
    assert [{bounded, [low | _]} | _] = uair.limbs
    last = length(Enum.at(uair.columns, low)) - 1
    original_parent = Enum.at(uair.columns, bounded)

    changed =
      List.update_at(uair.columns, low, fn cells ->
        List.update_at(cells, last, &rem(&1 + 1, 256))
      end)

    assert Enum.at(changed, bounded) == original_parent
    assert Enum.at(changed, low) != Enum.at(uair.columns, low)
    assert {:error, _reason} = Prover.prove_uair(%{uair | columns: changed})
  end

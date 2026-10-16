defmodule Zkfol.Prover do
  @moduledoc """
  I own the Zinc+ boundary: the one actor the NIF answers to. I queue a
  proof, and when the verdict lands I record it on the log as the
  intent's observation. Waiters hear of it through the log, not from me.
  """

  use GenServer
  use EventBroker.DefFilter
  use TypedStruct

  alias Zkfol.Log
  alias Zkfol.Refusal
  alias Zkfol.Uair

  # I match the log event that settles `intent`: its observation.
  deffilter Settled, intent: pos_integer() do
    %EventBroker.Event{body: %Zkfol.Log.Event{basedon: ^intent}} -> true
    _ -> false
  end

  typedstruct module: Report, enforce: true do
    @moduledoc """
    I am the verdict as a value: the NIF's measurements and the claims
    the verifier read in the clear. I ride the log as the body of a
    `{:proved, report}` observation, and I exist only where the proof
    verified — a run that did not leaves `{:prove_failed, reason}`
    instead, so my existence is the verdict and no field restates it.
    """
    field(:prove_ms, float())
    field(:verify_ms, float())
    field(:num_vars, non_neg_integer())
    field(:public_cols, non_neg_integer())
    field(:proof_bytes, non_neg_integer())
    field(:backend, String.t())
    field(:claims, [{String.t(), non_neg_integer()}])
  end

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc "I queue `uair` under `intent` and return once it is in flight."
  @spec run(Uair.t(), pos_integer(), keyword()) :: :ok | {:error, Refusal.t()}
  def run(uair, intent, opts \\ []), do: GenServer.call(__MODULE__, {:run, uair, intent, opts})

  @impl true
  def init(inflight) do
    # Trapping exits makes terminate/2 run on the way down: verdicts
    # owed at death still settle on the log, as failures.
    Process.flag(:trap_exit, true)
    {:ok, inflight}
  end

  @impl true
  def handle_call({:run, uair, intent, opts}, _from, inflight) do
    with {:ok, claims} <- report_claims(uair),
         {:ok, req} <- Uair.request(uair, opts) do
      {:reply, :ok, Map.put(inflight, req, {intent, claims})}
    else
      {:error, _reason} = error -> {:reply, error, inflight}
    end
  end

  @impl true
  def handle_info({:zinc_plus, req, result}, inflight) do
    case Map.pop(inflight, req) do
      {nil, inflight} ->
        {:noreply, inflight}

      {{intent, claims}, inflight} ->
        case result do
          {:ok, report} ->
            Log.push({:proved, struct!(Report, Map.put(report, :claims, claims))}, intent)

          {:error, reason} ->
            Log.push({:prove_failed, Refusal.from_backend(reason)}, intent)
        end

        {:noreply, inflight}
    end
  end

  @spec report_claims(Uair.t()) ::
          {:ok, [{String.t(), non_neg_integer()}]} | {:error, Refusal.t()}
  defp report_claims(%Uair{claims: claims} = uair) do
    cols =
      claims
      |> Enum.flat_map(fn
        {_name, row, _x} -> [row]
        _claim -> []
      end)
      |> Enum.uniq()
      |> Enum.with_index()
      |> Map.new()

    Refusal.map(claims, &report_claim(uair, cols, &1))
  end

  @spec report_claim(Uair.t(), map(), term()) ::
          {:ok, {String.t(), non_neg_integer()}} | {:error, Refusal.t()}
  defp report_claim(
         %Uair{columns: columns, len: len, num_public: num_public},
         cols,
         {name, row, x}
       )
       when is_binary(name) and is_integer(row) and is_integer(x) and x >= 1 and x <= len do
    with {:ok, column} <- Map.fetch(cols, row),
         true <- column < num_public,
         {:ok, values} <- Enum.fetch(columns, column),
         {:ok, value} <- Enum.fetch(values, len - x) do
      {:ok, {name, value}}
    else
      _outside -> {:error, {:claim_outside_witness, %{claim: name, row: row, column: x}}}
    end
  end

  defp report_claim(_uair, _cols, {name, row, x}),
    do: {:error, {:claim_outside_witness, %{claim: name, row: row, column: x}}}

  defp report_claim(_uair, _cols, claim),
    do: {:error, {:claim_outside_witness, %{claim: claim, row: nil, column: nil}}}

  @impl true
  def terminate(_reason, inflight) do
    for {_req, {intent, _claims}} <- inflight do
      Log.push({:prove_failed, {:prover_died, %{}}}, intent)
    end
  end
end

defmodule Buckets.TokenBucket do
  @moduledoc """
  A Token Bucket fills with tokens at a regular rate, up until a preset limit.
  Another process may ask if the bucket is empty or not. Each empty request
  drains a token from the bucket.

  See [Token Bucket Algorithm](https://en.wikipedia.org/wiki/Token_bucket)
  """

  use GenServer

  alias Buckets.SternBrocot

  @doc """
  Create a Token Bucket process that allows 10 requests per second:

      {:ok, pid} = Buckets.TokenBucket.start(10)
      Buckets.TokenBucket.empty?(pid)

  """
  def start(args, opts \\ []) do
    GenServer.start(__MODULE__, args, opts)
  end

  @spec init(pos_integer) :: {:ok, map}
  def init(rps) when is_integer(rps) and rps > 0 do
    [tokens: tokens, interval_ms: interval_ms] = SternBrocot.find(rps)

    bucket = %{
      :max_tokens => rps,
      :tokens => rps,
      :refill_tokens => tokens,
      :interval_ms => interval_ms
    }

    Process.send_after(self(), :refill, interval_ms)

    {:ok, bucket}
  end

  @doc """
  Returns true if the bucket is empty, otherwise false.
  Removes a token from the bucket after the test.
  """
  @spec empty?(pid) :: boolean
  def empty?(pid) do
    GenServer.call(pid, :empty)
  end

  # Callbacks

  @doc """
  Each call to this function removes a token from the bucket.
  Returns true if the bucket is not empty before the call is made,
  otherwise false if empty.
  """
  def handle_call(:empty, _from, bucket) do
    new_bucket = Map.update(bucket, :tokens, 0, &dec_to_zero/1)

    case Map.get(bucket, :tokens, 0) do
      0 -> {:reply, true, new_bucket}
      _ -> {:reply, false, new_bucket}
    end
  end

  @doc """
  Add tokens to the bucket, and schedule the next refill.
  """

  def handle_info(:refill, bucket) do
    %{
      max_tokens: max_tokens,
      refill_tokens: refill_tokens,
      tokens: tokens_in_bucket,
      interval_ms: interval_ms
    } = bucket

    Process.send_after(self(), :refill, interval_ms)
    more_tokens = Enum.min([tokens_in_bucket + refill_tokens, max_tokens])
    {:noreply, %{bucket | :tokens => more_tokens}}
  end

  @doc """
  Decrement n, minimum value is zero.
  """
  @spec dec_to_zero(integer) :: non_neg_integer
  def dec_to_zero(n) do
    if n > 0 do
      n - 1
    else
      0
    end
  end
end

defmodule Cortex.Utils.SafeAtom do
  @moduledoc """
  Utilities for safe atom conversion to prevent atom exhaustion (DoS attacks).
  """

  @doc """
  Converts a string to an atom only if it already exists.
  Returns `{:ok, atom}` or `{:error, :not_found}`.
  """
  def to_existing(binary) when is_binary(binary) do
    {:ok, String.to_existing_atom(binary)}
  rescue
    ArgumentError -> {:error, :not_found}
  end

  def to_existing(atom) when is_atom(atom), do: {:ok, atom}

  @doc """
  Converts a string to an atom if it is in the allowed list.
  Returns `{:ok, atom}` or `{:error, :not_allowed}`.
  """
  def to_allowed(binary, allowed_atoms) when is_binary(binary) and is_list(allowed_atoms) do
    case Enum.find(allowed_atoms, fn a -> Atom.to_string(a) == binary end) do
      nil -> {:error, :not_allowed}
      atom -> {:ok, atom}
    end
  end

  @doc """
  Converts a string to an atom only if it already exists.
  Raises if it doesn't exist.
  """
  def to_existing!(binary) when is_binary(binary) do
    String.to_existing_atom(binary)
  end

  def to_existing!(atom) when is_atom(atom), do: atom
end

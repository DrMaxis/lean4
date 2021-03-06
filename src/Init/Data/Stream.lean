/-
Copyright (c) 2020 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Sebastian Ullrich, Andrew Kent, Leonardo de Moura
-/
prelude
import Init.Data.Array.Subarray
import Init.Data.Range

/-
  Streams are used to implement parallel `for` statements.
  Example:
  ```
  for x in xs, y in ys do
    ...
  ```
  is expanded into
  ```
  let mut s := toStream ys
  for x in xs do
    match Stream.next? s with
    | none => break
    | some (y, s') =>
      s := s'
      ...
  ```
-/
class ToStream (collection : Type u) (stream : outParam (Type u)) : Type u where
  toStream : collection → stream

export ToStream (toStream)

class Stream (stream : Type u) (value : outParam (Type v)) : Type (max u v) where
  next? : stream → Option (value × stream)

/- Helper class for using dot-notation with `Stream`s -/
structure StreamOf (ρ : Type u) where
  s : ρ

abbrev streamOf (s : ρ) :=
  StreamOf.mk s

@[inline] partial def StreamOf.forIn [Stream ρ α] [Monad m] [Inhabited (m β)] (s : StreamOf ρ) (b : β) (f : α → β → m (ForInStep β)) : m β := do
  let rec @[specialize] visit (s : ρ) (b : β) : m β := do
    match Stream.next? s with
    | some (a, s) => match (← f a b) with
      | ForInStep.done b  => return b
      | ForInStep.yield b => visit s b
    | none => return b
  visit s.s b

instance : ToStream (List α) (List α) where
  toStream c := c

instance : ToStream (Array α) (Subarray α) where
  toStream a := a[:a.size]

instance : ToStream (Subarray α) (Subarray α) where
  toStream a := a

instance : ToStream String Substring where
  toStream s := s.toSubstring

instance : ToStream Std.Range Std.Range where
  toStream r := r

instance [Stream ρ α] [Stream γ β] : Stream (ρ × γ) (α × β) where
  next? | (s₁, s₂) =>
    match Stream.next? s₁ with
    | none => none
    | some (a, s₁) => match Stream.next? s₂ with
      | none => none
      | some (b, s₂) => some ((a, b), (s₁, s₂))

instance : Stream (List α) α where
  next?
    | []    => none
    | a::as => some (a, as)

instance : Stream (Subarray α) α where
  next? s :=
    if h : s.start < s.stop then
      have s.start + 1 ≤ s.stop from Nat.succLeOfLt h
      some (s.as.get ⟨s.start, Nat.ltOfLtOfLe h s.h₂⟩, { s with start := s.start + 1, h₁ := this })
    else
      none

instance : Stream Std.Range Nat where
  next? r :=
    if r.start < r.stop then
      some (r.start, { r with start := r.start + r.step })
    else
      none

instance : Stream Substring Char where
  next? s :=
    if s.startPos < s.stopPos then
      some (s.str.get s.startPos, { s with startPos := s.str.next s.startPos })
    else
      none
